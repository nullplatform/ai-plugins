# Deployment

Create and manage deployments.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np deployment list` | List deployments for an application or scope |
| `np deployment read --id <id>` | Read deployment details by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np deployment create --body <json>` | Create a new deployment in a scope |
| `np deployment patch --id <id> --body <json>` | Update deployment information |

## Flag Reference

### `np deployment create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np deployment list`

| Flag | Type | Description |
|------|------|-------------|
| `--application_id` | string | Filter by application ID (allows 1 value) |
| `--scope_id` | string | Filter by scope ID (comma-separated, up to 10 values) |
| `--status_in_scope` | string | Filter by deployment status in scope |
| `--include_messages` | bool | Include messages in the response |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np deployment patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the deployment to update |

### `np deployment read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the deployment to read |
| `--include` | string | Include related entities information |
| `--include_messages` | bool | Include messages in the response |

## Gotchas

- `--nrn` exists in the curated reference for `deployment list` (e.g., `organization=1:account=2:namespace=3:application=4`) but the discovery data shows `--application_id` and `--scope_id` as the actual filter flags. Use `--application_id` or `--scope_id` to filter deployments.
- `--application_id` allows only **1 value** (unlike other resources that allow up to 10).
