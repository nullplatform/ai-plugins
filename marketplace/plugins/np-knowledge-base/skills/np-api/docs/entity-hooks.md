# Entity Hooks

Entity hooks are lifecycle interceptors that execute before or after operations
on entities (applications, scopes, deployments). They allow validating, notifying, or blocking
operations automatically.

## @endpoint /entity_hook

Lists entity hook instances executed.

### Parameters
- `nrn` (query, required): URL-encoded NRN
- `entity_name` (query): Filter by entity type: `application` | `scope` | `deployment`
- `limit` (query): Maximum results (default 30)

### Response
```json
{
  "paging": {"total": 247, "offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "entity_hook_action_id": "uuid-of-the-hook-definition",
      "entity_id": "987962648",
      "entity_name": "application",
      "entity_action": "application:create",
      "nrn": "organization=...:application=987962648",
      "status": "success | pending | failed | recoverable_failure | cancelled",
      "execution_status": "pending | running | completed",
      "when": "before | after",
      "type": "hook",
      "on": "create | write | delete",
      "messages": [
        {"level": "info", "message": "information from the hook"},
        {"level": "warning", "message": "warning report"},
        {"level": "error", "message": "the hook has failed"}
      ],
      "dimensions": {"country": "uruguay", "environment": "development"},
      "dependencies": [],
      "requests": [],
      "user_id": 421006915,
      "policy_context": null,
      "context": null,
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Key fields
- `id`: UUID of the hook instance (specific execution)
- `entity_hook_action_id`: UUID of the hook definition (template/rule)
- `entity_name`: Entity type: `application`, `scope`, `deployment`
- `entity_action`: Complete action: `application:create`, `scope:create`, `deployment:create`, `deployment:write`
- `entity_id`: ID of the affected entity
- `nrn`: Complete NRN of the entity
- `status`: Hook status: `success` (passed), `pending` (waiting), `failed` (failed), `recoverable_failure` (recoverable failure), `cancelled`
- `execution_status`: Execution status: `pending`, `running`, `completed`
- `when`: `before` (pre-operation, can block) | `after` (post-operation, notification)
- `on`: Operation type: `create` | `write` | `delete`
- `messages[]`: Hook execution logs (info/warning/error)
- `dimensions`: Dimensions of the affected entity (may be empty)
- `context`: Snapshot of the entity at hook time (may be null or contain the complete object)

### Known entity actions
- `application:create` - When creating an application
- `scope:create` - When creating a scope
- `scope:delete` - When deleting a scope
- `deployment:create` - When creating a deployment
- `deployment:write` - When modifying a deployment (e.g., traffic switch)

### Example
```bash
# All organization hooks
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411"

# Only scope hooks
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&entity_name=scope"

# Only deployment hooks
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&entity_name=deployment"

# Filter failed hooks with jq
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&limit=100" | jq '[.results[] | select(.status == "failed")]'
```

### Notes
- `before` hooks can **block** the operation if they fail (status=failed)
- `after` hooks are informational and don't block
- `context` contains the entity snapshot — useful for diagnosing what was being created/modified
- If a scope stays in `pending` or `creating`, check if there's a `before` hook blocking it
- Hooks are defined via `entity_hook_action` (the definition/template), this endpoint shows the instances/executions

---

## @endpoint /entity_hook/{id}

Gets detail of an entity hook instance.

### Parameters
- `id` (path, required): UUID of the hook instance

### Response
Same structure as a list element (see above).

### Example
```bash
np-api fetch-api "/entity_hook/2477f213-926d-423e-89ce-d18c5570d24c"
```

### Notes
- Useful to verify the status of a specific hook
- The `context` field may contain the complete entity object at hook time

---

## @endpoint /entity_hook/action

Lists entity hook definitions (templates/rules). These are the rules that determine
which hooks execute when an operation occurs on an entity.

### Parameters
- `nrn` (query, required): URL-encoded NRN

### Response
```json
{
  "paging": {"total": 5, "offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "entity": "scope",
      "action": "scope:create",
      "when": "before",
      "type": "hook",
      "on": "create",
      "nrn": "organization=1255165411:account=95118862",
      "dimensions": {"environment": "production"},
      "notification_channel_id": 12345,
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Key fields
- `id`: UUID of the hook definition
- `entity`: Monitored entity type: `application` | `scope` | `deployment`
- `action`: Action that triggers the hook: `application:create`, `scope:create`, `scope:delete`, `deployment:create`, `deployment:write`
- `when`: `before` (can block) | `after` (informational)
- `on`: Operation type: `create` | `write` | `delete`
- `nrn`: NRN where the rule applies (cascades to children)
- `dimensions`: Dimension filter — the hook only executes if the entity's dimensions match
- `notification_channel_id`: Notification channel that receives and processes the hook

### Relationship with instances

Definitions (`/entity_hook/action`) are the rules. Instances (`/entity_hook`) are
the concrete executions. Each time an entity is created/modified that matches a rule,
an instance is created with `entity_hook_action_id` pointing to the definition.

### Example
```bash
# List all organization hook definitions
np-api fetch-api "/entity_hook/action?nrn=organization%3D1255165411"

# Filter by entity_name
np-api fetch-api "/entity_hook/action?nrn=organization%3D1255165411" | jq '[.results[] | select(.entity == "scope")]'
```

### Notes
- Definitions require a previously configured notification channel
- The `dimensions` field allows a hook to only apply to certain environments/countries
- `before` hooks block the operation until receiving a response: `success`, `failed`, `recoverable_failure`, or `cancelled`
- Approvals take precedence over hooks (evaluated first)

---

## @endpoint /entity_hook/action/{id}

Gets detail of a specific entity hook definition.

### Parameters
- `id` (path, required): UUID of the definition

### Response
Same structure as a list element from `/entity_hook/action`.

### Example
```bash
np-api fetch-api "/entity_hook/action/5c545ae0-bb00-424c-8dcd-d4e64af51ad8"
```

---

## Use in diagnostics

Entity hooks are a common cause of entities that get "stuck" in `pending` or `creating`:

1. Check if there are pending hooks: `GET /entity_hook?nrn=...&entity_name=scope`
2. Filter by `status: "pending"` or `status: "failed"`
3. Review `messages[]` to understand why it failed
4. The `entity_id` indicates which entity is blocked
