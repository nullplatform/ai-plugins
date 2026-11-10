# The worker-bridge image contract

`worker-bridge` is the base image for workflow-style packages (the scopes /
services family: scopes-lambda, scopes-static-files, services-s-3,
services-endpoint-exposer, services-postgresql-rds…). It carries the gRPC
worker server; the package supplies content + an entrypoint script. This is the
alternative to the SDK runtime — same agent, same gRPC contract, bash/tofu
instead of TypeScript.

## The Dockerfile shape (real, from the service repos)

```dockerfile
FROM public.ecr.aws/nullplatform/worker-bridge:1.0.0

# per-package tooling — whatever the workflows call
RUN apk add --no-cache aws-cli gomplate  # (+ tofu, kubectl, postgresql16-client…)

COPY . /app/pkg

ENV NP_PACKAGE_NAME=my-service \
    NP_SERVICE_PATH=/app/pkg/my-service \
    NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
```

- **`/app/pkg`** — the whole repo baked in (workflows, specs, scripts,
  `service/` shared handlers).
- **`NP_PACKAGE_NAME`** — must match the channel's package selector.
- **`NP_SERVICE_PATH`** — where this package's workflows/specs live.
- **`NP_SCOPE_ENTRYPOINT`** — the dispatch script the bridge execs per action.
- The bridge listens on `NP_GRPC_LISTEN` (agent sets it, default :50051) and
  runs as root by design (Trivy AVD-DS-0002 is suppressed with a documented
  `.trivyignore` in these repos — inherit it, don't re-litigate).

## The entrypoint dispatch (what actually runs)

The entrypoint script:
1. Reads `NP_ACTION_CONTEXT` (the action JSON, sometimes shell-quoted — strip
   quotes), extracts `notification`, resolves `scope_id` from
   parameters/tags/arguments.
2. Routes by action to a handler under `$NP_SERVICE_PATH` (e.g.
   `service/scope/entrypoint` → `Executing scope action=create-scope`).
3. Handlers run workflows:
   `np service workflow exec --workflow $NP_SERVICE_PATH/scope/workflows/create.yaml --build-context --include-secrets`.

So a worker-bridge package = directory of `workflows/*.yaml` + scripts, and the
np CLI inside the image executes them with full platform context. The CLI is
baked into the bridge; pin CI-installed CLIs to a released version (≥ 2.10.0),
never a floating channel.

## Publishing the image (the shared CI chain)

Repos on this model use `actions-nullplatform/release-publish-oci.yml@main`:
release-please cuts the version → docker buildx (multi-arch) pushes to ECR →
finalize registers the artifact:

```
np artifact create --nrn $NP_ARTIFACT_NRN --type oci_image \
  --registry <host-only> --repository <path> --digest $DIGEST \
  --tag $IMAGE_TAG --changelog-file <release-notes> \
  --annotation org.opencontainers.image.source=… \
  --annotation org.opencontainers.image.revision=<tag commit> \
  --annotation org.opencontainers.image.version=<git tag> \
  --visible-to "organization=*"
```

Everything is chained in ONE run because release-please tags with
`GITHUB_TOKEN` and bot-token events never trigger other workflows. Recovery:
`workflow_dispatch` with `existing_tag` re-publishes an existing tag with the
CURRENT workflow (builds the tag's commit via the `ref` passthrough).
Secrets/vars per repo: `AWS_ROLE_ARN_ECR_PUSH`, `ARTIFACT_NP_API_KEY`
(dedicated key), `NP_ARTIFACT_NRN`. The ECR repository must exist first — ECR
never creates on push; a 403 on push = the role's permission policy misses that
repository; "repository does not exist" = wrong name or truly missing repo.

### nullplatform's own agent plugins (`scopes-*` / `services-*`)

They start from `nullplatform/templates-scopes` or `nullplatform/templates-services`,
which already carry this chain plus a beta workflow. Images go to ECR Public as
`agent-plugins/{scopes,services}/<slug>` (older repos keep `services/<name>`; don't rename
them). What the templates do not do for you:

- **ECR repository + role**: add the **Public ECR** service (`services-public-ecr`) to the
  application, with `images` = the exact `image_name` of `release.yml`. It PRs
  `infrastructure-iac-agent-plugins` (repo, its `beta/` twin, publisher role) and writes
  `AWS_ROLE_ARN_ECR_PUSH` into the repo; its `update` retries only that secret. It refuses a
  **private** GitHub repo (`does not exist on GitHub, or is private`).
- **`NP_ARTIFACT_NRN`**: a repo variable nobody sets — do it by hand, or both `release` and
  `beta` stop at preflight.
- **Betas**: every same-repo, non-bot PR pushes `beta/<image>:test-<branch>-<short sha>` and
  registers it as its own artifact, assuming the org secret `AWS_BETA_ROLE_ARN` (writes only
  `beta/*`).
- **Release PR checks are red by design**: PRs opened by `github-actions[bot]` get their
  `pull_request` runs held, so every check on the release-please PR fails with "workflow file
  issue"; `auto-merge-release` merges it via `workflow_run`. Not a defect — and
  `branches-ignore` filters the base branch, so it can't exclude it.
- A `chore:`/`docs:` merge cuts no release; it takes `feat:` or `fix:`.
- **Spec selectors**: `category` / `sub_category` / `provider` in the service and link specs
  are what the catalog and the docs index show; the template ships `Other` / `Other` / `AWS`,
  and its release preflight refuses to publish them.
- **Repository name**: `services-<slug>` or `scopes-<slug>` — the docs sync finds repos by
  that prefix (public, with a release, no template placeholders left). A one-line GitHub
  description is welcome but optional; a new scope row uses it.
- **Public index**: after its first release the daily sync in `nullplatform/docsite` proposes
  it (a reviewed PR, up to a day) — a service in
  [Sample services](https://docs.nullplatform.com/docs/services/sample-services), one row
  per spec; a scope in [Sample scopes](https://docs.nullplatform.com/docs/agent-backed-scopes/sample-scopes), one row per scope type.
  Don't add it by hand.
