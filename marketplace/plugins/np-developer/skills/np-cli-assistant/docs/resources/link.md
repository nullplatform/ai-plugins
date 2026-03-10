# Link

Create and manage links and link specifications. Links connect services to applications and scopes.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np link list` | List links |
| `np link read --id <id>` | Read a link |
| `np link action list --linkId <id>` | List link actions |
| `np link action read --linkId <id> --id <id>` | Read a link action |
| `np link specification list` | List link specifications |
| `np link specification read --id <id>` | Read a link specification |
| `np link specification action specification list` | List link specification actions |
| `np link specification action specification read --id <id>` | Read a link specification action |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np link create --body <json>` | Create a link |
| `np link delete --id <id>` | Delete a link |
| `np link patch --id <id> --body <json>` | Update a link |
| `np link action create --linkId <id> --body <json>` | Create a link action |
| `np link action delete --linkId <id> --id <id>` | Delete a link action |
| `np link action patch --linkId <id> --id <id> --body <json>` | Update a link action |
| `np link action update` | Update a link action (service workflow context) |
| `np link specification create --body <json>` | Create a link specification |
| `np link specification delete --id <id>` | Delete a link specification |
| `np link specification patch --id <id> --body <json>` | Update a link specification |
| `np link specification action specification create --linkSpecificationId <id> --body <json>` | Create a link specification action |
| `np link specification action specification delete --id <id>` | Delete a link specification action |
| `np link specification action specification patch --id <id> --body <json>` | Update a link specification action |

## Flag Reference

### `np link list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Filter by NRN (e.g., `organization=1:account=2:namespace=3:application=4`) |
| `--service_id` | string | Filter by service ID |
| `--status` | string | Filter by link status |
| `--show_descendants` | bool | Include links from lower NRN levels (e.g., scopes). **Required in most cases** |
| `--include_messages` | bool | Include messages associated with each link |
| `--include_secret_attributes` | bool | Show secret attribute values |
| `--id` | string | Filter by link ID |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np link read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Link ID |
| `--include` | string | Include related entities information |

### `np link create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np link delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Link ID |
| `--force` | bool | Force delete without checking for delete action existence |

### `np link patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Link ID |

### `np link action create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--linkId` | string | Link ID |

### `np link action delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action ID |
| `--linkId` | string | Link ID |

### `np link action list`

| Flag | Type | Description |
|------|------|-------------|
| `--linkId` | string | Link ID |
| `--id` | string | Action ID filter |
| `--nrn` | string | NRN filter |
| `--status` | string | Action status filter |
| `--include_messages` | bool | Include messages |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np link action patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Action ID |
| `--linkId` | string | Link ID |

### `np link action read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action ID |
| `--include` | string | Include related entities information |
| `--linkId` | string | Link ID |

### `np link action update`

| Flag | Type | Description |
|------|------|-------------|
| `--link-action-id` | string | Link Action ID (auto-populated from NP_ACTION_CONTEXT if not set) |
| `--link-id` | string | Link ID (auto-populated from NP_ACTION_CONTEXT if not set) |
| `--messages` | string | Action messages of process |
| `--results` | string | Action results once provisioned |
| `--status` | string | Status of action: `success` or `failed` |

### `np link specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID filter |
| `--nrn` | string | NRN filter |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np link specification read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID |
| `--include` | string | Include related entities information |

### `np link specification create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np link specification delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID |

### `np link specification patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Specification ID |

### `np link specification action specification create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--linkSpecificationId` | string | Link specification ID |

### `np link specification action specification delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action specification ID |

### `np link specification action specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--linkSpecificationId` | string | Link specification ID |
| `--application_id` | string | Application ID for dynamic properties |
| `--id` | string | Action specification ID filter |
| `--link_id` | string | Link ID for dynamic properties |
| `--link_specification_id` | string | Link specification ID filter |
| `--nrn` | string | NRN filter |
| `--service_id` | string | Service ID for dynamic properties |
| `--service_specification_id` | string | Service specification ID filter |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np link specification action specification patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Action specification ID |

### `np link specification action specification read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action specification ID |
| `--include` | string | Include related entities information |

## Response Fields

Link objects returned by `np link list` use `entity_nrn` (not `nrn`) to identify the owning entity. Key fields:

| Field | Type | Description |
|-------|------|-------------|
| `entity_nrn` | string | NRN of the entity (application or scope) that owns the link. Use this to extract `application=` and `scope=` IDs |
| `dimensions` | object | Context dimensions (e.g., `{"environment": "production"}`) |
| `service_id` | string | UUID of the linked service |
| `name` | string | Human-readable link name |
| `status` | string | Link status: `active`, `creating`, `failed`, `deleting` |
| `slug` | string | URL-friendly identifier |
| `attributes` | object | Service-specific key-value attributes |
| `specification_id` | string | UUID of the link's specification |

## Gotchas

- Links are almost always attached to **scopes**, not directly to the application. Running `np link list --nrn ...application=X` without `--show_descendants` will usually return empty results. **Always include `--show_descendants`** when listing links at the application level.
- When grouping links by application, parse the `entity_nrn` field — not a top-level `nrn`. Example: `entity_nrn: "organization=1:account=2:namespace=3:application=4"` → extract `application=4`.
- `--force` on `np link delete` skips checking for a delete action. Use only when you're sure no cleanup action is needed.
