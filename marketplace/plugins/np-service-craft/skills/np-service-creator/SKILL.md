---
name: np-service-creator
description: This skill should be used when the user asks to "register a service in terraform", "publish a service package", "wire a service worker", "create service_definition module", "create agent binding", or needs to work with terraform modules for nullplatform service registration.
---

# Nullplatform Service Creator — Terraform Registration

Terraform patterns for registering services and publishing them as packages run by workers.

## Critical Rules

1. **Confirm before `tofu apply`** — explain what will be created and why.
2. **NEVER hardcode module variables from memory** — read them from the module source at the
   ref you are pinning. The `package` variable's own description is the contract.
3. **Packaging is a mode of `service_definition`, not a different module.** Set its `package`
   block and set `worker_orchestrator = true` on the agent association. Both layers still
   apply, in order. → `/np-package-builder` for the model behind it.
4. **State `type = "oci_image"` on the artifact.** It defaults to `git_repository`, and an
   `oci_image` that omits `repository` falls back to `nullplatform/scopes/containers` — it
   packages the platform's image instead of yours, without failing.
5. **Add your registry to `worker.allowedRegistries`.** It defaults to
   `["public.ecr.aws/nullplatform/*"]`, so a custom image is silently never pulled.
6. **`repository_*` fields are still required when packaged** — the module reads the spec
   files over HTTPS on every apply. `repository_branch` must be a tag; the module rejects
   `main`.

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md

## The model, and who owns it

A service ships as an **OCI image** built on the worker-bridge base; `service_definition`
publishes a **package revision** whose BOM pins the specs and that image; the agent
association emits a **package-exec channel** so the agent spawns a **worker** from it.

**The package model itself belongs to `/np-package-builder`** — the worker-bridge image
contract and its `NP_*` variables, how the agent runs and routes to workers,
`allowedRegistries` and chart config, the artifact reference forms, the
`np package init/build/run/publish` CLI, the plugin SDK, and migrating a legacy
git-cloned scope or service. Read it there; do not restate it here.

This skill covers what is specific to registering a **service**: its two terraform layers,
the spec/link/action wiring, and the gotchas of that path.

@${CLAUDE_PLUGIN_ROOT}/skills/np-service-creator/docs/packaged-service.md

## Module Source of Truth

| Module | Path | Purpose |
|--------|------|---------|
| `service_definition` | `nullplatform/service_definition/` | Specs + (with `package`) the package revision |
| `service_definition_agent_association` | `nullplatform/service_definition_agent_association/` | The channel — package-exec with `worker_orchestrator`, git-clone exec without |
| `agent` | `nullplatform/agent/` | Runs the workers |
| `packaged_service` | `nullplatform/packaged_service/` | Packages spec resources you declare by hand. Creates no channel — not the path for a crafted service |

`scope_definition` packages a scope type the same way; that, and the CLI alternative
(`np package publish`, interchangeable with a terraform apply), are covered in
`/np-package-builder`.

The **v7 line** implements packages and workers — any `v7.x.x` has the model.

```bash
git clone --depth 1 --branch <ref> https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref
```

Do not copy variables from this skill — infer them from the source each time.

## Reference implementations

The GitHub organization is always **`nullplatform`**.

| Service | Repo | Cloud |
|---|---|---|
| AWS S3 Bucket | `nullplatform/services-s-3` | AWS |
| Azure Blob Storage | `nullplatform/services-blob-storage` | Azure |
| PostgreSQL on K8s | `nullplatform/services-postgresql-k-8-s` | cloud-neutral — runs on the cluster |

All three share the layout and Dockerfile shape in `packaged-service.md` and differ only in
slug and in which tools the image installs. PostgreSQL on K8s is the most useful reference
when the service is not tied to one cloud.

### Resolving the ref: latest release, then verify

**Do not hardcode a ref.** Resolve the latest release at the moment you use it:

```bash
REPO=services-s-3
REF=$(git ls-remote --tags https://github.com/nullplatform/$REPO \
      | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' | sort -V | tail -1)
```

Then **verify that ref actually carries the packaged structure** before copying from it — a
release can predate the package model, and a tag can point at a scaffold:

```bash
curl -sf "https://raw.githubusercontent.com/nullplatform/$REPO/$REF/Dockerfile" \
  | grep -q "worker-bridge" && echo "packaged" || echo "NOT packaged — try the default branch"
```

If the latest release is not packaged, fall back to the default branch and tell the user
which ref you ended up using.

These repos release often, so treat any version named here as a floor, not as current:
`services-s-3` is packaged from `v0.3.0` on, `services-postgresql-k-8-s` from `v1.0.2`, and
`services-blob-storage` from `v0.1.0` — its earlier `0.0.1` tag still points at a
pre-service scaffold. Resolve the actual ref with the command above rather than reusing one
of these.

## Migrating a legacy service

Moving a git-cloned service to packages — image, artifact, `package` block,
`worker_orchestrator`, dropping `agent_repo` — is documented end to end in
`/np-package-builder`. Follow it there, then use the checklist below for the
service-specific parts.

## Pre-Registration Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | Schema in `attributes.schema` | `jq -e '.attributes.schema.type' <slug>/specs/service-spec.json.tpl` |
| 2 | No `specification_schema` | `jq -e '.specification_schema' <slug>/specs/service-spec.json.tpl` must fail |
| 3 | Links use `attributes.schema` | `jq -e '.attributes.schema' <slug>/specs/links/*.json.tpl` |
| 4 | Artifact states `type = "oci_image"` plus registry and repository | read the `package` block |
| 5 | `repository_branch` is a tag, not a branch | read the module block |
| 6 | Image digest matches what was pushed | `docker buildx imagetools inspect <ref>` |
| 7 | Baked entrypoint matches the association's `entrypoint` | compare Dockerfile `ENV` with the module default |
| 8 | Registry is in `worker.allowedRegistries` | read the agent layer |
| 9 | Fields with `export: true` have write_outputs | verify scripts exist in the image |
