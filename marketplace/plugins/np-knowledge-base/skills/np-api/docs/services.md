# Services

Services are provisioned infrastructure. There are two types:
- **dependency**: databases, caches, load balancers, etc.
- **scope**: internal representation of a scope (only for UUID providers)

## @endpoint /service/{id}

Gets details of a service.

### Parameters
- `id` (path, required): Service UUID

### Response
- `id`: UUID
- `name`: Service name
- `slug`: URL-friendly identifier
- `status`: active | failed | pending | updating | deleting | creating
- `type`: dependency | scope
- `specification_id`: Service specification UUID (template). For type=scope, this is the scope's **provider**
- `desired_specification_id`: If there's a pending update
- `entity_nrn`: Organizational context NRN
- `linkable_to[]`: NRNs of applications that can link this service
- `attributes`: Service-specific configuration
  - Database: host, port, username, database
  - AWS: vpc_id, subnet_ids, access_key_id, secret_access_key
- `selectors`:
  - `category`: database | cache | messaging | any
  - `provider`: aws | gcp | azure | any
  - `sub_category`: more specific
  - `imported`: boolean - whether it's an imported existing resource
- `messages[]`: Events (may be empty - see service actions)

### Navigation
- **→ specification**: `specification_id` → `/service_specification/{specification_id}`
- **→ actions**: `/service/{id}/action`
- **→ linked apps**: parse `linkable_to[]` NRNs

### Example
```bash
np-api fetch-api "/service/ef3baa4e-6144-457e-8812-280976eab7f3"
```

### Notes
- `status: failed` requires manual intervention
- `messages[]` may be empty even for failed - review `/service/{id}/action`
- `attributes` may contain sensitive credentials
- Imported services (`imported: true`) don't execute provisioning

---

## @endpoint /service

Lists services by NRN.

### Parameters
- `nrn` (query, required): URL-encoded NRN
- `type` (query): Filter by type: `dependency` | `scope`
- `limit` (query): Maximum results (default 30)

### NRN with Wildcards
- `organization=123` → Only org-level services
- `organization=123:account=456` → Services of that account
- `organization=123:account=*` → **ALL** org services (wildcard)

### Response
```json
{
  "paging": {"offset": 0, "limit": 1500},
  "results": [...]
}
```

### Example
```bash
# All services of an organization
np-api fetch-api "/service?nrn=organization%3D1255165411:account%3D*&limit=1500"

# Services of a specific account
np-api fetch-api "/service?nrn=organization%3D1255165411:account%3D95118862"
```

### GOTCHA: Do not use application_id as query param
- `GET /service?application_id=X` **does NOT work** — returns HTTP 403 ("Insufficient permissions") but the real error is that this filter is not supported.
- To list services of an application, always use NRN filter:
```bash
np-api fetch-api "/service?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>"
```

### GOTCHA: Visible services vs owned services (owned by app)

The `/service?nrn=<app_nrn>` endpoint returns **all visible services** for that application, including services inherited from upper levels (namespace, account, organization). This is the same as what the frontend shows in the "Available" tab.

To get only services **owned by an application** ("Owned by App" tab in the UI), you must filter client-side by `entity_nrn`:

```bash
# 1. Get all visible services
np-api fetch-api "/service?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>&type=dependency&limit=300"

# 2. Filter those whose entity_nrn == application's NRN
# Only services whose entity_nrn ends with "application=<app_id>" are owned by that app
```

There is **no** `entity_nrn` query param in the API. Filtering is always client-side.

---

## @endpoint /service/{id}/action

Lists actions executed on a service (GET) or creates a new action (POST via np-developer-actions).

### Parameters (GET)
- `id` (path, required): Service UUID
- `limit` (query): Maximum results

### Response (GET)
```json
{
  "results": [
    {
      "id": "uuid",
      "name": "start-blue-green | switch-traffic | finalize-blue-green | create-xxx | update-xxx | delete-xxx",
      "status": "pending | in_progress | success | failed",
      "specification_id": "uuid-of-the-action-specification",
      "parameters": {"deployment_id": "123", "scope_id": "456"},
      "results": {},
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### POST (create action) - via np-developer-actions

To create an action on a service (e.g., trigger provisioning):

```json
POST /service/{id}/action
{
  "name": "create-<service-slug>",
  "specification_id": "<action_specification_id>",
  "parameters": { ... }
}
```

- `name`: Convention: `<action_type>-<service_slug>` (e.g., "create-my-queue")
- `specification_id`: Action specification ID (obtained from `/service_specification/{spec_id}/action_specification`)
- `parameters`: Values according to the action specification's `parameters.schema`

**NOTE**: To execute this POST, use `/np-developer-actions exec-api`. See `docs/services.md` in np-developer-actions.

### Navigation
- **→ action details**: `/service/{id}/action/{action_id}?include_messages=true`
- **← deployment**: filter by `parameters.deployment_id`

### Example
```bash
# List all actions of a service
np-api fetch-api "/service/ef3baa4e-6144-457e-8812-280976eab7f3/action?limit=200"
```

### Notes
- **This is the endpoint for getting deployment actions** - `/deployment/{id}/action` does NOT exist
- For actions of a specific deployment: filter by `parameters.deployment_id`
- Deployment action types: start-blue-green, switch-traffic, finalize-blue-green
- Service provisioning action types: create, update, delete, custom
- Creating a service requires **two requests**: first `POST /service`, then `POST /service/{id}/action` with the CREATE action spec. Without the second request, the service stays in `pending` indefinitely

---

## @endpoint /service/{id}/action/{action_id}

Gets details of a specific action.

### Parameters
- `id` (path, required): Service UUID
- `action_id` (path, required): Action UUID
- `include_messages` (query, **recommended**): Includes execution logs

### Response (with include_messages=true)
```json
{
  "id": "uuid",
  "name": "finalize-blue-green",
  "status": "failed",
  "parameters": {...},
  "results": {...},
  "messages": [
    {"level": "info", "message": "Executing step: build context", "timestamp": 1765319248732},
    {"level": "info", "message": "Timeout waiting for ingress reconciliation after 120 seconds", "timestamp": 1765319369338}
  ]
}
```

### Example
```bash
np-api fetch-api "/service/ef3baa4e/action/a031f992?include_messages=true"
```

### Notes
- Without `include_messages=true`, the messages array comes empty
- Action messages show workflow details not visible in deployment messages
- Reveals: internal steps, executed commands, specific errors
- **IMPORTANT**: The `specification_id` field of a service action is an **internal action specification**, NOT a service_specification. Don't confuse with `service.specification_id` which does point to `/service_specification/{id}`

---

## @endpoint /service_specification

Lists available service specifications. Each service specification defines a type of service that can be provisioned (e.g., SQS Queue, Postgres DB, Redis).

### Parameters
- `nrn` (query, required): URL-encoded NRN. Use application-level NRN to get specs available in that context.
- `type` (query): Filter by type: `dependency` (infrastructure) | `scope` (scopes)
- `limit` (query): Maximum results (default 30)

### Response
```json
{
  "paging": {"offset": 0, "limit": 100},
  "results": [
    {
      "id": "uuid",
      "name": "SQS Queue",
      "slug": "sqs-queue",
      "type": "dependency",
      "selectors": {
        "category": "Messaging Services",
        "sub_category": "Message Queue",
        "provider": "AWS"
      },
      "schema": {},
      "default_configuration": {},
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Example
```bash
# Dependency service specifications for an application
np-api fetch-api "/service_specification?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>&type=dependency&limit=100"

# Scope service specifications for an account
np-api fetch-api "/service_specification?nrn=organization%3D<org>%3Aaccount%3D<acc>&type=scope"
```

### Notes
- `type=dependency`: databases, queues, caches, etc. (used by "+ New service" in the UI)
- `type=scope`: scope/environment types (used by scope creation)
- The `selectors` (category, sub_category, provider) allow classifying and filtering types

---

## @endpoint /service_specification/{id}

Gets the template/blueprint of a service.

### Parameters
- `id` (path, required): Specification UUID
- `application_id` (query, optional): Application ID (the frontend sends it for context)

### Response
- `id`: UUID
- `name`: Specification name (e.g., "SQS Queue", "Postgres DB")
- `slug`: URL-friendly identifier
- `type`: `dependency` | `scope`
- `selectors`: `{category, sub_category, provider, imported}`
- `attributes`: `{schema, values}` — schema of the service attributes (provisioning output)
- `dimensions`: Dimension restrictions
- `scopes`: Scope restrictions
- `visible_to[]`: NRNs of organizations/accounts that can see this spec
- `assignable_to`: `"any"` or restrictions
- `use_default_actions`: boolean — whether it auto-generates action specs (CREATE, UPDATE, DELETE)
- `created_at`, `updated_at`: timestamps

### Example
```bash
np-api fetch-api "/service_specification/529d8786-4af4-4625-87de-664ad7c9ef5f?application_id=2052735708"
```

### Notes
- `attributes.schema` defines the service's **output attributes** (e.g., queue_arn, host, port). Don't confuse with input parameters for creating the service.
- The **input parameters** for creating a service are obtained from the CREATE action specification via `/service_specification/{id}/action_specification`
- `use_default_actions: true` indicates that action specs (CREATE, UPDATE, DELETE) were auto-generated when this spec was created
- **`export` field in attributes.schema.properties**: determines which attributes are injected as parameters when linking the service:
  - `"export": true` → exported as plaintext parameter
  - `"export": {"type": "environment_variable", "secret": true}` → exported as secret parameter
  - `"export": false` or absent → NOT exported
  - Example SQS: `queue_arn` (export:true) is exported, `visibility_timeout` (no export) is not

---

## @endpoint /service_specification/{id}/link_specification

Lists link specifications associated with a service specification.

### Parameters
- `id` (path, required): Service specification UUID

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "Link SQS Queue",
      "slug": "link-sqs-queue",
      "specification_id": "uuid-of-service-specification",
      "use_default_actions": false,
      "attributes": {"schema": {}, "values": {}},
      "selectors": {}
    }
  ]
}
```

### Example
```bash
np-api fetch-api "/service_specification/529d8786-4af4-4625-87de-664ad7c9ef5f/link_specification"
```

### Notes
- Useful to know which link specifications are associated with a service type
- The frontend queries this when creating a service to show linking options

---

## @endpoint /service_specification/{id}/action_specification

Lists action specifications of a service specification (available action templates).

### Parameters
- `id` (path, required): Service specification UUID

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "Upload File",
      "slug": "upload-file",
      "type": "create | update | delete | custom | diagnose",
      "retryable": true,
      "parallelize": false,
      "service_specification_id": "uuid",
      "link_specification_id": null,
      "parameters": {"schema": {...}, "values": {}},
      "results": {"schema": {...}, "values": {}}
    }
  ]
}
```

### Navigation
- **← service_specification**: `/service_specification/{id}`
- **→ action instances**: `/service/{service_id}/action` (instances of these specs)

### Example
```bash
np-api fetch-api "/service_specification/f7248a07-909f-4241-b2c7-616d2403bf54/action_specification"
```

### Notes
- `use_default_actions: true` automatically generates specs of type create, update, delete
- Custom actions are added via `available_actions` in the service-spec.json.tpl
- `parameters` and `results` use `{"schema": {...}, "values": {}}` structure, NOT direct JSON Schema
- `type: custom` = doesn't affect the parent service status (unlike create/update/delete)
- `link_specification_id: null` = service-level action; with value = link-level action

---

## @endpoint /link

Lists links (service → application connections) filtered by NRN.

### Parameters
- `nrn` (query, required): URL-encoded application NRN. Use **application-level** NRN to get only that app's links.

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "lnk fees",
      "slug": "lnk-fees",
      "status": "active | pending | creating | failed",
      "service_id": "uuid-of-linked-service",
      "entity_nrn": "organization=...:application=...",
      "dimensions": {"environment": "production"},
      "specification_id": "uuid",
      "attributes": {
        "permisions": {"read": true, "write": true, "admin": false},
        "username": "usr...",
        "password": null
      },
      "selectors": {"category": "...", "imported": false, "provider": "...", "sub_category": "..."}
    }
  ]
}
```

### Navigation
- **→ link detail**: `/link/{id}`
- **→ link actions**: `/link/{id}/action`
- **→ linked service**: `service_id` → `/service/{service_id}`

### Example
```bash
# Links of a specific application
np-api fetch-api "/link?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>"
```

### Notes
- Without application-level NRN filter, returns links from the entire platform (thousands)
- The `service_id` field allows correlating with `/service/{id}` to know which service is linked
- The `attributes` field contains exported parameters (credentials, URLs, etc.)
- Parameters of type `linked_service` in `/parameter` are automatically generated by links

---

## @endpoint /link/{id}

Gets detail of a specific link.

### Parameters
- `id` (path, required): Link UUID

### Response
- `id`: Link UUID
- `name`: Link name
- `slug`: URL-friendly identifier
- `status`: active | pending | creating | failed
- `service_id`: Linked service UUID
- `entity_nrn`: Application NRN
- `dimensions`: Link dimensions
- `specification_id`: Link specification UUID
- `attributes`: Exported parameters (credentials, URLs, etc.)
- `selectors`: Category, provider, sub_category, imported
- `messages[]`: Link events

### Navigation
- **→ link actions**: `/link/{id}/action`
- **→ service**: `service_id` → `/service/{service_id}`

### Example
```bash
np-api fetch-api "/link/9ba2dfe6-b5db-484a-9804-01718199575a"
```

### Notes
- If `status: failed`, review `/link/{id}/action` to diagnose
- `attributes` may contain sensitive credentials

---

## @endpoint /link/{id}/action

Lists actions executed on a link (create, update, delete).

### Parameters
- `id` (path, required): Link UUID

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "create-lnk-xxx",
      "slug": "create-lnk-xxx",
      "status": "success | failed | pending | in_progress",
      "link_id": "uuid-of-the-link",
      "parameters": {"permisions": {"read": true, "write": true, "admin": false}},
      "results": {"username": "usr...", "password": null, "permisions": {...}},
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Navigation
- **← link**: `/link/{id}`

### Example
```bash
np-api fetch-api "/link/9ba2dfe6-b5db-484a-9804-01718199575a/action"
```

### POST (create action) - via np-developer-actions

To create an action on a link (e.g., provisioning on create, deprovisioning on delete):

```json
POST /link/{id}/action
{
  "name": "delete-<link-slug>",
  "specification_id": "<delete_action_specification_id>",
  "parameters": { ... }
}
```

- `name`: Convention: `<action_type>-<link_slug>` (e.g., "delete-lnk-prices-prod")
- `specification_id`: Delete action specification ID (obtained from `/link_specification/{spec_id}/action_specification`)
- `parameters`: Values according to the delete action specification's `parameters.schema`

**NOTE**: This is the method the UI uses to delete links with `use_default_actions: true`.
Creates a delete action that an agent processes to deprovision resources (delete DB user, etc.).

### Notes
- This is where the actual link provisioning errors are
- The `parameters` field shows what was sent, `results` shows what was generated (e.g., credentials)
- For detailed messages of a failed action: `/link/{id}/action/{action_id}?include_messages=true`
- To **delete** links with `use_default_actions: true`: create a delete action with POST (see np-developer-actions `service-links.md`). This executes deprovisioning.
- Deletion via action is asynchronous — the link goes through `deleting` status before disappearing

---

## @endpoint /application/{app_id}/service/{service_id}/link/{link_id}

Gets a service link (service → application connection). Alternative endpoint nested under application/service.

### Parameters
- `app_id` (path): Application ID
- `service_id` (path): Service UUID
- `link_id` (path): Link ID

### Response
- `id`: Link ID
- `service_id`: Service UUID
- `application_id`: Application ID
- `status`: Link status
- `parameters`: Variables exported to the app

### Navigation
- **→ link actions**: `/application/{app_id}/service/{service_id}/link/{link_id}/action`

### Notes
- Actual linking errors are in the `/action` endpoint

---

## @endpoint /application/{app_id}/service/{service_id}/link/{link_id}/action

Gets service link actions.

### Example
```bash
np-api fetch-api "/application/123/service/abc-uuid/link/789/action"
```

### Notes
- This is where the actual link provisioning errors are

---

## @endpoint /link_specification

Lists available link specifications. Each link specification defines the template for creating a link of a specific service type.

### Parameters
- `nrn` (query, required): URL-encoded NRN (at account level)

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "Link SQS Queue",
      "slug": "link-sqs-queue",
      "specification_id": "uuid-of-service-specification",
      "use_default_actions": false,
      "attributes": {"schema": {}, "values": {}},
      "selectors": {}
    }
  ]
}
```

### Relationship with service_specification

The link_specification's `specification_id` field points to the corresponding `service_specification`.
This allows matching: given a service with `specification_id = X`, search for the link_specification whose `specification_id` is also `X`.

### Known link specifications

| Name | ID | Service Spec ID | use_default_actions | status in POST |
| --- | --- | --- | --- | --- |
| Link SQS Queue | `99396bf5-2200-415d-b79a-d04f9a5dddad` | `529d8786-...` (SQS Queue) | false | `"active"` |
| Link PostgreSQL | `581ef5b7-6993-47d7-b78b-36be0386cdf2` | `670da122-...` | false | `"active"` |
| database-user | `96472045-b509-46c4-96fa-51fc654d6737` | `11063f69-...` (Postgres) | **true** | don't send |
| Link Redis | `66919464-05e6-4d78-bb8c-902c57881ddd` | `4a4f6955-...` | false | `"active"` |
| Link DynamoDB | `6b14b24d-ba3c-4fca-951c-472b318e278e` | `64df74c2-...` | false | `"active"` |
| Link Pubsub Queue | `43c560d2-0aa9-4f6e-a0be-e3192b0fba90` | `b836752e-...` | false | `"active"` |
| Link SQS Agent | `fa9f75e3-d1b9-40f0-a029-ebf78769632d` | `271c090e-...` | false | `"active"` |
| MySQL | `32e7a096-9343-44d0-ac75-69891096365a` | `e541df6a-...` | false | `"active"` |
| Serverless Valkey Link | `7ccfd202-9e85-49c4-a015-3acce157772a` | `5184c8ca-...` | false | `"active"` |
| Read Access | `8dab5557-f933-43e3-827c-607ef3cf935f` | `8e778953-...` | **true** | don't send |
| Link cache | `968976be-bfcb-4bba-9d23-2c7fa31698c5` | `8e778953-...` | **true** | don't send |

### Example
```bash
np-api fetch-api "/link_specification?nrn=organization%3D1255165411%3Aaccount%3D95118862"
```

### Notes
- IDs may vary between organizations. Always query this endpoint to get the correct ID.
- **`use_default_actions: true`**: when creating the link specification, action specifications are generated (CREATE, UPDATE, DELETE). Query with `/link_specification/{id}/action_specification`. The client creates the action with `POST /link/{id}/action`, an agent processes it and provisions resources (e.g., create DB user, generate password), transitioning the link to `active`.
- **`use_default_actions: false`**: no action specifications exist. No agent processes the link. Must be created with `"status": "active"` to be active immediately. Without this field, the link stays in `pending` forever.
- The `use_default_actions` field is **critical** for determining how to create a link. See `POST /link` documentation in np-developer-actions.

---

## @endpoint /link_specification/{id}/action_specification

Lists action specifications of a link specification. Only exist for link specifications with `use_default_actions: true`.

### Parameters
- `id` (path, required): Link specification UUID

### Response
```json
{
  "results": [
    {
      "id": "uuid",
      "name": "create database-user",
      "slug": "create-database-user",
      "type": "create | update | delete",
      "link_specification_id": "uuid",
      "parameters": {"schema": {...}, "values": {}},
      "results": {"schema": {...}, "values": {}}
    }
  ]
}
```

### Key fields
- `type`: `create` (for provisioning on link), `update` (for modifying), `delete` (for deleting)
- `parameters.schema`: JSON Schema of input parameters (e.g., read/write/admin permissions)
- `results.schema`: JSON Schema of results (e.g., generated username, password)
- `parameters.schema.properties[].target`: which link `attribute` the result maps to

### Example
```bash
np-api fetch-api "/link_specification/96472045-b509-46c4-96fa-51fc654d6737/action_specification"
```

### Notes
- Only link specifications with `use_default_actions: true` have action specifications
- The `create` type is needed for the second request when creating a link (`POST /link/{id}/action`)
- Structure identical to `/service_specification/{id}/action_specification`

---

## Services of type=scope

Each scope with UUID provider has an associated service of `type=scope`. This service:
- Contains the **scope's capabilities** in the `attributes` field
- Its `specification_id` is the scope's **provider**
- Its `entity_nrn` contains the scope's complete NRN

### Scope ↔ Service Relationship

```
Scope (UUID provider)
  └── instance_id → Service (type=scope)
                      ├── specification_id = provider UUID
                      ├── attributes = scope capabilities
                      └── entity_nrn = scope NRN
```

### Usage: List scopes by provider

```bash
# List all type=scope services of the org
np-api fetch-api "/service?nrn=organization%3D{org_id}:account%3D*&type=scope&limit=1500"

# Filter by provider (specification_id)
| jq '[.results[] | select(.specification_id == "provider-UUID")]'
```

### Usage: Compare capabilities between scopes

```bash
# Find scopes that don't have a certain capability
jq '[.results[] |
  select(.specification_id == "UUID") |
  select((.attributes | has("traffic_management")) | not) |
  {name, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### Notes
- Only scopes with UUID provider have an associated service
- Scopes with legacy provider (`AWS:SERVERLESS:LAMBDA`, etc.) do NOT have a type=scope service
- The service's `attributes` field is equivalent to the scope's `capabilities`
