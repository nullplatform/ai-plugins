# Applications

Applications are deployable code containers that define runtime, build, health checks, and resources.

## @endpoint /application/{id}

Gets details of an application.

### Parameters
- `id` (path, required): Application ID

### Response
- `id`: Numeric ID
- `name`: Unique name within the namespace
- `type`: service | function | job | static
- `status`: active | inactive | archived
- `nrn`: Hierarchical identifier (organization=X:account=Y:namespace=Z:application=W)
- `specification.runtime`: language, version
- `specification.build`: command, output_path
- `specification.health_check`: path, port, initial_delay_seconds, period_seconds, timeout_seconds, failure_threshold
- `specification.resources`: memory, cpu
- `metadata`: Additional properties (only in individual GET, NOT in lists)

### Navigation
- **→ namespace**: extract namespace_id from NRN → `/namespace/{namespace_id}`
- **→ scopes**: `/scope?application_id={id}`
- **→ builds**: `/build?application_id={id}`
- **→ services**: via `linkable_to` in services

### Example
```bash
np-api fetch-api "/application/489238271"
```

### Notes
- `specification.health_check` is critical for deployment troubleshooting
- `initial_delay_seconds` too low causes probe failures in Java apps (need 60-120s)
- `metadata` only available in individual GET, NOT in lists - cannot filter by metadata

---

## @endpoint /application

Lists applications with filters.

### Parameters
- `namespace_id` (query): Filter by namespace
- `status` (query): Filter by status (active, inactive, archived)
- `limit` (query): Maximum results (default 30)
- `offset` (query): For pagination

### Response
```json
{
  "paging": {"total": 69, "offset": 0, "limit": 30},
  "results": [
    {"id": 123, "name": "my-app", "type": "service", "status": "active"}
  ]
}
```

### Navigation
- **→ application details**: `/application/{id}` for each result

### Example
```bash
np-api fetch-api "/application?namespace_id={namespace_id}&limit=100"

# Only active applications
np-api fetch-api "/application?namespace_id={namespace_id}&status=active"
```

### Notes
- Paginated response with `paging` and `results`
- Does NOT include `metadata` field - requires individual fetch by ID
- Use `status=active` to exclude inactive or archived applications

---

## @endpoint /template

Lists available technology templates for creating applications.

### Parameters
- `target_nrn` (query, recommended): Namespace NRN to filter applicable templates
- `global_templates` (query): `true` to include global Nullplatform templates in addition to org ones
- `limit` (query): Maximum results (default 30, use 200 to get all)

### Response
```json
{
  "paging": {},
  "results": [
    {
      "id": 1220542475,
      "name": "NodeJS + Fastify",
      "status": "active",
      "url": "https://github.com/nullplatform/technology-templates-nodejs-container",
      "organization": null,
      "account": null,
      "tags": ["javascript", "fastify", "backend"],
      "rules": {},
      "components": [{"type": "language", "id": "javascript", "version": "es6"}]
    }
  ]
}
```

### Navigation
- **← from application**: `template_id` in the application → `/template/{id}` (not documented, use list)

### Example
```bash
# Templates for a specific namespace (includes globals)
np-api fetch-api "/template?limit=200&target_nrn=organization=X:account=Y:namespace=Z&global_templates=true"
```

### Notes
- Templates with `organization: null` are global Nullplatform templates
- Templates with `organization` and `account` are org/account-specific
- Filter `status: "active"` before showing to the user
- The `rules` field may contain name and repository path validation rules
- `components` describes the technology (language, framework, runtime)
