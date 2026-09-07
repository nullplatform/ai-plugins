# Scopes

Scopes represent environments/targets for deployments (qa, staging, prod).

## @endpoint /scope/{id}

Gets details of a scope.

### Parameters
- `id` (path, required): Scope ID

### Response
- `id`: Numeric ID
- `name`: Scope name (changes to `deleted-{timestamp}-{name}` when deleted)
- `status`: active | unhealthy | deleted | failed | updating | stopped | stopping | creating | pending
- `application_id`: Application ID
- `asset_name`: Associated asset name (e.g., `docker-image-asset`, `lambda-asset`). **CRITICAL for deployments**: if `null`, deployments fail with a confusing error. Must be set before deploying
- `instance_id`: Associated service ID (**important for getting deployment actions**)
- `active_deployment`: Active deployment ID (**ONLY in individual GET, NOT in listings**)
- `current_active_deployment`: Active deployment ID (same as active_deployment)
- `nrn`: organization=X:account=Y:namespace=Z
- `provider`: Scope type identifier. Can be:
  - **Legacy (fixed string)**: `AWS:SERVERLESS:LAMBDA`, `AWS:WEB_POOL:EKS`, `AWS:WEB_POOL:EC2INSTANCES`
  - **New (UUID)**: reference to a `service_specification` that defines the capabilities schema
- `dimensions`: Scope classification
  - `environment`: dev | qa | staging | prod
  - `country`: us | mx | ar | br
  - `compliance`: banxico | pci | hipaa
- `capabilities`: **depends on provider** - each service_specification defines its own schema. Typical K8s example:
  - `scheduled_stop`: auto-stop config (enabled, timer in seconds)
  - `auto_scaling`: HPA config (min_amount, max_amount, cpu, memory)
  - `health_check`: probe config
  - `logs`: provider and throttling
  - Full K8s schema: [nullplatform/scopes](https://github.com/nullplatform/scopes/blob/main/k8s/specs/service-spec.json.tpl)
- `specification.replicas`: Default replicas
- `specification.resources`: memory, cpu
- `stops_at`: Next auto-stop timestamp (if scheduled_stop enabled)

### Navigation
- **→ application**: `application_id` → `/application/{application_id}`
- **→ deployments**: `/deployment?scope_id={id}`
- **→ deployment actions**: `instance_id` → `/service/{instance_id}/action`
- **→ instances**: `/telemetry/instance?application_id={app_id}&scope_id={id}`
- **→ namespace**: extract namespace_id from NRN
- **← application**: `/scope?application_id={application_id}`

### Example
```bash
np-api fetch-api "/scope/415005828"

# With error messages (useful for diagnosing delete or creation failures)
np-api fetch-api "/scope/415005828?include_messages=true"
```

### Notes
- **`include_messages=true`**: Includes the `messages[]` array with scope errors and events. Without this param, `messages` comes empty. Useful for diagnosing scopes in `failed` status (e.g., deprovisioning errors like "Error deleting ingress...")
- `instance_id` is key for getting deployment actions via `/service/{instance_id}/action`
- When scope is deleted, name changes to `deleted-{timestamp}-{original-name}`
- `status: active` does NOT change when scope auto-stops - only metrics show 0
- Deleted scopes cannot be recovered - must be recreated
- **IMPORTANT**: `active_deployment` and `current_active_deployment` ONLY appear in individual GET (`/scope/{id}`), NOT in listings (`/scope?application_id=X`)
- **IMPORTANT**: `asset_name` must be set for deployments to work. If `null`, `POST /deployment` fails with `"The scope and the release belongs to different applications"`. Set with `PATCH /scope/{id}` sending `{"asset_name": "docker-image-asset"}`

---

## @endpoint /scope

Lists scopes of an application.

### Parameters

- `application_id` (query, required): Application ID
- `status` (query): Filter by status (active, deleted, etc.)
- `limit` (query): Maximum results
- `offset` (query): For pagination

### Response

Paginated object:

```json
{
  "paging": {"total": 3, "offset": 0, "limit": 30},
  "results": [
    {"id": 415005828, "name": "qa private", "status": "active", ...}
  ]
}
```

### Example

```bash
np-api fetch-api "/scope?application_id=489238271"

# Only active scopes
np-api fetch-api "/scope?application_id=489238271&status=active"
```

### Notes

- Returns object with `paging` and `results` (like other endpoints)
- Deleted scopes may NOT appear in the list by default
- **IMPORTANT**: The listing does NOT include `active_deployment` - use individual GET to obtain it

---

## Listing scopes by provider

The `/scope` endpoint does not support provider filter. To list all organization scopes by provider:

### Method: via /service (type=scope)

Each scope with UUID provider has an associated service where `specification_id` = provider.

```bash
# 1. List all type=scope services of the org
np-api fetch-api "/service?nrn=organization%3D{org_id}:account%3D*&type=scope&limit=1500"

# 2. Filter by specification_id (provider UUID)
| jq '[.results[] | select(.specification_id == "480c7522-...") | {name, status, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### Useful service (type=scope) fields

- `specification_id`: Provider UUID (service_specification)
- `entity_nrn`: contains the scope's complete NRN
- `attributes`: equivalent to scope's `capabilities`
- `status`: active | failed | creating | etc

### Example: find scopes without certain capabilities

```bash
# Compare service attributes against a reference scope
jq '[.results[] | select(.specification_id == "UUID") |
  select((.attributes | has("traffic_management")) | not) |
  {name, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### UI URL

To build a scope's UI URL:
```
https://{organization_slug}.app.nullplatform.io/{entity_nrn}
```

---

## @endpoint /scope_type

Lists available scope types for an application. This endpoint replaces
the use of `/service_specification` for discovering scope types.

### Parameters

- `nrn` (query, required): URL-encoded application NRN (e.g., `organization%3D123%3Aaccount%3D456%3Anamespace%3D789%3Aapplication%3D101`)
- `status` (query): Filter by status (e.g., `active`)
- `include` (query): Additional fields to include (e.g., `capabilities,wildcard,available`)

### Response

Array of scope types:

```json
[
  {
    "id": 123,
    "type": "web_pool_k8s",
    "name": "Kubernetes",
    "description": "Docker containers on pods",
    "provider_type": "null_native",
    "provider_id": "AWS:WEB_POOL:EKS",
    "available": true,
    "parameters": {"schema": {...}}
  }
]
```

### Key fields

- `id`: Numeric type ID
- `type`: Technical type — `web_pool`, `web_pool_k8s`, `serverless`, `custom`
- `name`: Friendly name (e.g., "Kubernetes", "Scheduled Task", "Server instances")
- `description`: Type description
- `provider_type`: `null_native` (built-in types) or `service` (custom types via service_specification)
- `provider_id`: Provider ID for POST /scope — can be fixed string (`AWS:WEB_POOL:EKS`) or UUID
- `available`: Boolean — indicates if the type is available for the current application/account
- `parameters.schema`: Capabilities JSON schema (mainly for `custom` type)

### Navigation

- **→ scope creation**: `type` and `provider_id` are used in POST `/scope`
- **→ capabilities**: `/capability?nrn={nrn}&target=scope` for native types
- **← application**: filter by application NRN

### Example

```bash
# List available scope types for an application
np-api fetch-api "/scope_type?nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973%3Aapplication%3D1914258629&status=active&include=capabilities,wildcard,available"
```

### Notes

- **Only show types with `available: true`** to the user — the rest are not enabled
- Types vary between organizations/accounts — never assume specific types exist
- For `custom` type, `provider_id` is a UUID referencing a `service_specification`
- For native types (`web_pool_k8s`, `serverless`), `provider_id` is a fixed string
- The scope_type's `type` field is used directly as `type` in POST `/scope`

---

## @endpoint /capability

Lists configurable capabilities for a target (scope, deployment, etc.).
Used to discover what can be configured when creating a native scope type.

### Parameters

- `nrn` (query, required): URL-encoded application NRN
- `target` (query, required): Capabilities target (e.g., `scope`)

### Response

Array of capabilities:

```json
[
  {
    "id": 456,
    "slug": "auto_scaling",
    "name": "Auto Scaling",
    "target": "scope",
    "definition": {
      "type": "object",
      "properties": {
        "enabled": {"type": "boolean"},
        "instances": {
          "type": "object",
          "properties": {
            "amount": {"type": "integer"},
            "min_amount": {"type": "integer"},
            "max_amount": {"type": "integer"}
          }
        }
      }
    }
  }
]
```

### Key fields

- `id`: Numeric capability ID
- `slug`: Identifier used as **key in the capabilities object** of POST /scope
- `name`: Friendly name
- `target`: Target it applies to (e.g., `scope`)
- `definition`: JSON schema defining the capability value structure

### Common capabilities for K8s scopes

| Slug | Name | Description |
|------|------|-------------|
| `visibility` | Visibility | Public/private visibility (create only) |
| `listener_protocol` | Listener Protocol | HTTP/gRPC protocol |
| `memory` | Memory | Memory in GB |
| `kubernetes_processor` | Kubernetes Processor | CPU in millicores |
| `auto_scaling` | Auto Scaling | HPA: instances, CPU%, memory% |
| `health_check` | Health Check | Health probes (path, timeout, interval) |
| `logs` | Logs | Log provider and throttling |
| `metrics` | Metrics | Metrics providers |
| `continuous_delivery` | Continuous Delivery | Auto-deploy from branches |
| `scheduled_stop` | Scheduled Stop | Auto-stop after inactivity |

### Navigation

- **→ scope creation**: `slug` is used as key in `capabilities` of POST `/scope`
- **→ scope_type**: native types use capabilities from this endpoint; `custom` types use `parameters.schema`

### Example

```bash
# Get scope capabilities for an application
np-api fetch-api "/capability?nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973%3Aapplication%3D1914258629&target=scope"
```

### Notes

- Capabilities apply to **native** types (`web_pool_k8s`, `serverless`, `web_pool`)
- For `custom` types, capabilities are defined in `scope_type.parameters.schema`
- Each capability's `slug` is used as key in the `capabilities` object of POST `/scope`
- Each capability has its own JSON schema in `definition` describing the expected structure
