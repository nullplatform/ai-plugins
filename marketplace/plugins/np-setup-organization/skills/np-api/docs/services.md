# Services

Services son infraestructura provisionada. Hay dos tipos:
- **dependency**: databases, caches, load balancers, etc.
- **scope**: representación interna de un scope (solo para providers UUID)

## @endpoint /service/{id}

Obtiene detalles de un service.

### Parámetros
- `id` (path, required): UUID del service

### Respuesta
- `id`: UUID
- `name`: Nombre del service
- `slug`: Identificador URL-friendly
- `status`: active | failed | pending | updating | deleting | creating
- `type`: dependency | scope
- `specification_id`: UUID del service specification (template). Para type=scope, este es el **provider** del scope
- `desired_specification_id`: Si hay update pendiente
- `entity_nrn`: NRN del contexto organizacional
- `linkable_to[]`: NRNs de aplicaciones que pueden linkear este service
- `attributes`: Configuración específica del service
  - Database: host, port, username, database
  - AWS: vpc_id, subnet_ids, access_key_id, secret_access_key
- `selectors`:
  - `category`: database | cache | messaging | any
  - `provider`: aws | gcp | azure | any
  - `sub_category`: más específico
  - `imported`: boolean - si es recurso importado existente
- `messages[]`: Eventos (puede estar vacío - ver service actions)

### Navegación
- **→ specification**: `specification_id` → `/service_specification/{specification_id}`
- **→ actions**: `/service/{id}/action`
- **→ linked apps**: parsear `linkable_to[]` NRNs

### Ejemplo
```bash
np-api fetch-api "/service/ef3baa4e-6144-457e-8812-280976eab7f3"
```

### Notas
- `status: failed` requiere intervención manual
- `messages[]` puede estar vacío incluso para failed - revisar `/service/{id}/action`
- `attributes` puede contener credenciales sensibles
- Services importados (`imported: true`) no ejecutan provisioning

---

## @endpoint /service

Lista services por NRN.

### Parámetros
- `nrn` (query, required): NRN con URL encoding
- `type` (query): Filtrar por tipo: `dependency` | `scope`
- `limit` (query): Máximo de resultados (default 30)

### NRN con Wildcards
- `organization=123` → Solo services a nivel org
- `organization=123:account=456` → Services de ese account
- `organization=123:account=*` → **TODOS** los services de la org (wildcard)

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 1500},
  "results": [...]
}
```

### Ejemplo
```bash
# Todos los services de una organización
np-api fetch-api "/service?nrn=organization%3D1255165411:account%3D*&limit=1500"

# Services de un account específico
np-api fetch-api "/service?nrn=organization%3D1255165411:account%3D95118862"
```

### GOTCHA: No usar application_id como query param
- `GET /service?application_id=X` **NO funciona** — devuelve HTTP 403 ("Insufficient permissions") pero el error real es que ese filtro no esta soportado.
- Para listar services de una aplicacion, usar siempre el filtro por NRN:
```bash
np-api fetch-api "/service?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>"
```

### GOTCHA: Servicios visibles vs servicios propios (owned by app)

El endpoint `/service?nrn=<app_nrn>` devuelve **todos los servicios visibles** para esa aplicacion, incluyendo servicios heredados de niveles superiores (namespace, account, organización). Esto es lo mismo que el frontend muestra en la pestaña "Available".

Para obtener solo los servicios **propiedad de una aplicación** (pestaña "Owned by App" en la UI), hay que filtrar client-side por `entity_nrn`:

```bash
# 1. Obtener todos los servicios visibles
np-api fetch-api "/service?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>&type=dependency&limit=300"

# 2. Filtrar los que tengan entity_nrn == NRN de la aplicación
# Solo los servicios cuyo entity_nrn termine en "application=<app_id>" son propiedad de esa app
```

**No existe** un query param `entity_nrn` en la API. El filtrado es siempre client-side.

---

## @endpoint /service/{id}/action

Lista acciones ejecutadas en un service (GET) o crea una nueva action (POST via np-developer-actions).

### Parámetros (GET)
- `id` (path, required): UUID del service
- `limit` (query): Máximo de resultados

### Respuesta (GET)
```json
{
  "results": [
    {
      "id": "uuid",
      "name": "start-blue-green | switch-traffic | finalize-blue-green | create-xxx | update-xxx | delete-xxx",
      "status": "pending | in_progress | success | failed",
      "specification_id": "uuid-de-la-action-specification",
      "parameters": {"deployment_id": "123", "scope_id": "456"},
      "results": {},
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### POST (crear action) - via np-developer-actions

Para crear una action en un service (ej: trigger provisioning):

```json
POST /service/{id}/action
{
  "name": "create-<slug-del-servicio>",
  "specification_id": "<action_specification_id>",
  "parameters": { ... }
}
```

- `name`: Convencion: `<action_type>-<service_slug>` (ej: "create-my-queue")
- `specification_id`: ID de la action specification (obtenido de `/service_specification/{spec_id}/action_specification`)
- `parameters`: Valores segun el `parameters.schema` de la action specification

**NOTA**: Para ejecutar este POST, usar `/np-developer-actions exec-api`. Ver `docs/services.md` en np-developer-actions.

### Navegación
- **→ action details**: `/service/{id}/action/{action_id}?include_messages=true`
- **← deployment**: filtrar por `parameters.deployment_id`

### Ejemplo
```bash
# Listar todas las acciones de un service
np-api fetch-api "/service/ef3baa4e-6144-457e-8812-280976eab7f3/action?limit=200"
```

### Notas
- **Este es el endpoint para obtener deployment actions** - NO existe `/deployment/{id}/action`
- Para acciones de un deployment específico: filtrar por `parameters.deployment_id`
- Tipos de deployment actions: start-blue-green, switch-traffic, finalize-blue-green
- Tipos de service provisioning actions: create, update, delete, custom
- La creacion de un service requiere **dos requests**: primero `POST /service`, luego `POST /service/{id}/action` con la CREATE action spec. Sin el segundo request, el service queda en `pending` indefinidamente

---

## @endpoint /service/{id}/action/{action_id}

Obtiene detalles de una acción específica.

### Parámetros
- `id` (path, required): UUID del service
- `action_id` (path, required): UUID de la acción
- `include_messages` (query, **recomendado**): Incluye logs de ejecución

### Respuesta (con include_messages=true)
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

### Ejemplo
```bash
np-api fetch-api "/service/ef3baa4e/action/a031f992?include_messages=true"
```

### Notas
- Sin `include_messages=true`, el array messages viene vacío
- Action messages muestran detalles de workflow no visibles en deployment messages
- Revela: pasos internos, comandos ejecutados, errores específicos
- **IMPORTANTE**: El campo `specification_id` de una service action es un **action specification interno**, NO un service_specification. No confundir con `service.specification_id` que sí apunta a `/service_specification/{id}`

---

## @endpoint /service_specification

Lista las service specifications disponibles. Cada service specification define un tipo de servicio que se puede provisionar (ej: SQS Queue, Postgres DB, Redis).

### Parametros
- `nrn` (query, required): NRN con URL encoding. Usar NRN a nivel de aplicacion para obtener las specs disponibles en ese contexto.
- `type` (query): Filtrar por tipo: `dependency` (infraestructura) | `scope` (scopes)
- `limit` (query): Maximo de resultados (default 30)

### Respuesta
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

### Ejemplo
```bash
# Service specifications de tipo dependency para una aplicacion
np-api fetch-api "/service_specification?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>&type=dependency&limit=100"

# Service specifications de tipo scope para un account
np-api fetch-api "/service_specification?nrn=organization%3D<org>%3Aaccount%3D<acc>&type=scope"
```

### Notas
- `type=dependency`: bases de datos, colas, caches, etc. (usado por "+ New service" en la UI)
- `type=scope`: tipos de scope/ambiente (usado por la creacion de scopes)
- Los `selectors` (category, sub_category, provider) permiten clasificar y filtrar los tipos

---

## @endpoint /service_specification/{id}

Obtiene el template/blueprint de un service.

### Parametros
- `id` (path, required): UUID del specification
- `application_id` (query, optional): ID de la aplicacion (el frontend lo envia para contexto)

### Respuesta
- `id`: UUID
- `name`: Nombre del specification (ej: "SQS Queue", "Postgres DB")
- `slug`: Identificador URL-friendly
- `type`: `dependency` | `scope`
- `selectors`: `{category, sub_category, provider, imported}`
- `attributes`: `{schema, values}` — schema de los atributos del service (salida del provisioning)
- `dimensions`: restricciones de dimensions
- `scopes`: restricciones de scopes
- `visible_to[]`: NRNs de organizaciones/accounts que pueden ver esta spec
- `assignable_to`: `"any"` o restricciones
- `use_default_actions`: boolean — si genera action specs automaticamente (CREATE, UPDATE, DELETE)
- `created_at`, `updated_at`: timestamps

### Ejemplo
```bash
np-api fetch-api "/service_specification/529d8786-4af4-4625-87de-664ad7c9ef5f?application_id=2052735708"
```

### Notas
- `attributes.schema` define los **atributos de salida** del service (ej: queue_arn, host, port). No confundir con los parametros de entrada para crear el service.
- Los **parametros de entrada** para crear un service se obtienen de la CREATE action specification via `/service_specification/{id}/action_specification`
- `use_default_actions: true` indica que al crear esta spec se auto-generaron action specs (CREATE, UPDATE, DELETE)
- **Campo `export` en attributes.schema.properties**: determina que atributos se inyectan como parametros al linkear el servicio:
  - `"export": true` → se exporta como parametro plaintext
  - `"export": {"type": "environment_variable", "secret": true}` → se exporta como parametro secreto
  - `"export": false` o ausente → NO se exporta
  - Ejemplo SQS: `queue_arn` (export:true) se exporta, `visibility_timeout` (sin export) no

---

## @endpoint /service_specification/{id}/link_specification

Lista las link specifications asociadas a un service specification.

### Parametros
- `id` (path, required): UUID del service specification

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "Link SQS Queue",
      "slug": "link-sqs-queue",
      "specification_id": "uuid-del-service-specification",
      "use_default_actions": false,
      "attributes": {"schema": {}, "values": {}},
      "selectors": {}
    }
  ]
}
```

### Ejemplo
```bash
np-api fetch-api "/service_specification/529d8786-4af4-4625-87de-664ad7c9ef5f/link_specification"
```

### Notas
- Util para saber que link specifications estan asociadas a un tipo de servicio
- El frontend lo consulta al crear un servicio para mostrar opciones de linking

---

## @endpoint /service_specification/{id}/action_specification

Lista las action specifications de un service specification (templates de acciones disponibles).

### Parámetros
- `id` (path, required): UUID del service specification

### Respuesta
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

### Navegación
- **← service_specification**: `/service_specification/{id}`
- **→ action instances**: `/service/{service_id}/action` (instancias de estas specs)

### Ejemplo
```bash
np-api fetch-api "/service_specification/f7248a07-909f-4241-b2c7-616d2403bf54/action_specification"
```

### Notas
- `use_default_actions: true` genera automáticamente specs de tipo create, update, delete
- Custom actions se agregan vía `available_actions` en el service-spec.json.tpl
- `parameters` y `results` usan estructura `{"schema": {...}, "values": {}}`, NO JSON Schema directo
- `type: custom` = no afecta el status del service parent (a diferencia de create/update/delete)
- `link_specification_id: null` = action a nivel service; con valor = action a nivel link

---

## @endpoint /link

Lista links (conexiones service → application) filtrados por NRN.

### Parámetros
- `nrn` (query, required): NRN de la aplicacion con URL encoding. Usar NRN **a nivel de aplicacion** para obtener solo los links de esa app.

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "lnk fees",
      "slug": "lnk-fees",
      "status": "active | pending | creating | failed",
      "service_id": "uuid-del-service-linkeado",
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

### Navegación
- **→ link detail**: `/link/{id}`
- **→ link actions**: `/link/{id}/action`
- **→ service linkeado**: `service_id` → `/service/{service_id}`

### Ejemplo
```bash
# Links de una aplicacion especifica
np-api fetch-api "/link?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>"
```

### Notas
- Sin filtro de NRN a nivel de aplicacion, devuelve links de toda la plataforma (miles)
- El campo `service_id` permite correlacionar con `/service/{id}` para saber que servicio esta linkeado
- El campo `attributes` contiene los parametros exportados (credenciales, URLs, etc.)
- Los parametros de tipo `linked_service` en `/parameter` son generados automaticamente por los links

---

## @endpoint /link/{id}

Obtiene detalle de un link especifico.

### Parámetros
- `id` (path, required): UUID del link

### Respuesta
- `id`: UUID del link
- `name`: Nombre del link
- `slug`: Identificador URL-friendly
- `status`: active | pending | creating | failed
- `service_id`: UUID del service linkeado
- `entity_nrn`: NRN de la aplicacion
- `dimensions`: Dimensions del link
- `specification_id`: UUID de la link specification
- `attributes`: Parametros exportados (credenciales, URLs, etc.)
- `selectors`: Categoria, provider, sub_category, imported
- `messages[]`: Eventos del link

### Navegación
- **→ link actions**: `/link/{id}/action`
- **→ service**: `service_id` → `/service/{service_id}`

### Ejemplo
```bash
np-api fetch-api "/link/9ba2dfe6-b5db-484a-9804-01718199575a"
```

### Notas
- Si `status: failed`, revisar `/link/{id}/action` para diagnosticar
- `attributes` puede contener credenciales sensibles

---

## @endpoint /link/{id}/action

Lista acciones ejecutadas en un link (create, update, delete).

### Parámetros
- `id` (path, required): UUID del link

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "create-lnk-xxx",
      "slug": "create-lnk-xxx",
      "status": "success | failed | pending | in_progress",
      "link_id": "uuid-del-link",
      "parameters": {"permisions": {"read": true, "write": true, "admin": false}},
      "results": {"username": "usr...", "password": null, "permisions": {...}},
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Navegación
- **← link**: `/link/{id}`

### Ejemplo
```bash
np-api fetch-api "/link/9ba2dfe6-b5db-484a-9804-01718199575a/action"
```

### POST (crear action) - via np-developer-actions

Para crear una action en un link (ej: provisioning al crear, deprovisioning al eliminar):

```json
POST /link/{id}/action
{
  "name": "delete-<slug-del-link>",
  "specification_id": "<delete_action_specification_id>",
  "parameters": { ... }
}
```

- `name`: Convencion: `<action_type>-<link_slug>` (ej: "delete-lnk-prices-prod")
- `specification_id`: ID de la action specification del tipo delete (obtenido de `/link_specification/{spec_id}/action_specification`)
- `parameters`: Valores segun el `parameters.schema` de la delete action specification

**NOTA**: Este es el metodo que usa la UI para eliminar links con `use_default_actions: true`.
Crea una delete action que un agent procesa para deprovisionar recursos (eliminar usuario DB, etc.).

### Notas
- Aqui estan los errores reales de provisioning del link
- El campo `parameters` muestra lo que se envio, `results` muestra lo que se genero (ej: credenciales)
- Para mensajes detallados de una action fallida: `/link/{id}/action/{action_id}?include_messages=true`
- Para **eliminar** links con `use_default_actions: true`: crear una delete action con POST (ver np-developer-actions `service-links.md`). Esto ejecuta deprovisioning.
- La eliminacion via action es asincrona — el link pasa por status `deleting` antes de desaparecer

---

## @endpoint /application/{app_id}/service/{service_id}/link/{link_id}

Obtiene un service link (conexión service → application). Endpoint alternativo anidado bajo application/service.

### Parámetros
- `app_id` (path): ID de la aplicación
- `service_id` (path): UUID del service
- `link_id` (path): ID del link

### Respuesta
- `id`: ID del link
- `service_id`: UUID del service
- `application_id`: ID de la aplicación
- `status`: Estado del link
- `parameters`: Variables exportadas a la app

### Navegación
- **→ link actions**: `/application/{app_id}/service/{service_id}/link/{link_id}/action`

### Notas
- Errores reales de linking están en el endpoint `/action`

---

## @endpoint /application/{app_id}/service/{service_id}/link/{link_id}/action

Obtiene acciones del service link.

### Ejemplo
```bash
np-api fetch-api "/application/123/service/abc-uuid/link/789/action"
```

### Notas
- Aquí están los errores reales de provisioning del link

---

## @endpoint /link_specification

Lista las link specifications disponibles. Cada link specification define el template para crear un link de un tipo especifico de servicio.

### Parametros
- `nrn` (query, required): NRN con URL encoding (a nivel de account)

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "name": "Link SQS Queue",
      "slug": "link-sqs-queue",
      "specification_id": "uuid-del-service-specification",
      "use_default_actions": false,
      "attributes": {"schema": {}, "values": {}},
      "selectors": {}
    }
  ]
}
```

### Relacion con service_specification

El campo `specification_id` de la link_specification apunta al `service_specification` correspondiente.
Esto permite matchear: dado un servicio con `specification_id = X`, buscar la link_specification cuyo `specification_id` tambien sea `X`.

### Link specifications conocidas

| Nombre | ID | Service Spec ID | use_default_actions | status en POST |
| --- | --- | --- | --- | --- |
| Link SQS Queue | `99396bf5-2200-415d-b79a-d04f9a5dddad` | `529d8786-...` (SQS Queue) | false | `"active"` |
| Link PostgreSQL | `581ef5b7-6993-47d7-b78b-36be0386cdf2` | `670da122-...` | false | `"active"` |
| database-user | `96472045-b509-46c4-96fa-51fc654d6737` | `11063f69-...` (Postgres) | **true** | no enviar |
| Link Redis | `66919464-05e6-4d78-bb8c-902c57881ddd` | `4a4f6955-...` | false | `"active"` |
| Link DynamoDB | `6b14b24d-ba3c-4fca-951c-472b318e278e` | `64df74c2-...` | false | `"active"` |
| Link Pubsub Queue | `43c560d2-0aa9-4f6e-a0be-e3192b0fba90` | `b836752e-...` | false | `"active"` |
| Link SQS Agent | `fa9f75e3-d1b9-40f0-a029-ebf78769632d` | `271c090e-...` | false | `"active"` |
| MySQL | `32e7a096-9343-44d0-ac75-69891096365a` | `e541df6a-...` | false | `"active"` |
| Serverless Valkey Link | `7ccfd202-9e85-49c4-a015-3acce157772a` | `5184c8ca-...` | false | `"active"` |
| Read Access | `8dab5557-f933-43e3-827c-607ef3cf935f` | `8e778953-...` | **true** | no enviar |
| Link cache | `968976be-bfcb-4bba-9d23-2c7fa31698c5` | `8e778953-...` | **true** | no enviar |

### Ejemplo
```bash
np-api fetch-api "/link_specification?nrn=organization%3D1255165411%3Aaccount%3D95118862"
```

### Notas
- Los IDs pueden variar entre organizaciones. Siempre consultar este endpoint para obtener el ID correcto.
- **`use_default_actions: true`**: al crear la link specification se generan action specifications (CREATE, UPDATE, DELETE). Consultar con `/link_specification/{id}/action_specification`. El cliente crea la action con `POST /link/{id}/action`, un agent la procesa y provisiona recursos (ej: crear usuario DB, generar password), transicionando el link a `active`.
- **`use_default_actions: false`**: no existen action specifications. No hay agent que procese el link. Se debe crear con `"status": "active"` para que quede activo de inmediato. Sin este campo, el link queda en `pending` para siempre.
- El campo `use_default_actions` es **critico** para determinar como crear un link. Ver documentacion de `POST /link` en np-developer-actions.

---

## @endpoint /link_specification/{id}/action_specification

Lista las action specifications de una link specification. Solo existen para link specifications con `use_default_actions: true`.

### Parametros
- `id` (path, required): UUID de la link specification

### Respuesta
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

### Campos clave
- `type`: `create` (para provisionar al linkear), `update` (para modificar), `delete` (para eliminar)
- `parameters.schema`: JSON Schema de los parametros de entrada (ej: permisos read/write/admin)
- `results.schema`: JSON Schema de los resultados (ej: username, password generados)
- `parameters.schema.properties[].target`: a que `attribute` del link se mapea el resultado

### Ejemplo
```bash
np-api fetch-api "/link_specification/96472045-b509-46c4-96fa-51fc654d6737/action_specification"
```

### Notas
- Solo link specifications con `use_default_actions: true` tienen action specifications
- La de tipo `create` se necesita para el segundo request al crear un link (`POST /link/{id}/action`)
- Estructura identica a `/service_specification/{id}/action_specification`

---

## Services de type=scope

Cada scope con provider UUID tiene un service asociado de `type=scope`. Este service:
- Contiene las **capabilities del scope** en el campo `attributes`
- Su `specification_id` es el **provider** del scope
- Su `entity_nrn` contiene el NRN completo del scope

### Relación Scope ↔ Service

```
Scope (provider UUID)
  └── instance_id → Service (type=scope)
                      ├── specification_id = provider UUID
                      ├── attributes = capabilities del scope
                      └── entity_nrn = NRN del scope
```

### Uso: Listar scopes por provider

```bash
# Listar todos los services type=scope de la org
np-api fetch-api "/service?nrn=organization%3D{org_id}:account%3D*&type=scope&limit=1500"

# Filtrar por provider (specification_id)
| jq '[.results[] | select(.specification_id == "UUID-del-provider")]'
```

### Uso: Comparar capabilities entre scopes

```bash
# Encontrar scopes que no tienen cierta capability
jq '[.results[] |
  select(.specification_id == "UUID") |
  select((.attributes | has("traffic_management")) | not) |
  {name, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### Notas
- Solo scopes con provider UUID tienen service asociado
- Scopes con provider legacy (`AWS:SERVERLESS:LAMBDA`, etc.) NO tienen service type=scope
- El campo `attributes` del service es equivalente a `capabilities` del scope
