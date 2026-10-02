# Workflows (Approvals, Notifications, Templates)

Workflow and configuration entities.

## @endpoint /approval/{id}

Gets details of an approval.

### Parameters
- `id` (path, required): Approval ID

### Response
- `id`: Approval ID
- `created_at`: Creation timestamp
- `approval_action_id`: Approval action ID (internal reference)
- `entity_id`: ID of the entity requiring approval (e.g., deployment ID as string)
- `aggregator_entity_id`: Aggregator ID (null if not applicable)
- `entity_name`: Entity type (e.g., `deployment`, `service:action`, `scope`)
- `nrn`: Complete resource NRN
- `entity_action`: Action requiring approval (e.g., `deployment:create`)
- `status`: `pending` | `approved` | `auto_approved` | `auto_denied` | `denied` | `cancelled` | `expired`
- `execution_status`: `pending` | `executing` | `success` | `failed` | `expired` - indicates if the approved action has already been executed
- `user_id`: Requesting user ID
- `dimensions`: Context dimensions
  - `environment`: production | staging | development | etc
  - `country`: usa | mx | ar | etc
- `policy_context`: Policy evaluation context
  - `policies[]`: Array of evaluated policies
    - `id`: Policy ID
    - `name`: Descriptive name (e.g., "[SRE] Tests coverage should be above 80%")
    - `selector`: Pre-filter that determines if the policy applies to the request (e.g., by dimensions, entity type)
    - `conditions`: Required conditions. Use MongoDB syntax: `$gte`, `$lte`, `$eq`, `$or`, `$nor`, `$and`
      - Example: `{"build_metadata_coverage_percent": {"$gte": 80}}`
      - Range example: `{"scope.capabilities.memory.memory_in_gb": {"$gte": 2, "$lte": 4}}`
    - `evaluations[]`: Result of each criterion
      - `criteria`: Evaluated criterion
      - `result`: `met` | `not_met`
    - `passed`: boolean - whether the policy passed
    - `selected`: boolean - whether the policy applies to this context (determined by selector)
  - `action`: `auto` | `manual` - whether it was auto-approved or required human intervention
  - `time_to_reply`: Response window (ms). Expires if not answered in time
  - `allowed_time_to_execute`: Post-approval execution window (ms)
- `context`: Complete snapshot of related entities at approval time
  - `user`: Requesting user data
  - `deployment`: Deployment state at approval time
  - `scope`: Target scope data
  - `release`: Release to deploy
  - `build`: Build associated with the release
  - `application`: Application
  - `namespace`, `account`, `organization`: Organizational hierarchy

### Navigation
- **→ deployment**: `entity_id` → `/deployment/{entity_id}` (when `entity_name` is `deployment`)
- **→ user**: `user_id` → `/user/{user_id}`
- **← deployment NRN**: `/approval?nrn={deployment_nrn_encoded}`

### Example
```bash
np-api fetch-api "/approval/541210877"
```

### Supported entity/action combinations

| Entity Name | Entity Action | Description |
|-------------|---------------|-------------|
| `deployment` | `deployment:create` | When creating a deployment |
| `scope` | `scope:create` | When creating a scope |
| `scope` | `scope:recreate` | When recreating a scope |
| `scope` | `scope:write` | When modifying a scope (PATCH) |
| `scope` | `scope:delete` | When deleting a scope |
| `scope` | `scope:stop` | When stopping a scope |
| `service:action` | `service:action:create` | When executing a service action |
| `parameter` | `parameter:read-secrets` | When requesting access to secrets |

### Approval request statuses

| Status | Description |
|--------|-------------|
| `pending` | Waiting for human decision |
| `approved` | Manually approved |
| `auto_approved` | Automatically approved: all policies passed (policy mode), or the checklist run resolved `approve` (checklist mode) |
| `denied` | Manually rejected |
| `auto_denied` | Automatically rejected (policies failed + auto-deny config) |
| `cancelled` | Cancelled by user or system |
| `expired` | Expired without response (exceeded `time_to_reply`) |

### Execution statuses

| Status | Description |
|--------|-------------|
| `pending` | Approved but not started yet |
| `executing` | Execution in progress. An `executing` for more than 60 s (the API measures it from the row's last write, which the approval JSON does not carry: `/can_execute` answers `true` for a stale one) has no live executor left: `POST /approval/{id}/execute` starts it again, or `POST /approval/{id}/cancel` cancels it |
| `success` | Successfully executed |
| `failed` | Execution failed. `POST /approval/{id}/execute` retries it, in both modes |
| `expired` | Expired without executing (exceeded `allowed_time_to_execute`) |

### Secret visibility (parameter:read-secrets)

When `entity_action` is `parameter:read-secrets`, the approval controls temporary access
to secret parameter values. Flow:
1. User requests to view secrets from the UI
2. An approval request is created with `entity_action: parameter:read-secrets`
3. If approved, the user gets access for 24 hours
4. The approval expires in 3 days if not answered

### Notes
- `status: approved` + `execution_status: pending` = approved but waiting for deployment to start ("Start deployment" in the UI)
- `status: auto_approved` + `execution_status: pending` = a checklist approval whose specification does not start the action on its own (`definition.execution_trigger: explicit`, the default): it also waits for the Start. `GET /approval/{id}/checklist` → `execution.on_approval` says whether a checklist approval starts on its own (`execute`) or waits (`wait`)
- `status: approved` / `auto_approved` + `execution_status: executing` or `success` = approved and deployment already started
- `policy_context.action: manual` indicates policies didn't pass and human approval was required
- `policy_context.action: auto` indicates policies passed and it was auto-approved
- The `context` is an immutable snapshot from the approval moment - useful for auditing
- **Policy operators**: Conditions use MongoDB syntax: `$gte`, `$lte`, `$eq`, `$or`, `$nor`, `$and`
- **Selectors**: Act as pre-filters before evaluating conditions. Determine if the policy applies to the request
- **Scopes**: When `entity_name` is `scope`, the approval is generated when creating a scope that doesn't meet the organization's policies (e.g., memory out of range, incorrect scope_type, scheduled_stop disabled). See `np-developer-actions/docs/scopes.md` Step 5 for querying policies before creating scopes

---

## @endpoint /approval

Lists approvals with filters.

### Parameters
- `nrn` (query, required): Resource NRN (URL-encoded). Supports NRN at different levels:
  - **Application NRN**: returns all app approvals (scopes + deployments)
  - **Deployment NRN**: returns approvals for a specific deployment
  - **Scope NRN**: returns approvals for a specific scope

### Response
```json
{
  "paging": {"total": 1, "offset": 0, "limit": 30},
  "results": [...]
}
```

Each result has the same structure as `/approval/{id}`.

### Example
```bash
# Search approvals for a specific deployment
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>%3Ascope%3D<scope_id>%3Adeployment%3D<deployment_id>"

# Search all approvals for an application (includes scopes and deployments)
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>"
```

### Notes
- The NRN must be URL-encoded (replace `=` with `%3D` and `:` with `%3A`)
- Use the deployment NRN (not just the ID) to filter approvals
- **To discover scope policies**: use application-level NRN to get previous approvals and extract `policy_context.policies[]` with the conditions the organization evaluates
- Direct listing without NRN may return 403 (unauthorized)
- Returns the same detail level as individual GET, including `policy_context` and `context`

---

## @endpoint /approval/{id}/execute

Starts the action of an approved approval by sending the callback the entity registered with it
(for a deployment, the call that moves it to `creating`). This is the endpoint behind the
"Start deployment", "Create scope" and "Apply changes" buttons in the UI. It does not approve.

### Parameters
- `id` (path, required): Approval ID

### Request
- **Method**: POST
- **Body**: `{}` (empty)

### Behavior

First rule that applies (the same rules `/approval/{id}/can_execute` answers with):

1. **Already executed** — `execution_status: success`, or `executing` for less than 60 s (the API
   measures it from the row's last write, which the approval JSON does not carry: `/can_execute`
   answers `true` for a stale one), on an approval with a registered callback, with or without an
   execution window →
   `200` with the approval as it is: no save, no second callback, no propagation to a group's
   children.
2. **Cannot execute** for any other reason → `400 CANNOT_EXECUTE`: the body reads
   `"The approval request cannot be executed"` (`detail: null`); the reason is not in it:
   `GET /approval/{id}/can_execute` → `message` gives it (`Approval is not approved` on a
   `pending`: approve it through its channel first).
3. **Claim.** The row is taken with a compare-and-set (`pending` | `failed` | `executing` older
   than 60 s → `executing`). Exactly one caller wins, so the callback is sent once per approval
   even when two Starts, a pipeline, a reviewer's reply or the policy engine race for it. A caller
   that loses the claim answers `200` with the approval as it is now, without a callback.
4. **Callback**, with a total budget of 10 s: each attempt gets what is left of it, fast errors
   are retried while budget remains, and a timeout is not retried (the call may have landed). The
   approval ends `success` or `failed`; a `failed` is retried with another execute, in both modes.
5. **`deployment_group`**: the group's approval is saved as soon as its callback answers, and its
   children's approvals are updated afterwards, best effort (logged). If that update fails, the
   group keeps its own status (e.g. `success`) and its children stay `approved` + `pending`.

An approval with no registered callback (e.g. `parameter:read-secrets`) has nothing to send: an
execute marks it `success`.

### Response

Returns the approval (same structure as GET `/approval/{id}`), with `execution_status` as it
ended: `success` or `failed` after the callback, or unchanged when the call was a no-op.

### Example
```bash
# NOTE: This is a POST, not a GET. Use from np-developer-actions:
action-api.sh exec-api --method POST --data '{}' "/approval/<approval_id>/execute"
```

### Notes
- Empty body (`{}`) - no additional parameters required
- Repeating an execute is safe: once the approval is `success`, or `executing` within the last
  60 s, it answers `200` and sends nothing
- An `executing` older than 60 s means whatever was executing it died mid-callback: an execute
  takes it again and sends the callback again, even if the previous one had landed
- In checklist mode the approval may have started on its own (`definition.execution_trigger`):
  read `execution.on_approval` on `GET /approval/{id}/checklist`, or ask `/can_execute`, before
  offering a Start
- **This is the correct path to start an approved deployment** (instead of direct PATCH to deployment)

---

## @endpoint /approval/{id}/can_execute

Tells whether `POST /approval/{id}/execute` would start the approval's action now.

### Parameters
- `id` (path, required): Approval ID

### Response
- `can_execute`: boolean
- `message`: the reason, first rule that applies:

| `can_execute` | `message` | When |
|---|---|---|
| `false` | `Approval is not approved` / `Approval is expired` | `status` is not `approved` / `auto_approved` |
| `false` | `Approval is already executed` | `execution_status: success`, or `executing` for less than 60 s (the API measures it from the row's last write, which the approval JSON does not carry), on an approval with a registered callback — with or without an execution window |
| `false` | `Approval is expired to execute` | `execution_status: expired` |
| `true` | `Approval is approved and not expired to execute` | `failed`, or `executing` more than 60 s old, on an approval with a registered callback: retryable in both modes |
| `false` | `Approval is not pending to execute` | No execution window and not `pending` (nor retryable, as above) |
| `true` | `Approval is approved and not expired to execute` | Anything else |

An approval with no registered callback (`parameter:read-secrets`) skips the "already executed"
and the retryable rows: its execution window is the access to the secret.

### Example
```bash
np-api fetch-api "/approval/<approval_id>/can_execute"
```

---

## @endpoint /notification/channel/{id}

Gets details of a notification channel.

### Parameters
- `id` (path, required): Channel ID

### Response
- `id`: Numeric ID
- `name`: Channel name
- `type`: slack | email | webhook
- `status`: Status
- `nrn`: Context NRN
- `configuration`: Type-specific config

### Domain
```
https://notifications.nullplatform.com/notification/channel/{id}
```

### Example
```bash
np-api fetch-api "https://notifications.nullplatform.com/notification/channel/456"
```

---

## @endpoint /notification/channel

Lists notification channels.

### Parameters
- `nrn` (query, required): Base NRN
- `showDescendants` (query): **camelCase** - includes channels from lower hierarchy
- `limit` (query): Maximum results

### Example
```bash
np-api fetch-api "https://notifications.nullplatform.com/notification/channel?nrn=organization%3D4&showDescendants=true&limit=500"
```

### Notes
- Use `showDescendants` (**camelCase**) NOT `show_descendants`
- Inconsistent with `/provider` which uses snake_case
- Without `showDescendants=true` only returns channels at the specified NRN level

---

## @endpoint /template/{id}

Gets details of an application template.

### Parameters
- `id` (path, required): Template ID (may be name with version)

### Response
- `id`: Template ID/name
- `name`: Descriptive name
- `version`: Version
- `runtime`: Runtime configuration
- `build_command`: Build command
- `health_check_config`: Health check config
- `resources`: Default resources

### Example
```bash
np-api fetch-api "/template/react_18.2.0"
```

---

## @endpoint /template

Lists available templates.

### Example
```bash
np-api fetch-api "/template"
```

---

## @endpoint /report

Lists available reports (analytics and compliance).

### Domain
```
https://reports.nullplatform.com/report
```

### Example
```bash
np-api fetch-api "https://reports.nullplatform.com/report"
```

---

## @endpoint /user/{id}

Gets details of a user.

### Parameters
- `id` (path, required): User ID

### Response
- `id`: Numeric ID
- `email`: User email
- `name`: Name
- `role`: Role
- `status`: Status
- `created_at`, `last_login`: Timestamps

### Common Service Accounts
- `gabriel+scope_workflow_manager_job@nullplatform.io` - Scope lifecycle
- `nullmachineusers+approvals-api@nullplatform.io` - Approvals workflow
- `nullmachineusers+ephemeral-scopes@nullplatform.io` - Auto-stop scheduler

### Example
```bash
np-api fetch-api "/user/111433570"
```

---

## @endpoint /user

Lists users.

### Example
```bash
np-api fetch-api "/user"
```
