# API Keys

Credentials for programmatic access to the Nullplatform API.

## @endpoint /api-key/{id}

Gets details of a specific API key.

### Parameters
- `id` (path, required): Numeric ID of the API key

### Response
- `id`: Numeric ID
- `name`: Descriptive name of the key
- `api_key`: Token (partially hidden, e.g., `np_...xxxx`)
- `grants`: Array of assigned permissions
  - `nrn`: NRN of the context where the permission applies
  - `role_slug`: Identifier of the assigned role
- `tags`: Array of key-value tags
  - `key`: Tag name
  - `value`: Tag value
- `created_at`: Creation timestamp

### Known Roles
| Role Slug | Description |
|-----------|-------------|
| `controlplane:agent` | Communication with the control plane |
| `ops` | Execute operations and commands |
| `developer` | Development access |
| `secrets-reader` | Read secrets and parameters |
| `secops` | Security operations |

### Navigation
- **→ roles**: `grants[].role_slug` indicates assigned permissions
- **← notification_channel**: The `agent` type channel references an API key

### Example
```bash
np-api fetch-api "/api-key/1896628918"
```

### Example Response
```json
{
  "id": 1896628918,
  "name": "SCOPE_DEFINITION_AGENT_ASSOCIATION",
  "api_key": "np_...8a4f",
  "grants": [
    {
      "nrn": "organization=1875247450:account=1514930957",
      "role_slug": "controlplane:agent"
    },
    {
      "nrn": "organization=1875247450:account=1514930957",
      "role_slug": "ops"
    }
  ],
  "tags": [
    {"key": "managed-by", "value": "IaC"}
  ],
  "created_at": "2025-01-25T10:30:00Z"
}
```

### Notes
- The complete secret value is only shown when creating the key
- Keys created by Terraform have tag `managed-by: IaC`
- For notification channels, the API key needs at least `controlplane:agent` + `ops`

---

## @endpoint /api-key

Lists API keys with filters.

### Parameters
- `nrn` (query, optional): Filter by NRN (URL-encoded)
- `name` (query, optional): Filter by name
- `limit` (query, optional): Maximum results (default: 30)
- `offset` (query, optional): For pagination

### Response
```json
{
  "paging": {
    "total": 5,
    "offset": 0,
    "limit": 30
  },
  "results": [
    {
      "id": 1896628918,
      "name": "SCOPE_DEFINITION_AGENT_ASSOCIATION",
      "grants": [...],
      "tags": [...],
      "created_at": "..."
    }
  ]
}
```

### Navigation
- **→ detail**: `results[].id` → `/api-key/{id}`

### Examples
```bash
# List all API keys of an organization
np-api fetch-api "/api-key?nrn=organization%3D1875247450"

# Search by specific name
np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# With pagination
np-api fetch-api "/api-key?nrn=organization%3D1875247450&limit=10&offset=0"
```

### Notes
- The NRN must be URL-encoded (`=` → `%3D`, `:` → `%3A`)
- Without filters returns keys accessible to the current user
- Paginated response with `paging` and `results`

---

## Common Use Cases

### Diagnose Notification Channel Permissions

When a scope fails with "You're not authorized":

```bash
# 1. Get the scope's channel
np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"

# 2. Search the API key by name (visible in the channel)
np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# 3. View the API key grants
np-api fetch-api "/api-key/{api_key_id}"

# 4. Verify it has: controlplane:agent + ops
```

### Compare API Keys

To verify differences between a channel's API key and the agent's:

```bash
# Channel API key (created by Terraform)
np-api fetch-api "/api-key/1896628918"

# Agent API key (more permissions)
np-api fetch-api "/api-key/1724072588"
```

The agent's typically has more roles than the channel's.
