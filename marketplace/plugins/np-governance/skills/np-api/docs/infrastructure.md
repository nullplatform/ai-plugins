# Infrastructure (Organization, Account, Namespace, Provider, Agent)

Infrastructure entities and organizational hierarchy.

## @endpoint /organization/{id}

Gets details of an organization.

### Parameters
- `id` (path, required): Organization ID

### Response
- `id`: Numeric ID
- `name`: Organization name
- `settings`: Org-level configuration

### Navigation
- **→ accounts**: `/account?organization_id={id}` (if filter exists)

### Example
```bash
np-api fetch-api "/organization/549683990"
```

---

## @endpoint /organization

Lists organizations.

### Example
```bash
np-api fetch-api "/organization"
```

---

## @endpoint /account/{id}

Gets details of an account.

### Parameters
- `id` (path, required): Account ID

### Response
- `id`: Numeric ID
- `name`: Account name
- `slug`: URL-friendly identifier
- `status`: Status
- `organization_id`: Parent organization ID
- `settings`: Configuration (region, tier)
- `created_at`, `updated_at`: Timestamps

### Navigation
- **→ organization**: `organization_id` → `/organization/{organization_id}`
- **→ namespaces**: `/namespace?account_id={id}` (if filter exists)
- **← organization**: part of the NRN

### Example
```bash
np-api fetch-api "/account/463975847"
```

---

## @endpoint /account

Lists accounts of an organization.

### Parameters
- `organization_id` (query, required): Organization ID. Obtained from the JWT token (check-auth shows it).
- `status` (query): Filter by status (active, inactive)
- `limit` (query): Maximum results (default 30)
- `offset` (query): For pagination

### Response
```json
{
  "paging": {"total": 8, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 95118862,
      "name": "main",
      "organization_id": 1255165411,
      "repository_prefix": "kwik-e-mart",
      "repository_provider": "github",
      "status": "active",
      "slug": "kwik-e-mart-main",
      "nrn": "organization=1255165411:account=95118862"
    }
  ]
}
```

### Navigation
- **← organization**: `organization_id` from JWT token
- **→ namespaces**: `/namespace?account_id={id}`

### Example
```bash
# List organization accounts (organization_id from JWT)
np-api fetch-api "/account?organization_id=1255165411"

# Only active accounts
np-api fetch-api "/account?organization_id=1255165411&status=active"
```

### Notes
- This is the first bootstrap step: JWT → accounts → namespaces → applications
- `repository_prefix` and `repository_provider` indicate where app repos are created
- Paginated response with `paging` and `results`

---

## @endpoint /namespace/{id}

Gets details of a namespace.

### Parameters
- `id` (path, required): Namespace ID

### Response
- `id`: Numeric ID
- `name`: Namespace name
- `slug`: URL-friendly identifier
- `status`: Status
- `account_id`: Parent account ID
- `nrn`: Complete NRN
- `configuration`: region, cluster settings
- `metadata`: Additional properties

### Navigation
- **→ account**: `account_id` → `/account/{account_id}`
- **→ applications**: `/application?namespace_id={id}`

### Example
```bash
np-api fetch-api "/namespace/476951634"
```

---

## @endpoint /namespace

Lists namespaces of an account.

### Parameters
- `account_id` (query, required): Account ID. Obtained from `GET /account?organization_id=<org_id>`.
- `status` (query): Filter by status (active, inactive)
- `limit` (query): Maximum results (default 30)
- `offset` (query): For pagination

### Response
```json
{
  "paging": {"total": 143, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 463208973,
      "name": "Nullplatform Demos",
      "account_id": 95118862,
      "slug": "nullplatform-demos",
      "status": "active",
      "nrn": "organization=1255165411:account=95118862:namespace=463208973"
    }
  ]
}
```

### Navigation
- **← account**: `account_id` → `/account/{account_id}`
- **→ applications**: `/application?namespace_id={id}`

### Example
```bash
# List namespaces of an account
np-api fetch-api "/namespace?account_id=95118862&status=active&limit=50"
```

### Notes
- Second bootstrap step: JWT → accounts → **namespaces** → applications
- Paginated response with `paging` and `results`
- A namespace may have no applications (e.g., newly created namespace)

---

## @endpoint /provider

Lists providers (configured cloud provider instances).

### Parameters
- `nrn` (query, required): Base NRN
- `show_descendants` (query): **snake_case** - includes providers from lower hierarchy
- `limit` (query): Maximum results

### Example
```bash
np-api fetch-api "/provider?nrn=organization=4&show_descendants=true&limit=200"
```

### Notes
- Use `show_descendants` (**snake_case**) NOT `showDescendants`
- Without `show_descendants=true` only returns providers at the specified NRN level

---

## @endpoint /provider_specification

Lists available provider specifications.

### Parameters
- `nrn` (query): NRN to filter

### Domain
```
https://providers.nullplatform.com/provider_specification?nrn=organization=123
```

### Example
```bash
np-api fetch-api "https://providers.nullplatform.com/provider_specification?nrn=organization=549683990"
```

---

## @endpoint /controlplane/agent

Lists agents (runtime agents on client infrastructure).

Agents are lightweight outbound-only services that connect the client's infrastructure
with Nullplatform. They connect to `agents.nullplatform.com:443` and poll for tasks that
match their tags.

### Parameters
- `organization_id` (query): Organization ID
- `account_id` (query): Account ID
- `nrn` (query): Alternative NRN (e.g., `organization=1:account=2`)

### Response
```json
{
  "results": [
    {
      "id": "uuid",
      "name": "my-agent-name",
      "nrns": ["organization=1255165411:account=95118862"],
      "status": "active",
      "capabilities": [],
      "tags": {"cloud": "aws", "region": "us-east-1"},
      "heartbeat": "2026-02-25T10:00:00Z",
      "version": "1.2.3",
      "channel_selectors": {}
    }
  ]
}
```

### Key fields
- `id`: Agent UUID
- `name`: Agent name
- `nrns[]`: Array of NRNs where the agent is registered (can be in multiple accounts)
- `status`: `active` | others
- `capabilities`: Agent capabilities
- `tags`: Tags for routing. Tasks are routed to the agent whose tags match
- `heartbeat`: Last heartbeat — useful to verify if the agent is alive
- `version`: Agent version

### Agent notification channels

Agents can process platform notifications by executing scripts on the client's infrastructure.
There are two types of notification channels for agents:

| Type | Description |
|------|-------------|
| `agent` | Executes a local script on the infrastructure where the agent runs |
| `http` | Makes an HTTP request to a remote handler |

Agent notification channels are configured in `/notification/channel` with `type: agent` or
`type: http`. The agent polls for notifications matching its tags and processes them.

### Authentication
Agents require an API key with `controlplane:agent` and `ops` roles to register
and authenticate with the control plane.

### Example
```bash
# By organization_id and account_id
np-api fetch-api "/controlplane/agent?organization_id=1255165411&account_id=95118862"

# By NRN
np-api fetch-api "/controlplane/agent?nrn=organization%3D1255165411%3Aaccount%3D95118862"
```

### Notes
- Agents are outbound-only: they connect to Nullplatform, not the other way around
- Tag-based routing: agents only process tasks that match their tags
- Supports deployment via: Helm, Docker, binary, serverless
- If an agent has no recent heartbeat, it's down or disconnected
