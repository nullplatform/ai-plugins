# Automation: Interceptors, Events, Custom Actions

Handlers hang off a specification and react to instance lifecycle actions. Two kinds
with opposite guarantees:

| | Interceptors | Events |
|---|---|---|
| Timing | BEFORE the mutation, sequential by `ordinal` | AFTER the mutation, parallel |
| Can block? | Yes — sync gate | No — fire-and-forget, errors never surface |
| Semantics | 2xx allow · 4xx reject (becomes the caller's error) · 5xx → `on_failure` decides (`fail` aborts, `skip` continues) | none |
| Can mutate data? | Yes — a 2xx body `{ "data": {...} }` merge-patches the instance | No |

Handlers are per-tenant. `action` targets `create`, `update`, `delete`, or a custom
action slug.

## Handler CRUD (same shape for both; swap `interceptors` ↔ `events`)

```bash
catalog-api.sh GET  /specifications/<specId>/interceptors
catalog-api.sh POST /specifications/<specId>/interceptors '{
  "action": "create",
  "url": "https://hooks.example.com/gate",
  "method": "POST",
  "ordinal": 0,
  "on_failure": "fail",
  "payload_format": "cloud_events",
  "timeout_ms": 5000,
  "retry": { "max_attempts": 3, "backoff_ms": 500 }
}'
catalog-api.sh GET    /specifications/<specId>/interceptors/<handlerId>
catalog-api.sh PATCH  /specifications/<specId>/interceptors/<handlerId> '{"enabled": false}'
catalog-api.sh DELETE /specifications/<specId>/interceptors/<handlerId>
```

- Create requires `action` + `url`. `url` supports `${...}` templates.
- `action` is **immutable** after create — recreate the handler to retarget it.
- `headers` and `body` are **write-only** (secrets): reads omit them; a PATCH
  replaces them.
- `payload_format`: `cloud_events` sends a CloudEvents envelope automatically;
  `custom` gives the handler full control of body/headers via templates.
- Payloads carry instance data **alias-keyed**, with snake_case envelope keys
  (`tenant_id`, `action`, `changed_fields`, ...).
- Filter listings with `?action=create`.

## Custom actions

Declared in the spec's `schema.actions`, keyed by slug:

```json
{
  "actions": {
    "reboot": {
      "name": "Reboot",
      "description": "Restart the instance",
      "input":  { "type": "object", "properties": { "force": { "type": "boolean" } } },
      "output": { "type": "object" },
      "enabled": true
    }
  }
}
```

`name` required; `input`/`output` are JSON Schemas validating the execution payload
and result; `enabled` defaults to true. Action slugs join the vocabulary of handler
`action` fields and authorization `action:<slug>` grants. Slugs match
`^[a-z][a-z0-9-]*$` — dashes are fine (`rotate-keys`); the snake_case rule applies
to enum values and aliases, not action slugs.

### Executing

```bash
# Fire an action against an instance (body validated against the action's input schema)
# → 202 with a PENDING execution record
catalog-api.sh POST /actions/service/<entityId>/reboot '{"force": true}'

# Execution history for an instance
catalog-api.sh GET '/actions/service/<entityId>/history?limit=30'

# Read / advance one execution (async executors report status + output here)
# status enum: pending | success | failed
catalog-api.sh GET   /actions/service/executions/<executionId>
catalog-api.sh PATCH /actions/service/executions/<executionId> '{"status": "success", "output": {...}}'
```

Execution flow: the POST validates input, runs the action's interceptors (they
gate it like any mutation), persists a `pending` execution record, fires events
(they deliver it to executors), and answers **202**. An external executor
PATCHes the execution to `success`/`failed` with `output`. Requires an
`action:<slug>` (or `*`) grant on the `entities` plane — custom actions ride the
platform `entity:write` verb.

Removing an action from the schema does NOT purge its execution history —
existing execution records survive and stay readable.
