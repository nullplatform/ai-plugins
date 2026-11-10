# Execution modes

Who runs a service action is a property of the **notification channel**, not of the service
code. Everything downstream of `np service-action exec` — specs, `build_context`, workflows,
Terraform modules, exports — is identical in both modes. Decide the mode **before** generating
anything: it changes what `create`, `register` and `test` do.

| | Agent mode | CI mode |
|---|---|---|
| Channel type | `agent` (`package-exec`; legacy `exec`) | `github` (`workflow_dispatch`); `gitlab` / `bitbucket` work the same way |
| Who receives the notification | an np-agent selected by tags | a workflow file in a repository the client owns |
| Where the code runs | a worker pod from the package's OCI image | the CI runner, on a checkout of the channel's `reference` |
| What ships | OCI image + package revision | nothing — the runner checks the repo out |
| Auth to nullplatform | `NP_API_KEY` from the agent, bridged by the entrypoint | `NULLPLATFORM_API_KEY` from a CI secret |
| Cloud auth | the agent/worker identity (IRSA, workload identity, …) | OIDC federation or secrets configured in the CI |
| Registration | `service_definition` + agent association | spec + `github` channel (Terraform or API) |
| Local test | `/np-agent-local-setup` | run the handler with a captured `NP_ACTION_CONTEXT` |
| Prerequisite skills | `np-package-builder`, `np-agent-local-setup` | `np-notification-manager` (github channel) |
| Rolling out a code change | rebuild → new digest → bump `package.version` → apply | push to `reference` (branch) or re-point the channel (tag) |
| Where to look when nothing runs | agent logs, worker pod | `gh run list` on the channel's repo |

Nothing here is specific to one client. GitHub owner, repository, workflow file, layout of the
repo and cloud account all come from the user or from what the API returns for their NRN.

## Deciding

Look first, then ask with `AskUserQuestion`:

```bash
/np-api fetch-api "/controlplane/agent"                                                  # connected agents
/np-api fetch-api "/notification/channel?nrn=<nrn>&status=active&limit=100" \
  | jq '(.results // .)[] | {id, type, description}'                                       # how the NRN runs things today
```

- **Agent** — mark `(Recommended)` when at least one agent is connected for the NRN.
- **CI (GitHub Actions)** — mark `(Recommended)` when the NRN already has `github` channels and
  no agent. The client's existing workflow is usually the one to reuse: read it before
  proposing a new one.

When both exist, ask; do not assume. State the consequence of the choice in the option
description (image + agent vs. workflow + secrets).

## Detecting the mode of an existing service

A service without a `package` block is **not** necessarily legacy. Resolve its spec and look
for the channel that filters on it:

```bash
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true" \
  | jq -r '.[] | select(.slug=="<slug>") | .id'
/np-api fetch-api "/notification/channel?nrn=<nrn>&status=active&limit=100" \
  | jq --arg s "<slug>" --arg id "<spec_id>" \
     '(.results // .)[] | select((.filters|tostring) | test($s) or test($id)) | {id, type, configuration}'
```

| Channel found | Mode shown in the list |
|---|---|
| `agent` with `command.type = package-exec` | Agent (packaged) |
| `agent` with `command.type = exec` | Agent (legacy git-clone) |
| `github` | CI: `<account>/<repository>@<reference>` · `<workflow_id>` |
| none | Not registered |

Two active channels matching the same spec means two executions per action. Flag it; never
create a second one silently.

## What the CI side must do

The workflow contract (input → `NP_ACTION_CONTEXT`, CLI install, `np service-action exec`,
`np service action update --results`, `get-exec-path`, fail loudly) and the payload shape are
in the notification manager's github doc — read that, do not restate it:

@${CLAUDE_PLUGIN_ROOT}/skills/np-notification-manager/docs/github-channel.md

## Two repository layouts seen in CI mode

Read the client's workflow to know which one it expects before writing a single file:

1. **This bundle's layout** (`<slug>/entrypoint/`, `workflows/<provider>/*.yaml`, `scripts/<provider>/`):
   the runner's handler calls the service's `entrypoint`, which calls `np service workflow exec`.
   The only difference from agent mode is that `SERVICE_PATH` is the checkout, not the image.
2. **Resolved by `np service-action get-exec-path`**: the runner expects
   `<base-path>/<slug>/service` and `<base-path>/<slug>/link/<link-slug>` directories holding
   Terraform directly, and runs `tofu` itself after `--lookup-by descend-by-action-and-link-slug`.

Both are valid. Recommend layout 1 when the client has no runner yet (it reuses every
convention in `np-service-workflows`); follow layout 2 when the client's runner already
dictates it.
