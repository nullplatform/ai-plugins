# Registering a service as a package

What crafting a **service** adds on top of the package model. The model itself —
the worker-bridge image contract, the agent/worker architecture, the artifact
reference forms, the `np package` CLI — belongs to another skill.

→ **`/np-package-builder`** owns the model. Read it for: the worker-bridge image
contract and its `NP_*` variables, how the agent runs workers and routes to them,
`allowedRegistries` and chart configuration, the three artifact reference forms,
`np package init/build/run/publish`, the plugin SDK, and migrating an old
git-cloned scope or service.

This document covers only what is specific to a **service**: how its specs, links
and actions get registered, and the operational behaviour observed while doing it.

## The shape of a service registration

Two layers, applied in order. Packaging does not change that —
`nullplatform-bindings/` still reads the spec slug out of `nullplatform/` through
remote state.

```
nullplatform/            service_definition + package = { version, artifacts }
                         publishes a revision whose BOM pins the spec, every
                         action spec, every link spec and the artifacts

nullplatform-bindings/   service_definition_agent_association
                         + worker_orchestrator = true, package_slug
                         emits a package-exec channel instead of a git-clone one
```

Read the module variables at the ref you pin — the `package` variable carries the
full contract in its own description:

```bash
git clone --depth 1 --branch <ref> https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref
```

The **v7 line** implements packages and workers; any `v7.x.x` has the model.

## Service-specific gotchas

### `available_links` defaults to `["connect"]`

A service with no links must say so. Otherwise the apply fails reading a spec file
that was never written:

```
Invalid value for "path" parameter: no file exists at .../specs/links/connect.json.tpl
```

Pass `available_links = []`.

### Local mode works with packaging

`git_provider = "local"` plus `local_specs_path` reads the specs off the
filesystem with `file()`, and the `package` block behaves identically. That is how
you iterate: craft, build, register and run a packaged service without pushing a
repo or minting a token.

```hcl
  git_provider      = "local"
  local_specs_path  = "/abs/path/to/<slug>"
  repository_branch = "local"   # no default, so required — but unread in local mode
  available_links   = []
```

In **remote** mode the repo fields do matter, packaged or not: the module fetches
the spec files over HTTPS on every `apply`, so a private repo needs a fine-grained
token with `Contents: Read-only`. Pass it by variable — `main.tf` is tracked and
`.gitignore` typically only covers `*.tfvars`.

### The channel's entrypoint must match what the image bakes

The association's `entrypoint` defaults to `/app/packages/<package_slug>/entrypoint`.
The service repos bake `/app/pkg/<slug>/entrypoint/entrypoint`. They do not match,
so pass `entrypoint` explicitly unless you baked the module's path. Get this wrong
and the channel points at a path absent from the image — it fails on the first
action, not at apply.

Verify the channel after applying:

```bash
/np-api fetch-api "/notification/channel/<id>"
# configuration.command.type must be "package-exec"
# configuration.command.data.cmdline must exist inside the image
```

## Operational behaviour worth knowing

Observed end to end on a live cluster. These complement `/np-package-builder`
rather than restating it.

| | |
|---|---|
| **One worker Deployment per package revision** | Deployments are named `np-worker-<agent>-<slug>-<version>`, with the version dot-to-dash. Two revisions of the same package coexist as two Deployments. A service instance is bound for life to the revision it was born with, so an old revision keeps its worker while anything references it |
| **Nothing garbage-collects those workers** | They carry no `ownerReferences`, only `managed-by: np-agent` and `worker-lifecycle: dynamic`. Deleting the package, channel and spec leaves them running; the agent reaps them on its own `idleTTL`. Never `kubectl delete` them |
| **`tofu destroy` does not remove the artifact envelope** | It survives with its revision history, keyed by `{registry, repository}`. The TF resource models a revision; the envelope outlives it. No `np` CLI command removes one and `artifacts/*` is not on `np-api`'s modify allowlist |
| **A version bump plans as `1 to add, 1 to change, 1 to destroy`** | A changed digest forces replacement of the artifact while the package updates in place. Benign here — but it is the same signature that, on the **agent** module, means the Helm release is being recreated. Read which resource the plan names |
| **The terraform key may not reach service instances** | It can create specifications and packages and still get `403` on `/service`. Provider and CLI keys carry different permissions |

## Verification

```bash
/np-api fetch-api "/packages?nrn=<nrn>"                              # plural; /package is not a route
/np-api fetch-api "/packages/<package_id>/revisions"
/np-api fetch-api "/packages/<package_id>/revisions/<revision_id>"   # the stored BOM
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"
```

A revision's `components` holds one entry per component as
`{resource_type, name, resource_id, resource_revision_id, parent_id}`. Expect
**more entries than you listed**: every default action specification expands as a
child. A service with one spec, one link and one artifact resolves to eleven — the
`service_specification` and the `artifact` at the root, the link and all actions
beneath a parent.
