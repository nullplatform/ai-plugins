---
name: np-notification-manager
description: This skill should be used when the user asks to "create a notification channel", "debug notifications", "resend a notification", "check channel configuration", "inspect notification delivery", or needs to manage nullplatform notification channels, agent routing, and test notification delivery.
---

# np-notification-manager

Dedicated skill for managing notification channels and notifications in NullPlatform. Centralizes creation, inspection, and debugging of channels that connect platform events with agents.

## Critical Rules

1. **Always use `/np-api fetch-api`** to access the API. NEVER use `curl` directly against `api.nullplatform.com`.
2. **Confirm before creating or modifying** channels. Show the complete configuration and ask for explicit confirmation.
3. **Validate selector/tags** against the target agent before creating a channel.

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
| 848305398 | k8s scope         | agent | telemetry,service| cluster:runtime       | spec.slug=$eq:kubernetes-custom      |
| 848305399 | postgres service  | agent | service          | cluster:runtime       | spec.slug=$eq:postgres-k8s           |
```

---

## Command: Create Channel (`/np-notification-manager create`)

Guided flow to create a notification channel.

### Questions

1. **NRN**: "What account/organization NRN should own this channel?"
2. **Description**: "Human-readable name for this channel?"
3. **Purpose**:
   - Scope (deployment actions + telemetry) → sources: `["telemetry", "service"]`
   - Service (provisioning actions only) → sources: `["service"]`
   - Telemetry only (logs/metrics) → sources: `["telemetry"]`
4. **Command configuration**:
   - Entrypoint path (e.g., `<repo-path>/entrypoint`)
   - Service path argument (e.g., `--service-path=<repo-path>/<scope-dir>`)
   - Overrides path (optional, e.g., `--overrides-path=<path>`)
5. **Agent selector tags**: Key-value pairs that must match the agent's `--tags`
   - e.g., `environment: demo`, `cluster: runtime`
6. **Filters**: Match notifications for specific scope/service types
   - Service specification slug (e.g., `kubernetes-custom`)
   - Or custom filter expressions

### Channel JSON Structure

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

### Key fields

| Field | Description | Common values |
|-------|-------------|---------------|
| `type` | Channel type | `agent` (always for scopes/services) |
| `source` | What events it receives | `["service"]`, `["telemetry"]`, `["telemetry", "service"]` |
| `configuration.command.type` | How to execute | `exec` (executes command on the agent) |
| `configuration.command.data.cmdline` | Command to execute | Path to entrypoint with args |
| `configuration.command.data.environment` | Environment variables | Always include `NP_ACTION_CONTEXT` |
| `configuration.selector` | Target agent tags | Must match the agent's `--tags` |
| `filters` | Which notifications to match | Service specification slug |

### Sources explained

- `"service"`: Receives notifications for scope and deployment actions (create, deploy, delete, etc.)
- `"telemetry"`: Receives requests for logs, metrics, instances, and parameters
- For a complete scope, always use both: `["telemetry", "service"]`

### Advanced filters

Available operators in filters:
- `$eq` — exact equality
- `$ne` — not equal
- `$in` — one of several values
- `$contains` — contains substring

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

Show the complete JSON to the user and ask for confirmation. Then:

```
/np-api fetch-api "POST /notification/channel" with body: <channel-json>
```

Capture the created channel ID and show it to the user.

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
6. **Validations**:
   - Verify the selector has reasonable tags
   - Verify the filters reference a valid slug
   - Verify the cmdline points to an existing path (if local)

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

2. **Agent connection**: Find agents with tags matching the selector
   ```
   /np-api fetch-api "/controlplane/agent"
   ```
   Filter by selector tags and verify at least one agent is active.

3. **Filter validation**: Verify the slug in filters corresponds to an existing service specification
   ```
   /np-api fetch-api "/service/specification?slug=<slug>"
   ```

4. **Recent deliveries**: Review last notifications and their results
   ```
   /np-api fetch-api "/notification?nrn=<channel-nrn>&per_page=10"
   ```
   For each one, review delivery result.

5. **Command path validation**: If we have local access, verify the cmdline points to existing files:
   - Does the entrypoint exist?
   - Does the service-path exist?
   - Do scripts have execute permissions?

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

---

## Reference: Channel Types

| Type | Usage | Configuration |
|------|-------|---------------|
| `agent` | Scopes and services — executes commands on the agent | `command.type: "exec"`, `cmdline`, `environment` |
| `webhook` | External integrations — sends HTTP POST | `url`, `headers`, `body_template` |
| `sns` | AWS SNS — publishes to a topic | `topic_arn`, `region` |

For scopes and services, always use `type: "agent"`.

## Reference: Notification Lifecycle

```
1. User Action (UI/API) → Service/Scope API
2. API creates Notification (status: pending)
3. Platform matches Notification against active channels:
   - source match (service, telemetry)
   - filter match (slug, custom filters)
4. For each matching channel:
   - Finds agents with matching selector tags
   - Sends command via WebSocket to agent
5. Agent executes command
6. Result reported back (success/failure)
7. Notification status updated (delivered/failed)
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
