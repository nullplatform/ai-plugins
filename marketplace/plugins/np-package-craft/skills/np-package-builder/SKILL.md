---
name: np-package-builder
description: Use when the user works with nullplatform PACKAGES or the control-plane runtime around them — "np package init/build/run/publish", "create a scope/service/simple package", "scaffold a plugin", "run a local agent", "publish a package", "register an artifact with a changelog", "np artifact login/create", "how does the agent run workers", "worker bridge image", "migrate a scope to packages", "pin a worker image", "allowedRegistries", "publish a package with terraform/tofu modules", "artifact lookup by tag". Covers the CLI workflow, the agent+workers architecture and its validations, the plugin SDK, the worker-bridge image contract, old-model migration, and the tofu modules.
---

# Nullplatform Package Builder

Build a nullplatform **package** with the `np package` commands: scaffold from a
template, develop locally, run it as a real agent, and publish it to the platform.

A package = a plugin the platform runs to do work (deploy a scope, provide a
service dependency, or handle a command). The `np` CLI stays thin — it knows git
(templates), the task runner (mise/bun), docker (local agent), and the platform
API. Everything format-specific lives in the template and is invoked via tasks.

## How to work (the method this skill assumes)

1. **Verify in the source of truth, never from memory.** Runtime behavior →
   read `controlplane-agent`; chart values → `helm-charts/charts/agent`;
   API contracts → the service's schema files. Quote what the code does, not
   what it should do.
2. **CI green is not "published".** After any publish, confirm the artifact on
   the platform (`np artifact list --visible-to …`) and, when it matters, pull
   the image by digest and inspect `/app/pkg` + `NP_*` envs before trusting it.
3. **Read the actual error class.** `repository does not exist` = wrong name or
   missing ECR repo; `403 Forbidden` on push = repo exists, role permissions
   missing; OIDC `Not authorized … AssumeRoleWithWebIdentity` = trust-policy
   subject mismatch (branch vs tag vs immutable `repo:org@ID/...` subjects).
   Job conclusions lie by omission — read the failing step's log.
4. **Prefer idempotent recovery** (existing_tag dispatches, digest-guarded
   release upserts, artifact upserts) over deleting/re-pushing tags. Never
   rewrite a published tag.
5. **Live-test with real credentials when the user provides them**, with
   throwaway entities you create and delete; assert against direct API reads,
   not tool output.
6. **Annotations are last-write-wins whole-blob** — send the complete set every
   time. Artifact annotations are free-form; action-spec annotations are a
   closed vocabulary (`runs_over`, `show_on`) and other keys are silently
   stripped.

## Reference documentation (load per task)

| Task | Read |
|---|---|
| How the agent runs workers, routing, validations, chart config, hazards | `docs/architecture.md` |
| Reading/writing SDK packages, ctx surface, orchestrator boundary | `docs/sdk.md` |
| worker-bridge image contract, entrypoint dispatch, publish chain | `docs/worker-bridge.md` |
| Migrating an old git-cloned scope/service to packages | `docs/migration.md` |
| Registering packages with terraform/tofu, artifact lookup by tag/digest | `docs/tofu-modules.md` |


## When to Use

- Creating a new scope / service / simple package
- Running or testing a package locally (as a real agent, no cluster)
- Publishing / versioning a package on the platform
- Registering artifacts with release metadata (tag, changelog, annotations)
- Iterating: change code → redeploy → bump

## Prerequisites

- `np` CLI **2.10.0+** on PATH. The `np artifact` suite ships in 2.10.0; the
  `np package` suite registers **hidden** from `np --help` while it stabilizes —
  the commands are fully functional by exact name (`np package init`, …).
- `docker`, `bun`, `git`, `jq`. `k3d` + `kubectl` + `helm` only for the cluster path.
- `NP_API_KEY` (or `NULLPLATFORM_API_KEY`) exported
- `NRN` for the target app: `organization=..:account=..:namespace=..:application=..`
- SDK: `@nullplatform/plugin@0.0.5` (npm tag `latest`)

## It's two commands

```
np package init      # make the code  (pick a template → name)
np package publish   # ship it        (register on the platform)
```

Everything else (`dev` / `test` / `build` / `run`) is optional inner-loop tooling.

## Package types

`np package init` scaffolds from the **templates registry** — pick a template id
that combines a type (WHAT you're building) with an SDK (HOW it's built):

| Type | Template id | What it is |
|------|-------------|------------|
| **scope** | `scope-bun` | Deployment target — deploy apps to new infra (Kubernetes, Lambda, ECS, bare metal…) |
| **service** | `service-bun` | Application dependency — databases, caches, queues, load balancers, CDNs, observability |
| **simple** | `simple-bun` | Custom command handler — run code when the platform dispatches a command |

## Workflow

### 1. Scaffold

Interactive wizard (pick template → name):

```bash
np package init
```

Scripted / CI (`--template` takes an id, an `owner/repo`, or a git URL; `--ref`
pins a branch/tag/commit):

```bash
np package init --name "My Scope" --template scope-bun
```

(`--type` / `--sdk` still work but are deprecated in favor of `--template`.)

### 2. Develop & test

```bash
cd my-scope
np package dev        # browser dev UI (http://localhost:3847) + hot reload
np package test       # run the suite
```

### 3. Run it as a real local agent (docker, no cluster)

```bash
export NP_API_KEY=...
np package run        # builds the worker image + runs it as an agent (runtime=host)
```

It registers with the platform tagged `package:<slug>` and `local:<user>`, then
execs the package per action. Create a scope of that type in the UI → it routes
to your local agent → the action runs → the scope goes `active`. Ctrl+C to stop.

### 4. Publish

```bash
np package publish --nrn "$NRN" --image registry/repo@sha256:...
np package publish --nrn "$NRN" --dry-run     # preview what gets registered
```

One call registers: the service spec, an action spec per action, the scope type,
the agent notification channel (command type `package-exec`, sources `service` +
`telemetry` — the package's agent also serves `log:read` / `instance:data`), and
the **Package + revision + artifact**. It bumps the patch version by default
(`--bump minor|major` or `--version X.Y.Z` to override) and makes the new
revision the package default.

The push registry resolves in order: `--registry <registry>/<repo>` flag →
`$NP_PUSH_REGISTRY` → git-remote inference (`github.com → ghcr.io/...`,
`gitlab.com → registry.gitlab.com/...`, confirmed in a TTY) → hard error.

## Artifact release metadata (CLI 2.10.0)

Artifact revisions carry release metadata alongside the digest. When a CI (or
you) registers an image directly:

```bash
np artifact create \
  --nrn "$NRN" --type oci_image \
  --registry "$HOST" --repository "$REPO" --digest "$DIGEST" \
  --tag "v1.2.0" \
  --changelog-file release-notes.md \
  --annotation "org.opencontainers.image.source=https://github.com/acme/my-package" \
  --annotation "org.opencontainers.image.revision=$GIT_SHA"
```

- `--tag`: the human-readable OCI tag; identity stays registry+repository+digest.
- `--changelog` / `--changelog-file`: markdown, rendered as **release notes** in
  the spec's *Versions* tab in the console.
- `--annotation key=value` (repeatable): free-form OCI-style annotations.
- Annotations are non-identity and replace **as a whole** on re-registration
  (last write wins) — always send the complete set.

For registry login in CI without CI-stored credentials:
`np artifact login --registry "$HOST" --application-id "$APP_ID"` resolves
credentials from the application's `BUILD_DOCKER_REGISTRY_*` parameters (any
registry) or `BUILD_AWS_*` keys (exchanged for a short-lived ECR token), then
runs the docker login.

## Custom actions

Templates ship the standard scope actions (`create-scope`, `delete-scope`,
blue-green, `rollback-deployment`, `delete-deployment`, `diagnose-*`) plus a
custom example. Add your own:

1. `src/actions/<name>.ts` — a plain `async (notification, emit) => result`
2. wire it in `src/index.ts` → `actions: { "<name>": { name, type, input, handler } }`
3. `np package publish` — registers it as an action_specification

## Agent routing (optional)

A scope declares how the platform routes actions to it, in `defineScope`:

```ts
agent: {
  selector: { package: "my-scope" },               // default: { package: <name> }
  entrypoint: "/app/packages/my-scope/entrypoint",  // default from the name
}
```

Omit it for the defaults. `publish` reads this from the manifest to build the
channel.

## Iterate

Edit `src/actions/*.ts`, then:

```bash
np package run --build                       # rebuild image + rerun agent
np package publish --nrn "$NRN" --image ...  # patch bump + move default
```

## Two ways to run

| | `np package run` (local) | k3d + `np-controller` (cluster) |
|---|---|---|
| Setup | docker only | k3d + kubectl + helm + operator |
| Speed | seconds | minutes |
| Use for | inner-loop dev | "like production" checks |

## Notes

- **Format-agnostic publish**: the manifest comes from the template's own
  `describe` task, so non-bun templates work too — they just print the manifest JSON.
- **API key**: goes in `NP_API_KEY` or `NULLPLATFORM_API_KEY`. It's embedded in
  the notification channel and used to auth.
- Full CLI reference: `docs/packages.md` in the `nullplatform/cli` repo; docsite
  section: *Packages*.
