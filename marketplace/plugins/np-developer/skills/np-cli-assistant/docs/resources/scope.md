# Scope

Create and manage scopes, scope domains, scope dimensions, scope types, scope actions, and scope specifications. Scopes are deployment environments within an application (e.g., production, staging).

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np scope list` | List scopes within an application |
| `np scope read --id <id>` | Read a specific scope |
| `np scope action read --scopeId <id> --actionId <id>` | Read a troubleshooting action |
| `np scope domain list` | List custom domains for a scope |
| `np scope domain read --id <id>` | Read a custom domain |
| `np scope type list --nrn <nrn>` | List available scope types for an NRN |
| `np scope type read --id <id>` | Read a scope type |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np scope create --body <json>` | Create a new scope in an application |
| `np scope patch --id <id> --body <json>` | Update a scope (name, capabilities, specification, etc.) |
| `np scope delete --id <id>` | Delete a scope (supports `--force` for retry) |
| `np scope action create --scopeId <id> --body <json>` | Kill a specific instance/pod (troubleshooting) |
| `np scope dimension create --scopeId <id> --body <json>` | Assign a dimension to a scope |
| `np scope dimension delete --scopeId <id> --slug <slug>` | Remove a dimension from a scope |
| `np scope domain create --body <json>` | Create a custom domain for a scope |
| `np scope domain patch --id <id> --body <json>` | Update a custom domain |
| `np scope domain delete --id <id>` | Delete a custom domain |
| `np scope type create --body <json>` | Enable scope types for applications |
| `np scope type patch --id <id> --body <json>` | Update a scope type |
| `np scope type delete --id <id>` | Delete a scope type |

## Flag Reference

### `np scope list`

| Flag | Type | Description |
|------|------|-------------|
| `--application_id` | string | Filter by application ID (comma-separated, up to 10 values) |
| `--status` | string | Filter by scope status |
| `--type` | string | Filter by scope type |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np scope read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the scope (required) |
| `--include` | string | Include related entities information |

### `np scope create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np scope patch`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the scope (required) |
| `--body` | string | JSON body or file path (required). Patchable fields include: `name`, `capabilities`, `specification` (replicas, resources), `asset_name` |

> **Example:** `np scope patch --id 415005828 --body '{"capabilities": {"auto_scaling": {"instances": {"min_amount": 2, "max_amount": 5}}}}'`

### `np scope delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the scope (required) |
| `--force` | bool | Force delete after a previous failed delete attempt |

> **Gotcha:** `--force` only works if a regular delete was already attempted and failed. It cannot be used on the first attempt.

### `np scope action create`

| Flag | Type | Description |
|------|------|-------------|
| `--scopeId` | string | The ID of the scope (required) |
| `--body` | string | JSON body or file path describing the action (required) |

> This command submits a troubleshooting action to kill a specific instance or pod.

### `np scope action read`

| Flag | Type | Description |
|------|------|-------------|
| `--scopeId` | string | The ID of the scope |
| `--actionId` | string | The ID of the troubleshooting action |
| `--include` | string | Include related entities information |

### `np scope dimension create`

| Flag | Type | Description |
|------|------|-------------|
| `--scopeId` | string | The ID of the scope (required) |
| `--body` | string | JSON body or file path with dimension data (required) |

### `np scope dimension delete`

| Flag | Type | Description |
|------|------|-------------|
| `--scopeId` | string | The ID of the scope (required) |
| `--slug` | string | The dimension slug to remove (required) |

### `np scope domain list`

| Flag | Type | Description |
|------|------|-------------|
| `--scope_id` | string | Filter by scope ID |
| `--organization_id` | string | Filter by organization ID |
| `--name` | string | Filter by domain name |
| `--status` | string | Filter by domain status |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np scope domain read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the custom domain |
| `--include` | string | Include related entities information |

### `np scope domain create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np scope domain patch`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the custom domain (required) |
| `--body` | string | JSON body or file path (required) |

### `np scope domain delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the custom domain |

### `np scope type list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Filter scope types matching or more specific than the NRN (required) |
| `--type` | string | Filter by scope type (e.g., `web_pool_k8s`, `serverless`, `custom`) |
| `--provider_type` | string | Filter by provider type (`null_native` or `service`) |
| `--provider_id` | string | Filter by provider ID |
| `--name` | string | Filter by scope type name |
| `--status` | string | Filter by status |
| `--include` | string | Include additional provider definition data |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np scope type read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the scope type |
| `--include` | string | Include related entities information |

### `np scope type create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np scope type patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the scope type |

### `np scope type delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the scope type |

## Gotchas

- **`--force` on delete**: only works if a regular delete was already attempted and failed. Cannot be used on the first attempt.
- **`np scope patch` patchable fields**: `name`, `capabilities` (auto_scaling, resources), `specification`, `asset_name`. Always send JSON body with only the fields you want to change.
- **`np scope specification create` is deprecated**: do NOT suggest this command. It still appears in `np --help` due to tech debt, but it is not the supported way to create scope specifications. Use `np service specification create --body <json>` with `"type": "scope"` in the body instead. See the [service resource](service.md) for details.
- **Scope types require `--nrn`**: the `np scope type list` command requires `--nrn` to be set.
