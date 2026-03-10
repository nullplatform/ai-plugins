# Services (Provisioning)

Acciones de escritura para provisionar nuevos servicios de infraestructura (databases, colas, caches, etc.).

## @action POST /service

Crea un nuevo servicio de infraestructura en una aplicacion.

### Flujo obligatorio de creacion

**IMPORTANTE**: Crear un servicio requiere un proceso de discovery previo para identificar
los tipos de servicio disponibles y sus schemas de configuracion. NO asumir service specification IDs ni schemas.

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery, pasos 1-4)
> y `/np-developer-actions exec-api` para ESCRITURA (paso 7). NUNCA usar `curl` ni
> `/np-api` para operaciones POST/PUT/DELETE.

#### Paso 1: Obtener datos de la aplicacion

```bash
np-api fetch-api "/application/<app_id>"
```

Del NRN extraer `organization_id`, `account_id`, `namespace_id`.
El NRN completo de la aplicacion se usara como `entity_nrn` del service.

#### Paso 2: Listar service specifications disponibles

Los tipos de servicio NO son fijos. Cada organizacion/account puede tener diferentes tipos.
Se descubren consultando service_specifications filtradas por NRN a nivel de aplicacion y `type=dependency`.

```bash
np-api fetch-api "/service_specification?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>&type=dependency&limit=100"
```

**NOTA**: El filtro `type=dependency` excluye specifications de tipo `scope` (que son para crear scopes, no servicios de infraestructura). El NRN a nivel de aplicacion es el que usa el frontend.

Mostrar al usuario la lista de service specifications disponibles con:

| # | Nombre | Categoria | Sub-categoria | Provider |
|---|--------|-----------|---------------|----------|

Donde:
- **Nombre**: `name` del service specification (ej: "SQS Queue", "Postgres DB", "Redis")
- **Categoria**: `selectors.category` (ej: "Database", "Messaging Services")
- **Sub-categoria**: `selectors.sub_category` (ej: "Relational Database", "Message Queue", "In-memory Cache")
- **Provider**: `selectors.provider` (ej: "AWS", "GCP", "K8S")

Si el usuario pidio algo especifico (ej: "crear una base de datos"), filtrar la lista por nombre o categoria.

#### Paso 3: Preguntar al usuario que tipo de servicio quiere crear

Usando `AskUserQuestion`, mostrar los service specifications priorizados (max 4 opciones por pregunta).
Si hay mas de 4, agrupar por categoria o mostrar los mas relevantes primero.

#### Paso 4: Obtener schema de configuracion y dimensions

Ejecutar tres consultas en paralelo:

```bash
# Detalle del service specification (attributes schema, dimensions, etc.)
np-api fetch-api "/service_specification/<spec_id>?application_id=<app_id>"

# Action specifications (para obtener el schema de la CREATE action → campos del formulario)
np-api fetch-api "/service_specification/<spec_id>/action_specification"

# Dimensions disponibles
np-api fetch-api "/dimension?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>"
```

**De las action specifications**, filtrar la de `type: "create"`. Su campo `parameters.schema` define
los **parametros de entrada** para la creacion del servicio. Estos son los campos que el usuario
debe completar (equivale al formulario de la UI).

Ejemplo para SQS Queue, la action spec `Create SQS Queue` tiene:

```json
{
  "parameters": {
    "schema": {
      "type": "object",
      "properties": {
        "fifo": {"type": "boolean", "default": false},
        "dead_letter": {"type": "boolean", "default": false}
      }
    }
  }
}
```

Los `results.schema` de la action spec definen lo que el agent devuelve despues del provisioning
(ej: `queue_arn`, `dead_letter_arn`). Estos se mapean a los `attributes` del service via el campo `target`.

**Del service specification**, obtener:
- `attributes.schema`: schema de los atributos del service (salida, no entrada)
- `dimensions`: restricciones de dimensions del service
- `use_default_actions`: si tiene action specs auto-generadas

#### Paso 5: Preguntar nombre, dimensions y configuracion

Usando `AskUserQuestion`:

1. **Nombre del servicio**: pedir un nombre descriptivo
2. **Dimensions**: proponer dimensions basadas en las disponibles (ej: environment=production)
3. **Parametros de configuracion**: presentar los campos de `parameters.schema` de la CREATE action spec con sus defaults

#### Paso 6: Confirmar con el usuario

Mostrar los bodies completos que se van a enviar (son DOS requests):
- **QUE**: `POST /service` + `POST /service/{id}/action`
- **POR QUE**: "Para crear un servicio de tipo X en la aplicacion Y con dimensions Z"

Pedir confirmacion explicita.

#### Paso 7: Ejecutar (dos requests secuenciales)

La creacion de un servicio requiere **dos requests secuenciales**:

**Request 1: Crear el servicio**

```bash
action-api.sh exec-api --method POST --data '{
  "name": "<nombre_del_servicio>",
  "specification_id": "<service_specification_id>",
  "entity_nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "linkable_to": ["organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>"],
  "dimensions": {},
  "selectors": {"imported": false}
}' "/service"
```

Campos del body:
- `name` (string, required): Nombre descriptivo del servicio
- `specification_id` (uuid, required): ID del service specification elegido en paso 3
- `entity_nrn` (string, required): NRN de la aplicacion dueña (de paso 1)
- `linkable_to` (array de NRN, required): NRNs desde donde se puede linkear. Por defecto, solo la propia aplicacion
- `dimensions` (object): Dimensions del servicio. `{}` = "Any" (sin restriccion). Ej: `{"environment": "production"}`
- `selectors.imported` (boolean): `false` = servicio owned por la app

**NOTA**: El frontend tambien envia `"entity": "service"` pero no es necesario. No enviar `status` — el backend lo setea automaticamente a `pending`.

**Request 2: Crear la action de provisionamiento**

Del response del request 1, extraer el `id` del servicio creado. Luego:

```bash
action-api.sh exec-api --method POST --data '{
  "name": "create-<slug_del_servicio>",
  "specification_id": "<create_action_spec_id>",
  "parameters": { <campos_del_schema_de_la_create_action_spec> }
}' "/service/<service_id>/action"
```

Campos del body:
- `name` (string, required): `"create-<slug>"` donde slug es el nombre del servicio en kebab-case
- `specification_id` (uuid, required): ID de la action specification de tipo `create` (obtenido en paso 4)
- `parameters` (object, required): Valores de los campos de `parameters.schema` de la CREATE action spec

Ejemplo completo para SQS Queue:

```bash
# Request 1: Crear servicio
action-api.sh exec-api --method POST --data '{
  "name": "my-events-queue",
  "specification_id": "529d8786-4af4-4625-87de-664ad7c9ef5f",
  "entity_nrn": "organization=1255165411:account=95118862:namespace=463208973:application=2052735708",
  "linkable_to": ["organization=1255165411:account=95118862:namespace=463208973:application=2052735708"],
  "dimensions": {},
  "selectors": {"imported": false}
}' "/service"

# Request 2: Crear action (usando el service_id del response anterior)
action-api.sh exec-api --method POST --data '{
  "name": "create-my-events-queue",
  "specification_id": "284c262a-dcf4-4af8-9dca-7c310c57d42b",
  "parameters": {"fifo": false, "dead_letter": true}
}' "/service/<service_id>/action"
```

**IMPORTANTE**: Sin el request 2, el servicio queda en `pending` indefinidamente.
El agent externo monitorea las actions en status `pending`/`in_progress` y las procesa.

#### Paso 8: Verificar resultado post-creacion

```bash
# Verificar que el servicio se creo correctamente
np-api fetch-api "/service/<service_id>"
```

El servicio pasa por estos estados: `pending` → `creating` → `active`

Si el status no es `active` despues de unos minutos:

```bash
# Revisar las actions del service para diagnosticar
np-api fetch-api "/service/<service_id>/action"
```

Si la action esta en `failed`, revisar el campo `results` para el mensaje de error.

### Service specifications conocidas (referencia)

| Nombre | ID | Categoria | Sub-categoria | Provider |
|--------|----|-----------| --------------|----------|
| SQS Queue | `529d8786-4af4-4625-87de-664ad7c9ef5f` | Messaging Services | Message Queue | AWS |
| SQS Agent | `271c090e-aa8f-417a-9eb8-966239a67328` | Messaging Services | Message Queue | AWS |
| Pubsub | `b836752e-51e2-4176-8093-f3f33aab3e23` | Messaging Services | Message Queue | GCP |
| Postgres DB | `11063f69-fc35-41f6-8d37-7c0d294d7f9e` | Database | Relational Database | K8S |
| PostgreSQL | `670da122-2947-411f-82bc-c7ef62ca08c9` | Database | Relational Database | AWS |
| MySQL | `e541df6a-4676-46e1-81fb-e21c0fa94ad6` | Database | Relational Database | AWS |
| Redis | `4a4f6955-5ae0-40dc-a1de-e15e5cf41abb` | Database | In-memory Cache | AWS |
| Serverless Valkey | `5184c8ca-006b-4334-b7c4-14130b30ce38` | Database | In-memory Cache | AWS |
| DynamoDB | `64df74c2-6967-4cd4-b202-753f61ac1159` | Database | NoSQL Database | AWS |

**IMPORTANTE**: Los IDs pueden variar entre organizaciones. Siempre consultar `/service_specification` para obtener los IDs correctos.

### Notas

- El servicio se crea en status `pending` y pasa a `creating` → `active` cuando el agent lo provisiona
- El `entity_nrn` del servicio determina a que aplicacion pertenece (owned)
- Despues de crear el servicio, normalmente se necesita **linkearlo** a la aplicacion (ver `service-links.md`)
- El campo `"entity": "service"` que envia el frontend en el POST /service NO es requerido por la API
- Los atributos con `"export": true` en el `attributes.schema` del service specification se convierten en parametros al linkear (ver `service-links.md` seccion "Parametros inyectados automaticamente")

---

## @action DELETE /service (via action)

Elimina un servicio existente y destruye sus recursos provisionados.

### Flujo obligatorio de eliminacion

**IMPORTANTE**: `DELETE /service/{id}` directo devuelve 403 (Forbidden). La eliminacion se hace
creando una **delete action** que el agent procesa para destruir los recursos.

> **EXCEPCION**: Servicios en estado `failed` SI se pueden eliminar con `DELETE /service/{id}` directo
> (devuelve 200). No requieren action porque no hay recursos provisionados que destruir.

> **IMPORTANTE**: Antes de eliminar un servicio, verificar que **no tenga links activos**.
> Eliminar primero los links (ver `service-links.md`) y luego el servicio.

#### Shortcut: Servicios en estado `failed`

Si el servicio esta en estado `failed`, se puede eliminar directamente sin crear una delete action:

```bash
action-api.sh exec-api --method DELETE --data '{}' "/service/<service_id>"
```

No requiere obtener action specifications ni crear actions. El DELETE directo retorna 200.
Para servicios en cualquier otro estado (`active`, `creating`, etc.), seguir el flujo completo a continuacion.

#### Paso 1: Obtener el servicio y su delete action specification

```bash
# Detalle del servicio
np-api fetch-api "/service/<service_id>"

# Action specifications (buscar la de type: "delete")
np-api fetch-api "/service_specification/<spec_id>/action_specification"
```

De las action specifications, filtrar la de `type: "delete"` y obtener su `id` y `parameters.schema`.

#### Paso 2: Confirmar con el usuario

Mostrar:
- **QUE**: `POST /service/{id}/action` con body de delete action
- **POR QUE**: "Para eliminar el servicio X y destruir sus recursos"

#### Paso 3: Ejecutar

```bash
action-api.sh exec-api --method POST --data '{
  "name": "delete-<slug-del-servicio>",
  "specification_id": "<delete_action_spec_id>",
  "parameters": { <campos_del_schema_de_la_delete_action_spec> }
}' "/service/<service_id>/action"
```

#### Paso 4: Verificar

```bash
np-api fetch-api "/service/<service_id>"
```

El servicio pasa por: `active` → `deleting` → (eliminado, la API devuelve error o objeto sin datos).

### Notas

- El agent destruye los recursos (infra, pods, etc.) y luego marca el servicio como eliminado
- Los `parameters` del delete action se obtienen del `parameters.schema` de la delete action spec (pueden ser los mismos que los de create)
- Si la delete action falla, revisar con `/service/{id}/action/{action_id}?include_messages=true`

---

## @action PATCH /service_specification/{id}

Modifica una service specification existente. Permite cambiar `visible_to` para controlar qué organizaciones/accounts pueden ver la spec.

### Caso de uso principal: ocultar/mostrar service specifications

Para ocultar una spec (que no aparezca en "New Service" de la UI):

```bash
action-api.sh exec-api --method PATCH --data '{"visible_to": []}' "/service_specification/<spec_id>"
```

Para restaurar la visibilidad:

```bash
action-api.sh exec-api --method PATCH --data '{"visible_to": ["organization=<org_id>:account=<acc_id>"]}' "/service_specification/<spec_id>"
```

### Respuesta

Devuelve el objeto completo de la service specification con los campos actualizados.

### Notas

- **Solo funciona para specs de tu organización**. Specs compartidas con otras organizaciones (ej: `visible_to: ["organization=1255165411", "organization=4"]`) devuelven **403 Forbidden** si intentas modificarlas desde una org que no es la propietaria.
- Requiere permisos elevados en la API key (grants de service_specification:write o similar).
- `PUT /service_specification/{id}` **no existe** (devuelve 404). Solo PATCH.
- Cambiar `visible_to: []` oculta la spec de la UI de "New Service" pero no afecta servicios ya creados con esa spec.

---

## @action PATCH /template/{id}

Modifica un template de aplicación. Permite renombrar templates y cambiar otros campos.

### Ejemplo: renombrar un template

```bash
action-api.sh exec-api --method PATCH --data '{"name": "Kwiki Bank - Frontend Starter Kit"}' "/template/<template_id>"
```

### Respuesta

Devuelve el objeto completo del template con los campos actualizados.

### Notas

- Requiere permisos elevados en la API key.
- `PUT /template/{id}` **no existe** (devuelve 404). Solo PATCH.
- Para encontrar el template_id, usar `np-api fetch-api "/template?limit=200&target_nrn=<nrn_encoded>&global_templates=true"` y buscar por nombre o repository URL.
