# Link Provisioning Flow

## Diagram

```
UI/API creates link: POST /link -> status: pending
  -> UI/API creates action instance: POST /link/{id}/action
  -> Service API -> SNS/SQS -> Lambda -> Notification API -> agents-api -> agent
  -> np-agent: entrypoint detects IS_LINK_ACTION=true, ACTION_SOURCE=link
  -> handler "link" maps create->link, update->link-update, delete->unlink
  -> np service workflow exec --workflow <link|link-update|unlink>.yaml
     Step 1: build_context (extract service + link data)
     Step 2: build_permissions_context (derive ARNs, set permissions module)
     Step 3: do_tofu (apply permissions/)
     Step 4: write_link_outputs (optional, write credentials)
```

## Actions are NOT Automatic

`use_default_actions: true` creates action **specifications** (templates), NOT instances.

The UI creates action instances automatically when a user clicks "Create Link". But when testing via API, you must create them manually:

```bash
# 1. Find action specifications for the link spec
/np-api fetch-api "/action_specification?link_specification_id=<link_spec_id>"

# 2. Create action instance (find the "create" spec)
TOKEN=$(cat np-api-skill.key)
curl -s -X POST "https://api.nullplatform.com/link/<link_id>/action" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"specification_id": "<create_action_spec_id>"}'
```

Same pattern for services: `POST /service/{id}/action`.

## Service vs Link Comparison

| Aspect | Service | Link |
|--------|---------|------|
| Notification source | `service` | `service` (same!) |
| Handler | `./service` | `./link` |
| Workflow | `create.yaml` | `link.yaml` / `link-update.yaml` / `unlink.yaml` |
| Terraform module | `deployment/` | `permissions/` |
| Outputs | write_service_outputs | write_link_outputs |

## Permissions Patterns

### Derive names from $CONTEXT — no API calls

The `$LINK` object contains scope slug, app slug, and entity attributes. Use them to build deterministic names without calling the API:

```bash
SCOPE_SLUG=$(echo "$LINK" | jq -r '.scope.slug // ""')
APP_SLUG=$(echo "$LINK" | jq -r '.entity.slug // ""')
APP_NRN=$(echo "$LINK" | jq -r '.entity.nrn // ""')
```

Build resource names from these fields — **always use `sanitize_name()`** to truncate (see `np-service-workflows` docs/build-context-patterns.md):
```bash
IAM_USER_NAME=$(sanitize_name "${SERVICE_NAME}-${LINK_ID}" 64 "$LINK_ID")
POLICY_NAME=$(sanitize_name "${SERVICE_NAME}-${SCOPE_SLUG}-${APP_SLUG}" 128 "$LINK_ID")
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"  # ARN from name, not from .service.attributes
```

### app_role_name fallback (from $LINK, not API)

```bash
APP_ROLE_NAME=$(echo "$LINK" | jq -r '.entity.attributes.role_name // .scope.attributes.role_name // ""')
if [ -z "$APP_ROLE_NAME" ]; then
  APP_ROLE_NAME=$(yaml_value "app_role_name" "" "$VALUES")
fi
```

Make optional in terraform: `count = var.app_role_name != "" ? 1 : 0`

### State per link

Each link gets its own tfstate:
```bash
TOFU_INIT_VARIABLES="-backend-config=key=services/${SERVICE_NAME}/links/${LINK_ID}.tfstate"
```

## Link Attributes vs Parameters

On first link action, `.link.attributes` may be empty. User-chosen values (e.g., `accessLevel`) come in `.parameters`:
```bash
LINK_ACCESS_LEVEL=$(echo "$LINK" | jq -r '.attributes.accessLevel // "read-write"')
if [ "$LINK_ACCESS_LEVEL" = "read-write" ]; then
  LINK_ACCESS_LEVEL=$(echo "$CONTEXT" | jq -r '.parameters.accessLevel // "read-write"')
fi
```

## Export of Credentials

Fields in link spec with `export: true` or `export: {secret: true}` become env vars in the linked app. See `np-service-specs` docs/export-parameters.md for details.
