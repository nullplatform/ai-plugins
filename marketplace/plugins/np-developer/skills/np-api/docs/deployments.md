# Deployments

Deployments are instances of releases deployed to scopes. They include K8s event messages.

## @endpoint /deployment/{id}

Gets details of a deployment.

### Parameters
- `id` (path, required): Deployment ID
- `include_messages` (query, **recommended**): Includes error messages. Default: false

### Response
- `id`: Numeric ID
- `status`: Possible states:
  - **In progress**: `pending` | `provisioning` | `deploying` | `running` | `finalizing`
  - **Finished**: `finalized` | `rolled_back` | `cancelled` | `failed`
- `scope_id`: Scope ID
- `application_id`: Application ID
- `release_id`: Deployed release ID
- `build_id`: Build ID (may be null in deployments without a build)
- `deployment_group_id`: Group ID if part of a multi-scope deploy
- `specification.replicas`: Number of replicas
- `specification.resources`: memory, cpu
- `status_started_at`: Timestamps for each phase (provisioning, deploying, finalized, rolled_back)
- `messages[]`: Array of events (only with `include_messages=true`)
  - `level`: INFO | ERROR | WARNING
  - `message`: Event text
  - `timestamp`: Epoch milliseconds

### Navigation
- **→ scope**: `scope_id` → `/scope/{scope_id}`
- **→ application**: `application_id` → `/application/{application_id}`
- **→ release**: `release_id` → `/release/{release_id}`
- **→ build**: `build_id` → `/build/{build_id}`
- **→ deployment actions**: `scope_id` → `/scope/{scope_id}` → `instance_id` → `/service/{instance_id}/action`
- **← scope**: `/deployment?scope_id={scope_id}`

### Example
```bash
np-api fetch-api "/deployment/1470739357?include_messages=true"
```

### Notes
- **ALWAYS use `?include_messages=true`** for troubleshooting
- Without include_messages, the messages array comes empty or minimal
- Timestamps in messages are epoch milliseconds (divide by 1000)
- BackOff events = container crashes (critical indicator)
- `status: finalized` does NOT mean success - review messages for errors
- The actual deployment errors are in `/service/{scope.instance_id}/action`, not in the deployment
- Old deployments (>30 days) may have truncated messages - use BigQuery audit logs

---

## @endpoint /deployment

Lists deployments with filters.

### Parameters
- `scope_id` (query): Filter by scope
- `application_id` (query): Filter by application
- `deployment_group_id` (query): Filter by group
- `status` (query): Filter by status (failed, finalized, running, etc)
- `sort` (query): Sort results (e.g., `created_at:desc` for most recent first)
- `limit` (query): Maximum results (default 30)
- `offset` (query): For pagination

### Response
```json
{
  "paging": {"total": 150, "offset": 0, "limit": 30},
  "results": [...]
}
```

### Example
```bash
np-api fetch-api "/deployment?scope_id={scope_id}&limit=50"
np-api fetch-api "/deployment?application_id={app_id}&status=failed&limit=50"

# Get most recent deployments first (useful for finding in-progress deployments)
np-api fetch-api "/deployment?scope_id={scope_id}&sort=created_at:desc&limit=20"
```

### Notes
- Use `sort=created_at:desc` to get most recent deployments first
- In-progress deployments (`running`, `deploying`, etc.) are the most recent ones
- To verify stale instances, compare instance `deployment_id` vs scope's `active_deployment`

---

## @endpoint /deployment_group

Gets details of a deployment group (multi-scope deploys).

### Parameters
- `id` (query, required): Group ID - **uses query param, NOT path param**
- `application_id` (query, required): Application ID

### Response
- `id`: Group ID
- `status`: PENDING | RUNNING | FINALIZING | FINALIZED | FAILED | CANCELED | CREATING_APPROVAL_DENIED
- `application_id`: Application ID
- `release_id`: Release ID
- `deployments_amount`: Number of deployments in the group

### Navigation
- **→ deployments**: `/deployment?deployment_group_id={id}&application_id={app_id}`

### Example
```bash
np-api fetch-api "/deployment_group?id=541542807&application_id=30290074"
```

### Notes
- Uses **query parameters** (id, application_id), NOT path parameters
- To see group deployments: `/deployment?deployment_group_id={id}`
