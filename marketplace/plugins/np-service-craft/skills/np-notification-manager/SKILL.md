---
name: np-notification-manager
description: This skill should be used when the user asks to "create a notification channel", "debug notifications", "resend a notification", "check channel configuration", "inspect notification delivery", or needs to manage nullplatform notification channels (agent, GitHub Actions, GitLab, http) and test notification delivery. Covers only the notification channels under `/notification` (events routed to agents, CI workflows and webhooks), including the GitHub channel that dispatches a `workflow_dispatch` to run service provisioning without an agent. It does NOT cover Communications under `/communications` (the dashboard bell/inbox, announcements and banners, inbox rules, inbox settings); use `/np-communications` for those.
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# np-notification-manager

Dedicated skill for managing notification channels and notifications in NullPlatform. Centralizes creation, inspection, and debugging of channels that connect platform events with their executor: an agent, a GitHub Actions workflow, a GitLab pipeline or a webhook.

## Critical Rules

1. **Scope check first.** This skill is about notification channels (`/notification/channel`, `/notification`). If the user is talking about what people see in the dashboard (the bell, the inbox, announcements and banners, inbox rules, "my inbox settings"), that is Communications (`/communications/*`, CLI `np communications ...`): say so, do not use these commands for it, and use `/np-communications` instead.
2. **Always use `/np-api fetch-api`** to access the API. NEVER use `curl` directly against `api.nullplatform.com`.
3. **Confirm before creating or modifying** channels. Show the complete configuration and ask for explicit confirmation.
4. **Ask with `AskUserQuestion`**, never as plain-text question lists. Before each batch, look up what the platform already knows (providers, existing channels, specifications, the repo) and offer it as options; the user can always pick "Other".
5. **Validate per type before creating.** `agent`: selector tags match a live agent. `github`: the repository, reference and workflow file exist and the workflow accepts `workflow_dispatch`. Never create a channel with an empty filter value.
6. **Stay client-agnostic.** Nothing in these flows assumes a particular organization, GitHub owner, repository layout or workflow name. Every value comes from the user or from what the API returns for their NRN.

## Available Commands

| Command | Description |
|---------|-------------|
| `/np-notification-manager list` | List active channels for an NRN |
| `/np-notification-manager create` | Create a notification channel (guided) |
| `/np-notification-manager inspect <channel-id>` | View detailed configuration of a channel |
| `/np-notification-manager notifications <nrn>` | View recent notifications for an NRN |
| `/np-notification-manager resend <notification-id> [channel-id]` | Resend a notification |
| `/np-notification-manager debug <channel-id>` | Diagnose delivery problems |

---

## Command: List Channels (`/np-notification-manager list`)

List all active channels for an NRN:

```
/np-api fetch-api "/notification/channel?nrn=<account-nrn>&status=active"
```

Show summary table:

```
| ID        | Description       | Type  | Source           | Selector              | Filters                              |
|-----------|-------------------|-------|------------------|-----------------------|--------------------------------------|
| 12345     | k8s scope         | agent | telemetry,service| cluster:runtime       | spec.slug=$eq:kubernetes-custom      |
| 12346     | postgres service  | agent | service          | cluster:runtime       | spec.slug=$eq:postgres-k8s           |
```

---

## Command: Create Channel (`/np-notification-manager create`)

Guided flow. Three batches of `AskUserQuestion`; the second one depends on the channel type.

### Phase 0 — Pre-flight (no questions yet)

Collect what can be offered as defaults:

```
/np-api fetch-api "/account"                                                   # NRN options
/np-api fetch-api "/notification/channel?nrn=<nrn>&status=active&limit=100"     # existing channels: reuse their config
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"       # specs: filter options
/np-api fetch-api "/provider?nrn=<nrn>&limit=100"                                 # providers (attributes come back null here)
/np-api fetch-api "/provider/<id>"                                               # read each github-configuration provider: setup.organization, setup.installation_id
/np-api fetch-api "/controlplane/agent"                                          # agents and their tags (agent type)
```

Also detect if the `gh` CLI is authenticated (`gh auth status`). When it is, repository, branch and workflow questions get real options; when it is not, the same questions are asked with "Other" only and the validation step is skipped with a warning.

### Batch 1 — What and where (all types)

1. **NRN** — options from `/account` (`organization=<org>:account=<id>`), plus the organization NRN. Namespace-level NRNs via "Other".
2. **Channel type** — `agent`, `github`, `gitlab`, `http`. Mark `agent` `(Recommended)` only when at least one agent is connected for that NRN; mark `github` `(Recommended)` when the NRN already has github channels and no agent.
3. **Purpose / sources** — Scope `["telemetry","service"]`, Service `["service"]`, Telemetry only `["telemetry"]`, Entity hooks `["entity"]`.
4. **Description** — offer a generated default (`<type> channel for <spec or purpose>`) plus "Other". Always set one: channels created by IaC often have an empty description and are hard to tell apart.

### Batch 2 — Type-specific configuration

- `agent` → questions 4–5 below (unchanged).
- `github` → @${CLAUDE_PLUGIN_ROOT}/skills/np-notification-manager/docs/github-channel.md (questions, autocompletion sources, validation, JSON).
- `gitlab` / `http` → not guided yet. Build the body from the official docs (`docs/notifications/channels.md`) and still run Batch 1, Batch 3 and the confirmation.

#### Agent questions

4. **Command configuration**:
   - Entrypoint path (e.g., `<repo-path>/entrypoint`)
   - Service path argument (e.g., `--service-path=<repo-path>/<scope-dir>`)
   - Overrides path (optional, e.g., `--overrides-path=<path>`)
5. **Agent selector tags**: Key-value pairs that must match the agent's `--tags`. Offer the tag sets of the agents returned by `/controlplane/agent` as options.

### Batch 3 — Filters (all types)

1. **Specification** — options from `/service_specification` (slug + name, mark the one matching the description if any). "Other" for a spec that does not exist yet.
2. **Filter key** — `service.specification.slug` `(Recommended)`: it lets the spec and the channel be declared together (Terraform, GitOps) and it is what the official `service_definition_agent_association` module emits. Offer `service.specification.id` when the user is wiring a channel by hand onto a spec that already exists and wants it to survive a slug change. Both are accepted by the API. If the channel also carries the `telemetry` source, use the module's shape: `{"$or": [{"service.specification.slug": {"$eq": "<slug>"}}, {"arguments.service_specification.slug": {"$eq": "<slug>"}}]}` — metric notifications carry the spec under `arguments`.
3. **Action scope** — all actions `(Recommended)`, or exclude custom actions (`"type": {"$ne": "custom"}`) when custom actions are handled by another channel.

Never accept an empty filter value (`{"service.specification.slug": ""}`). Depending on how the matcher treats it, the channel either never fires (dead channel) or fires for every service event in the NRN (duplicate executions). Both have been seen in the field as confusing leftovers.

### Channel JSON structure (agent)

```json
{
  "nrn": "<nrn>",
  "description": "<description>",
  "type": "agent",
  "source": ["<sources>"],
  "status": "active",
  "configuration": {
    "command": {
      "type": "exec",
      "data": {
        "cmdline": "<entrypoint-path> --service-path=<scope-path>",
        "environment": {
          "NP_ACTION_CONTEXT": "'${NOTIFICATION_CONTEXT}'"
        }
      }
    },
    "selector": {
      "<tag-key>": "<tag-value>"
    }
  },
  "filters": {
    "service.specification.slug": {
      "$eq": "<slug>"
    }
  }
}
```

The github JSON is in the github doc above.

### Key fields

| Field | Description | Common values |
|-------|-------------|---------------|
| `type` | Channel type | `agent`, `github`, `gitlab`, `http`, `slack` |
| `source` | What events it receives | `["service"]`, `["telemetry"]`, `["telemetry", "service"]`, `["entity"]`, `["approval"]`, `["audit"]` |
| `configuration` | Type-specific block | agent: `command` + `selector`; github: `installation_id`, `account`, `repository`, `reference`, `workflow_id` |
| `configuration.command.data.environment` | Environment variables (agent) | Always include `NP_ACTION_CONTEXT` |
| `configuration.selector` | Target agent tags (agent) | Must match the agent's `--tags` |
| `filters` | Which notifications to match | `service.specification.id` or `.slug`, optional `type` |

### Sources explained

- `"service"`: Receives notifications for scope, service and link actions (create, update, delete, custom)
- `"telemetry"`: Receives requests for logs, metrics, instances, and parameters
- `"entity"`: Entity hooks (application:create, deployment events, …)
- For a complete agent-backed scope, always use both: `["telemetry", "service"]`

### Advanced filters

Available operators in filters:
- `$eq` — exact equality (a bare value is the same as `{"$eq": value}`)
- `$ne` — not equal
- `$in` / `$nin` — one of / none of several values
- `$contains` — contains substring
- `$or` / `$and` — combine conditions

Example with multiple filters:
```json
{
  "filters": {
    "service.specification.slug": { "$eq": "my-scope" },
    "arguments.scope_provider": { "$eq": "<spec-id>" }
  }
}
```

### Create the channel

Run the type's validation (agent: selector matches a live agent; github: see the github doc). Show the complete JSON to the user and ask for confirmation. Then:

```
/np-api fetch-api "POST /notification/channel" with body: <channel-json>
```

Capture the created channel ID, show it, and point the user to **Platform settings > Notifications > Channels** in the dashboard. For a github channel, finish by printing what the workflow must do with the dispatch (contract section of the github doc) and offer `/np-notification-manager debug <id>` after the first service action.

---

## Command: Inspect Channel (`/np-notification-manager inspect <channel-id>`)

View the complete configuration of a channel:

```
/np-api fetch-api "/notification/channel/<channel-id>"
```

Show:
1. **General configuration**: ID, NRN, description, type, status, sources
2. **Command**: cmdline, environment variables
3. **Selector**: Tags the agent must have
4. **Filters**: Which notifications it matches
5. **Timestamps**: created_at, updated_at
6. **Validations** (by type):
   - `agent`: the selector has reasonable tags; the cmdline points to an existing path (if local)
   - `github`: `account`/`repository`/`reference`/`workflow_id` resolve with `gh` (repo exists, ref exists, workflow file present and declares `workflow_dispatch`); `installation_id` is numeric and, when a `github-configuration` provider exists for the NRN, note whether it matches
   - all: the filter references an existing specification (by id or slug) and no filter value is empty

---

## Command: List Notifications (`/np-notification-manager notifications <nrn>`)

View recent notifications:

```
/np-api fetch-api "/notification?nrn=<nrn>&per_page=20"
```

Show table with:

```
| ID       | Action              | Status    | Created            | Channel Deliveries |
|----------|---------------------|-----------|--------------------|-------------------|
| 12345678 | start-initial       | delivered | 2025-05-17T16:37Z  | 1 success         |
| 12345679 | create-scope        | delivered | 2025-05-17T16:38Z  | 1 success         |
| 12345680 | log:read            | failed    | 2025-05-17T16:39Z  | 0 success         |
```

To view the delivery detail of a notification:

```
/np-api fetch-api "/notification/<notification-id>/result"
```

---

## Command: Resend Notification (`/np-notification-manager resend <notification-id> [channel-id]`)

Resends a notification for retesting without needing to recreate resources from the UI.

```
/np-api fetch-api "POST /notification/<notification-id>/resend" with body:
```

Without specific channel (resends to all matching channels):
```json
{}
```

With specific channel:
```json
{
  "channels": [{ "id": <channel-id> }]
}
```

### When to use resend

- **Debugging**: The script failed and you fixed it, you want to re-execute without recreating the scope/deployment
- **Iterative testing**: You're developing a scope and want to test script changes
- **Validation**: You want to verify that an agent fix resolves the problem

### Finding the notification ID

```
/np-api fetch-api "/notification?nrn=<scope-nrn>&per_page=5"
```

Filter by specific action if needed, reviewing the `action` field in each notification.

---

## Command: Debug Channel (`/np-notification-manager debug <channel-id>`)

Complete diagnosis of a channel that is not working.

### Automatic checks

1. **Channel status**: Verify it's `active`
   ```
   /np-api fetch-api "/notification/channel/<channel-id>"
   ```

2. **Executor reachability** (by type):
   - `agent`: find agents with tags matching the selector
     ```
     /np-api fetch-api "/controlplane/agent"
     ```
     Filter by selector tags and verify at least one agent is active.
   - `github`: there is no executor to reach from nullplatform. Read `/notification/<id>/result` for the last deliveries: `{"status":204,...}` means GitHub accepted the dispatch, nothing more. Then look for the run in GitHub at the dispatch minute (`gh run list -R <account>/<repository> --workflow <workflow_id> --branch <reference> --created <window>`). Three outcomes: no run → GitHub dropped it, resend may help; failed run → fix the workflow, resend only repeats the failure; queued run → the runner is down. Full procedure in the github doc.

3. **Filter validation**: Verify the id or slug in filters corresponds to an existing service specification, and that no filter value is empty
   ```
   /np-api fetch-api "/service_specification/<id>"
   /np-api fetch-api "/service_specification?nrn=<channel-nrn>&show_descendants=true"   # then match by slug
   ```

4. **Recent deliveries**: Review last notifications and their results
   ```
   /np-api fetch-api "/notification?nrn=<channel-nrn>&per_page=10"
   ```
   For each one, review delivery result.

5. **Command path validation** (`agent`): If we have local access, verify the cmdline points to existing files:
   - Does the entrypoint exist?
   - Does the service-path exist?
   - Do scripts have execute permissions?

   (`github`): verify the workflow at `reference` still declares `workflow_dispatch` with a string input, and that the service it stuck on has `updated_at` within seconds of `created_at` (the run never reported back) versus later (the run started and failed mid-way).

### Diagnosis report

```
Channel Debug Report: <channel-id>
=====================================

Channel Status: [PASS] active
Agent Match:    [PASS] 1 agent(s) with matching tags
Filter Valid:   [PASS] slug "kubernetes-custom" exists (spec ID: 123)
Recent Delivery:[WARN] 2/5 notifications failed in last hour
Command Path:   [PASS] entrypoint exists and is executable

Issues Found:
  - 2 failed deliveries: Script error in build_context (line 45)
    Notification IDs: 12345678, 12345679
    → Review agent logs for details
    → Use /np-notification-manager resend <id> to retry after fix
```

For a `github` channel the report replaces the agent lines:

```
Channel Status: [PASS] active
Workflow:       [PASS] <account>/<repository>@<reference> .github/workflows/<workflow_id> (workflow_dispatch, input "context")
Installation:   [WARN] 60640523 differs from the github-configuration provider of this NRN (60640569) — fine if the repo lives in another GitHub org
Filter Valid:   [PASS] service.specification.id <uuid> = <slug>
Recent Delivery:[PASS] 5/5 dispatches accepted (204)
GitHub Runs:    [FAIL] 3/5 dispatches have no run in GitHub at that minute

Issues Found:
  - 3 dispatches accepted by GitHub but never ran → check Actions enabled, workflow not disabled, App installed on the repo
    → Resend once fixed: /np-notification-manager resend <notification-id> <channel-id>
```

---

## Reference: Channel Types

| Type | Usage | Configuration |
|------|-------|---------------|
| `agent` | Scopes and services executed by the nullplatform agent in the client's infrastructure | `command.type: "exec"` or `"package-exec"`, `cmdline`, `environment`, `selector` |
| `github` | Services provisioned by a GitHub Actions workflow (`workflow_dispatch`), no agent involved | `installation_id`, `account`, `repository`, `reference`, `workflow_id` → @${CLAUDE_PLUGIN_ROOT}/skills/np-notification-manager/docs/github-channel.md |
| `gitlab` | Same idea on GitLab CI | `project_id`, `reference` |
| `http` | Webhooks: entity hooks, approvals, audit sinks | `url`, `headers` |
| `slack` | Approval and alert messages | Slack app + channel |

Scopes always use `type: "agent"`. Services can use `agent` or a CI type (`github`/`gitlab`); the choice is the client's, both receive the same notification payload.

## Reference: Notification Lifecycle

```
1. User Action (UI/API) → Service/Scope API
2. API creates Notification (status: pending)
3. Platform matches Notification against active channels:
   - source match (service, telemetry)
   - filter match (slug, custom filters)
4. For each matching channel:
   - agent: finds agents with matching selector tags and sends the command via WebSocket
   - github: POSTs a `workflow_dispatch` to GitHub with the notification JSON as the `context` input
5. The executor (agent command or workflow job) runs `np service-action exec`, which reads `NP_ACTION_CONTEXT` and PATCHes the action status
6. Delivery result recorded in `/notification/<id>/result` (for github: GitHub's HTTP status, typically 204)
7. Notification status updated (delivered/failed) — "delivered" means handed over, not executed
```

## Troubleshooting

| Problem | Probable cause | Diagnosis |
|---------|---------------|-----------|
| Channel doesn't match notifications | Incorrect filters or missing source | Verify slug and sources with `/inspect` |
| Notification delivered but script doesn't run | Incorrect cmdline or permissions | Verify path and `chmod +x` |
| Agent doesn't receive | Tags don't match selector | Compare agent `--tags` with channel `selector` |
| Delivery timeout | Script takes too long or hangs | Review agent logs with `--command-executor-debug` |
| Notification failed | Error in script execution | See `/notification/<id>/result` for error details |
| Channel in inactive status | Was deactivated manually or automatically | Reactivate via API PATCH |
| github: delivery `204` but the service stays `pending`/`creating` | GitHub accepted the dispatch and no run executed or reported back | Compare service `created_at` vs `updated_at`; look for the run in GitHub at that minute; see github doc |
| github: two runs per action | Two channels match the same event (often one with an empty filter value) | List channels for the NRN and fix or delete the broad one |
| github: `422` on dispatch | The notification payload exceeds GitHub's `workflow_dispatch` input size limit | Trim the specification (large OpenAPI specs in attributes are the usual cause) |
