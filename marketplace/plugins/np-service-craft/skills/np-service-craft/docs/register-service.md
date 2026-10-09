# Register a service as a package

A service ships as an **OCI image**; `service_definition` publishes a **package revision**
pinning its specs and that image; the agent association emits a **package-exec channel** so
the agent spawns a **worker** from it.

→ The worker-bridge image, the agent/worker architecture and the artifact forms:
`/np-package-builder`. The service-specific parts (two layers, links, the channel's
entrypoint, operational behaviour):
@${CLAUDE_PLUGIN_ROOT}/skills/np-service-creator/docs/packaged-service.md

## Prerequisites

- `<slug>/specs/service-spec.json.tpl` exists and is valid JSON
- A `Dockerfile` at the repo root, built on `public.ecr.aws/nullplatform/scopes/worker-bridge`
- A container registry the agent is allowed to pull from
- `nullplatform/` and `nullplatform-bindings/` terraform directories

## Terraform layout

Two directories, applied in order — packaging does not change this. `nullplatform-bindings/`
reads the spec slug out of `nullplatform/` through `terraform_remote_state`.

## Flow

### 1. Read the service spec

```bash
jq '{name, slug, selectors}' <slug>/specs/service-spec.json.tpl
```

### 2. Check for collisions

```bash
grep -c "service_definition_<slug>" nullplatform/main.tf
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true" | jq '[.[] | {slug, name}]'
/np-api fetch-api "/packages?nrn=<nrn>" | jq '.results[] | {slug, name}'
```

If a specification or package with the same slug exists, ask the user to disambiguate. Do
not overwrite silently.

In a repository that already holds services, check the remote too — the API says nothing
about a directory that exists but was never registered:

```bash
git ls-tree -r --name-only origin/<branch> | grep "^<slug>/"
```

On a hit, ask with `AskUserQuestion`: **Overwrite** (confirming the previous version is
lost), **Rename** (suggest `<slug>-v2` or `<provider>-<slug>`), or **Cancel**. With the
one-repo-per-service layout this document describes, the check is usually a no-op — run it
anyway when the repo is shared.

### 2b. The specs repository is private by default

The module fetches the spec files over HTTPS on every `apply`, packaged or not, so the
repository is part of the runtime. Ask with `AskUserQuestion`, **Private first and marked
`(Recommended)`**:

- **Private (Recommended)** — needs a fine-grained token with `Contents: Read-only`, passed
  through `repository_token`. Without it the apply fails with a 404.
- **Public** — service definitions, attribute schemas and link configurations become readable
  by anyone on the internet. Require an explicit confirmation before proceeding.

**Never create or assume a public repository.** If one was created public by mistake, switch
it to private *before* continuing — the specs are already exposed until you do.

### 3. Tag the repo

`repository_branch` must be a **tag** — the module rejects `main`. Tag before building so
the image and the spec ref describe the same commit.

### 4. Build and push the image, capture the digest

Ask the user which cloud and which registry — the rest of the flow is identical on all three.

```bash
# AWS — ECR
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <registry>
docker buildx build --platform linux/amd64 -t <registry>/<repo>:<tag> . --push

# Azure — ACR (builds server-side, no local login needed)
az acr build -r <acr> --platform linux/amd64 -t <repo>:<tag> .

# GCP — Artifact Registry
gcloud auth configure-docker <region>-docker.pkg.dev
docker buildx build --platform linux/amd64 -t <region>-docker.pkg.dev/<project>/<repo>:<tag> . --push
```

Then capture the digest:

```bash
docker buildx imagetools inspect <ref> --format '{{.Manifest.Digest}}'   # AWS / GCP
az acr manifest list-metadata -r <acr> -n <repo> --query "[0].digest" -o tsv   # Azure
```

Confirm the registry is covered by the agent's `worker.allowedRegistries` (step 7), and that
the cluster can pull from it: on Azure that is `az acr update --attach-acr`, on AWS the node
role or IRSA, on GCP `artifactregistry.reader` on the node service account.

To verify the image locally before pushing, build **natively** (`docker build -t x .`) —
`--platform linux/amd64` under the legacy builder fails at `COPY` on an arm64 machine.

### 5. Generate the `nullplatform/` module

Read the module variables at the ref you are pinning — never from memory. Generate a
`service_definition` module with its `package` block carrying `version` and an `oci_image`
artifact with `registry`, `repository` and the digest from step 4, plus an output exporting
`service_specification_slug`.

**State `type = "oci_image"` explicitly.** It defaults to `git_repository`, and an
`oci_image` that omits `repository` falls back to the containers scope image without failing.

**Set `available_links` explicitly when the service has no links.** It defaults to
`["connect"]`, so a link-less service fails the apply reading a spec file that was never
written: `Invalid value for "path" parameter: no file exists at .../specs/links/connect.json.tpl`.
Pass `available_links = []`.

### 6. Generate the `nullplatform-bindings/` module

A `service_definition_agent_association` with `worker_orchestrator = true` and
`package_slug`. Check the baked entrypoint against the module's default
(`/app/packages/<slug>/entrypoint`) — the reference Dockerfiles bake `/app/pkg/<slug>/entrypoint/entrypoint`,
which does **not** match, so pass `entrypoint` explicitly unless you baked the module's path.

### 7. Wire the worker on the agent

```hcl
worker_orchestrated_packages = ["containers", "<slug>"]
worker = { allowedRegistries = ["<registry>/*"] }
extra_envs = { … }   # the worker does NOT inherit the agent's environment
```

### 8. Apply, in order

```bash
cd nullplatform          && tofu init && tofu apply -var-file=../common.tfvars
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../common.tfvars
# then the agent layer, for the worker wiring
```

Verify:

```bash
/np-api fetch-api "/packages?nrn=<nrn>"
/np-api fetch-api "/packages/<package_id>/revisions/<revision_id>"
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"
```

### 9. Release a new version

Five steps, and skipping any one leaves the previous version running:

```
tag → build and push → new digest + new package.version → tofu apply → create the service
```

The `apply` is what publishes the revision — the package is a terraform resource
(`nullplatform_artifact` + `nullplatform_package`). Edit the `.tf` and create the instance
without applying and the instance is born on the **previous** revision, which the next
paragraph then makes permanent for it.

A service instance is bound for life to the revision it was born with; promoting a new
revision does not move existing instances.

**Expect `1 to add, 1 to change, 1 to destroy` on a version bump.** A changed `meta.digest`
forces replacement of the `nullplatform_artifact` resource while the package updates
in-place. That is benign here. Do not confuse it with the same signature on the **agent**
module, where it means the Helm release is being destroyed and recreated — read which
resource the plan names before reacting.

## Legacy services

A service still on the git-clone flow keeps `agent_repo` and an association without
`worker_orchestrator`. Do not run both models against the same service. Migration steps are
in `np-service-creator`.

For the pre-registration checklist, see the `np-service-creator` skill.
