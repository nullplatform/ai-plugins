# Links

Operaciones para linkear servicios existentes a una aplicacion.

Un **link** conecta un service (base de datos, cola de mensajes, MCP, etc.) con una aplicacion,
exportando parametros (credenciales, URLs, etc.) como variables de entorno en los scopes que
matcheen las dimensions del link.

## Modelo de priorizacion

Al presentar servicios disponibles al usuario, usar esta priorizacion:

1. **Owned & sin link** → MAXIMA prioridad. Son servicios que la aplicacion creo pero aun no linkeo.
2. **Available (no owned)** → Segunda prioridad. Servicios de otras aplicaciones disponibles para linkear. Priorizar los que matcheen con lo que el usuario pidio (por nombre, categoria, dimensions).
3. **Ya linkeados** → Baja prioridad. Mostrar como referencia pero el usuario probablemente no quiere re-linkearlos.

---

## @action POST /link

Linkea un servicio existente y disponible a una aplicacion.

### Flujo obligatorio de creacion

**IMPORTANTE**: Linkear un servicio requiere un proceso de discovery previo para identificar
servicios disponibles y sus caracteristicas. NO asumir service IDs ni dimensions.

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery, pasos 1-5)
> y `/np-developer-actions exec-api` para ESCRITURA (paso 8). NUNCA usar `curl` ni
> `/np-api` para operaciones POST/PUT/DELETE.

#### Paso 1: Obtener datos de la aplicacion

```bash
np-api fetch-api "/application/<app_id>"
```

Del NRN extraer `organization_id`, `account_id`, `namespace_id`.
El NRN completo de la aplicacion se usara como `entity_nrn` del link.

#### Paso 2: Obtener servicios disponibles (con priorizacion)

Ejecutar dos consultas en paralelo:

```bash
# Todos los servicios disponibles para esta aplicacion (type=dependency)
np-api fetch-api "/service?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>&type=dependency&limit=100"

# Links ya existentes en esta aplicacion
np-api fetch-api "/link?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>"
```

**NOTA CRITICA**: Para obtener la lista completa de servicios disponibles (la que matchea con
la pestaña "Available" de la UI), se debe filtrar con el NRN **a nivel de aplicacion**.
Usar NRN a nivel de account o namespace devuelve menos resultados.

#### Paso 3: Clasificar y priorizar servicios

Con los resultados del paso 2, clasificar cada servicio:

```text
Para cada service en servicios_disponibles:
  - Si service.entity_nrn contiene el app NRN Y su service_id NO esta en links existentes:
    → Categoria: "Owned (sin linkear)" - PRIORIDAD 1
  - Si service.entity_nrn NO contiene el app NRN Y su id NO esta en links existentes:
    → Categoria: "Available" - PRIORIDAD 2
  - Si su id ESTA en links existentes (via service_id del link):
    → Categoria: "Ya linkeado" - solo informativo
```

**NOTA**: La clasificacion owned vs available es informativa para el usuario. Lo que determina el `status` a enviar en el POST es el campo `use_default_actions` de la link specification (ver "Status y activacion del link").

Mostrar al usuario la lista priorizada con:

| # | Nombre | Categoria | Status | Tipo | Dimensions |
|---|--------|-----------|--------|------|------------|

Donde:
- **Categoria**: indica la clasificacion (ej: "Database / Relational", "Messaging / Queue", "MCP Exposer")
- **Tipo**: se extrae de `selectors.category` y `selectors.sub_category` del service
- **Dimensions**: se extrae de `dimensions` del service (ej: environment=production, country=argentina)

Si el usuario pidio algo especifico (ej: "linkear la base de datos"), filtrar la lista por nombre o categoria.

#### Paso 4: Preguntar al usuario que servicio quiere linkear

Usando `AskUserQuestion`, mostrar los servicios priorizados (max 4 opciones por pregunta).
Si hay mas de 4, agrupar por categoria o mostrar los mas relevantes primero.

#### Paso 5: Obtener detalles del servicio y link specification

Ejecutar dos consultas en paralelo:

```bash
# Detalle del servicio elegido
np-api fetch-api "/service/<service_id>"

# Link specifications disponibles (para obtener el specification_id del link)
np-api fetch-api "/link_specification?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>"
```

Del servicio obtener:

- `dimensions`: las dimensions del service (el link deberia matchear con alguna de estas)
- `attributes`: atributos del servicio (host, port, etc.)
- `specification_id`: para matchear con la link specification correcta

De las link specifications, elegir la que corresponda al tipo de servicio (matchear por `specification_id` del servicio con el campo `specification_id` de la link_specification).

**Si la link specification tiene `use_default_actions: true`**, obtener tambien las action specifications:

```bash
np-api fetch-api "/link_specification/<link_spec_id>/action_specification"
```

De las action specifications, filtrar la de `type: "create"`. Su campo `parameters.schema` define los **parametros de entrada** para la action de provisionamiento (equivale al formulario de la UI, ej: permisos read/write/admin para database-user).

#### Paso 6: Obtener dimensions disponibles

```bash
np-api fetch-api "/dimension?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>"
```

Comparar las dimensions del servicio con las dimensions disponibles para proponer valores validos.

#### Paso 7: Preguntar nombre del link, dimensions y parametros

Usando `AskUserQuestion`:

1. **Nombre del link**: sugerir `lnk <slug-del-service>` como convencion
2. **Dimensions**: proponer las dimensions del servicio como default. El usuario puede ajustarlas.
3. **Parametros de la action** (solo si `use_default_actions: true`): presentar los campos de `parameters.schema` de la CREATE action spec con sus defaults (ej: permisos read/write/admin para database-user)

#### Paso 8: Confirmar con el usuario

Mostrar los bodies completos que se van a enviar:

**Para link specs con `use_default_actions: false`** (un solo request):
- **QUE**: `POST /link` con body (incluye `"status": "active"`)
- **POR QUE**: "Para linkear el servicio X a la aplicacion Y, exportando sus parametros como variables de entorno"

**Para link specs con `use_default_actions: true`** (dos requests):
- **QUE**: `POST /link` + `POST /link/{id}/action`
- **POR QUE**: "Para linkear el servicio X a la aplicacion Y y provisionar recursos (ej: usuario DB)"

Pedir confirmacion explicita.

#### Paso 9: Ejecutar

**Link spec con `use_default_actions: false` (un request):**

```bash
action-api.sh exec-api --method POST --data '{
  "name": "lnk <nombre>",
  "service_id": "<service_id>",
  "entity_nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "dimensions": {},
  "specification_id": "<link_specification_id>",
  "status": "active"
}' "/link"
```

**Link spec con `use_default_actions: true` (dos requests secuenciales):**

```bash
# Request 1: Crear el link (sin status — queda en pending)
action-api.sh exec-api --method POST --data '{
  "name": "lnk <nombre>",
  "service_id": "<service_id>",
  "entity_nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "dimensions": {},
  "specification_id": "<link_specification_id>"
}' "/link"

# Request 2: Crear la action de provisionamiento (usando el link_id del response anterior)
action-api.sh exec-api --method POST --data '{
  "name": "create-<slug-del-link>",
  "specification_id": "<create_action_spec_id>",
  "parameters": { <campos_del_schema_de_la_create_action_spec> }
}' "/link/<link_id>/action"
```

Campos del body del request 2:
- `name` (string, required): `"create-<slug>"` donde slug es el nombre del link en kebab-case
- `specification_id` (uuid, required): ID de la action specification de tipo `create` (obtenido en paso 5)
- `parameters` (object, required): Valores de los campos de `parameters.schema` de la CREATE action spec

**IMPORTANTE**: Sin el request 2, el link queda en `pending` indefinidamente.
El agent externo monitorea las actions en status `pending`/`in_progress` y las procesa.

#### Paso 10: Verificar resultado post-creacion

```bash
# Verificar que el link se creo correctamente
np-api fetch-api "/link/<link_id>"
```

Si el status no es `active`:

```bash
# Revisar las actions del link para diagnosticar
np-api fetch-api "/link/<link_id>/action"
```

Si hay una action con status `failed`:

```bash
# Obtener messages de la action fallida
np-api fetch-api "/link/<link_id>/action/<action_id>?include_messages=true"
```

### Campos requeridos (POST /link)

- `name` (string): Nombre del link (convencion: `lnk <slug-del-service>`)
- `service_id` (string UUID): ID del servicio a linkear
- `entity_nrn` (string): NRN de la aplicacion donde se linkea
- `dimensions` (object): Dimensions del link (deben matchear con las del servicio y los scopes target)
- `specification_id` (string UUID): ID de la **link specification** (ver seccion "Obtener link specification")
- `status` (string, condicional): **CRITICO** - ver seccion "Status y activacion del link"

### Obtener link specification

La API requiere una `specification_id` que corresponde a una **link specification**, NO a la service specification.
Para obtenerla:

```bash
np-api fetch-api "/link_specification?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>"
```

Matchear la link specification con el tipo de servicio (comparar `specification_id` del servicio con `specification_id` de la link_specification).

**CRITICO**: Ademas de obtener el ID, verificar `use_default_actions` para determinar si enviar `"status": "active"` (ver "Status y activacion del link").

| Tipo de servicio | Link Specification | `use_default_actions` | `status` en POST |
|-----------------|-------------------|-----------------------|------------------|
| SQS Queue | Link SQS Queue | false | `"active"` |
| PostgreSQL (con provisioning) | database-user | **true** | no enviar |
| PostgreSQL (sin provisioning) | Link PostgreSQL | false | `"active"` |
| Redis | Link Redis | false | `"active"` |
| DynamoDB | Link DynamoDB | false | `"active"` |
| Pubsub Queue | Link Pubsub Queue | false | `"active"` |
| MySQL | MySQL | false | `"active"` |

**IMPORTANTE**: Los IDs pueden variar entre organizaciones. Siempre consultar `/link_specification` para obtener el ID correcto y verificar `use_default_actions`.

### Status y activacion del link

**CRITICO**: El campo `status` en el POST body determina si el link se activa inmediatamente o
queda pendiente de provisioning por un agent externo. La regla depende de `use_default_actions`
de la **link specification** elegida.

#### Regla de activacion

| `use_default_actions` | `status` a enviar | Por que |
|-----------------------|-------------------|---------|
| `false` (SQS, Redis, DynamoDB, Pubsub, etc.) | `"active"` | No existe agent que procese acciones. Sin `status: "active"` el link queda en `pending` **para siempre**. |
| `true` (database-user para Postgres, etc.) | **NO enviar** (default `pending`) | Se necesita un segundo request `POST /link/{id}/action` para crear la action de provisionamiento. Un agent externo ejecuta la action, provisiona recursos (usuario DB, password), y transiciona el link a `active`. |

#### Por que funciona asi

- `use_default_actions: true` → la link specification tiene action specifications (CREATE, UPDATE, DELETE). El cliente crea la action con `POST /link/{id}/action`, un agent la detecta y ejecuta el provisioning.
- `use_default_actions: false` → no existen action specifications. No hay agent. El unico camino a `active` es enviarlo en el POST.

#### Que pasa internamente con `status: "active"`

Cuando el service-api recibe `status: "active"` en el POST body:
1. Setea automaticamente `selectors.imported = true` (no es necesario enviarlo manualmente)
2. Inyecta inmediatamente los parametros como variables de entorno en los scopes
3. **Saltea completamente el provisioning** — no se puede crear una CREATE action despues

**PELIGRO**: Si se envia `status: "active"` en un link con `use_default_actions: true` (ej: PostgreSQL), el link queda activo pero **sin credenciales provisionadas** (sin username, sin password). El link estaria incompleto.

#### Como determinar `use_default_actions`

En el Paso 5, al obtener la link specification, revisar el campo `use_default_actions`:

```
link_specification.use_default_actions === true  → NO enviar status
link_specification.use_default_actions === false → Enviar "status": "active"
```

#### Que pasa con `selectors.imported`

NO es necesario enviar `selectors.imported` manualmente:
- Si se envia `"status": "active"` → el service-api lo setea a `true` automaticamente
- Si NO se envia status (default `pending`) → queda `false`, el agent lo maneja

#### Evidencia empirica (validado en tests)

| Tipo | `status` enviado | Resultado | Provisioning |
|------|-----------------|-----------|--------------|
| SQS (`useDefault: false`) | ninguno | `pending` para siempre | No hay agent |
| SQS (`useDefault: false`) | `"active"` | `active` inmediato | No necesita |
| PostgreSQL (`useDefault: true`) | ninguno | `pending` → agent → `active` con username/password | Agent provisiona |
| PostgreSQL (`useDefault: true`) | `"active"` | `active` pero **sin username/password** | Salteado |

### Body tipico

**Link spec con `use_default_actions: false` (SQS, Redis, DynamoDB, etc.):**

```json
{
  "name": "lnk <nombre>",
  "service_id": "<uuid-del-service>",
  "entity_nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "dimensions": {"environment": "production"},
  "specification_id": "<link-specification-id>",
  "status": "active"
}
```

**Link spec con `use_default_actions: true` (database-user para Postgres, etc.) — DOS requests:**

Request 1 (POST /link):
```json
{
  "name": "lnk <nombre>",
  "service_id": "<uuid-del-service>",
  "entity_nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "dimensions": {"environment": "production"},
  "specification_id": "<link-specification-id>"
}
```

Request 2 (POST /link/{id}/action):
```json
{
  "name": "create-<slug-del-link>",
  "specification_id": "<create_action_spec_id>",
  "parameters": { "permisions": {"read": true, "admin": false, "write": false} }
}
```

Notar: NO enviar `status` en el request 1. El request 2 crea la action que el agent procesara.

### Ejemplo real (SQS — `use_default_actions: false`)

```json
{
  "name": "lnk scoring-feed",
  "service_id": "76c3ebf9-443b-4f5c-b7ee-abc8b6b221bc",
  "entity_nrn": "organization=1255165411:account=95118862:namespace=463208973:application=2052735708",
  "dimensions": {"environment": "production"},
  "specification_id": "99396bf5-2200-415d-b79a-d04f9a5dddad",
  "status": "active"
}
```

### Ejemplo real (Postgres DB — `use_default_actions: true`)

```bash
# Request 1: Crear link
action-api.sh exec-api --method POST --data '{
  "name": "lnk consulting-fees-db",
  "service_id": "3e807a6f-e51d-4248-ab6b-c7b837fa8676",
  "entity_nrn": "organization=1255165411:account=95118862:namespace=463208973:application=2052735708",
  "dimensions": {},
  "specification_id": "96472045-b509-46c4-96fa-51fc654d6737"
}' "/link"

# Request 2: Crear action (usando el link_id del response anterior)
action-api.sh exec-api --method POST --data '{
  "name": "create-lnk-consulting-fees-db",
  "specification_id": "74fa28f2-94d2-4423-a517-84e997ca53cd",
  "parameters": {"permisions": {"read": true, "admin": false, "write": false}}
}' "/link/<link_id>/action"
```

**IMPORTANTE**: Sin el request 2, el link queda en `pending` indefinidamente.

### Consultas previas (via /np-api)

- Aplicacion: `np-api fetch-api "/application/<app_id>"`
- Servicios disponibles: `np-api fetch-api "/service?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>&type=dependency&limit=100"`
- Links existentes: `np-api fetch-api "/link?nrn=organization%3D<org>%3Aaccount%3D<acc>%3Anamespace%3D<ns>%3Aapplication%3D<app>"`
- Detalle de servicio: `np-api fetch-api "/service/<service_id>"`
- Dimensions: `np-api fetch-api "/dimension?nrn=organization%3D<org>%3Aaccount%3D<acc>"`

### Respuesta

- `id`: UUID del link creado
- `name`: Nombre del link
- `slug`: Identificador URL-friendly generado
- `service_id`: UUID del servicio linkeado
- `entity_nrn`: NRN de la aplicacion
- `status`: `pending` → `creating` → `active`
- `dimensions`: Dimensions del link
- `attributes`: Parametros exportados (credenciales, URLs, etc. - generados por la action de create)

### Verificar resultado

```bash
# Verificar estado del link creado
np-api fetch-api "/link/<link_id>"

# Si fallo, revisar actions del link
np-api fetch-api "/link/<link_id>/action"
```

### Parametros inyectados automaticamente

Al crear un link activo, el sistema inyecta automaticamente parametros (variables de entorno) en la aplicacion.

#### Que atributos se exportan

El campo `export` en el `attributes.schema` del **service specification** y del **link specification** determina que atributos se convierten en parametros:

| Valor de `export` | Comportamiento |
|---|---|
| `true` | Se exporta como parametro `plaintext`, `secret: false` |
| `{"type": "environment_variable", "secret": true}` | Se exporta como parametro **secreto** |
| `false` o ausente | NO se exporta |

Ejemplo del service specification de SQS Queue:
- `queue_arn`: `export: true` → se exporta
- `dead_letter_arn`: `export: true` → se exporta (si tiene valor)
- `visibility_timeout`: sin `export` → NO se exporta

Ejemplo del link specification de database-user (Postgres):
- `username`: `export: true` → se exporta como plaintext
- `password`: `export: {"type": "environment_variable", "secret": true}` → se exporta como **secreto**
- `permisions`: `export: false` → NO se exporta

#### Convencion de nombre de parametros

Los parametros se nombran automaticamente con la convencion:

```
<SERVICE_NAME_UPPER_SNAKE>_<ATTRIBUTE_KEY_UPPER>
```

Donde:
- `SERVICE_NAME_UPPER_SNAKE`: nombre del servicio convertido a UPPER_SNAKE_CASE (ej: "test sqs capture" → `TEST_SQS_CAPTURE`)
- `ATTRIBUTE_KEY_UPPER`: clave del atributo en mayusculas (ej: `queue_arn` → `QUEUE_ARN`)

Ejemplos:
| Servicio | Atributo | Parametro generado |
|---|---|---|
| "test sqs capture" | `queue_arn` | `TEST_SQS_CAPTURE_QUEUE_ARN` |
| "consulting-prices" | `hostname` | `CONSULTING_PRICES_DB_HOSTNAME` |
| "consulting-prices" | `password` (del link) | `CONSULTING_PRICES_DB_PASSWORD` |

#### Propiedades de los parametros inyectados

- `read_only: true` — no se pueden modificar manualmente
- `type: environment` — variables de entorno
- `encoding: plaintext` o `secret` segun el `export` del schema
- Los valores reales estan en el array `values[]` del parametro (no en un campo `value` top-level)

#### Dimensions y alcance

- `dimensions: {}` en el link → los parametros se inyectan **sin filtro dimensional** (aplica a todos los scopes)
- `dimensions: {"environment": "production"}` → solo se inyectan en scopes que matcheen esa dimension

### Notas

- Para link specs con `use_default_actions: false`: el link requiere `"status": "active"` en el POST (un solo request), queda activo de inmediato
- Para link specs con `use_default_actions: true`: se necesitan DOS requests (POST /link + POST /link/{id}/action). El link se crea en `pending`, el segundo request crea la action, un agent la procesa, provisiona recursos, y transiciona a `active`
- Las dimensions del link determinan a que scopes se exportan los parametros (variables de entorno)
- Un servicio puede tener multiples links a diferentes aplicaciones
- La convencion de nombre del link es `lnk <slug-del-service>` pero el usuario puede elegir otro nombre
- Si el servicio tiene dimensions (ej: environment=production), el link deberia tener dimensions compatibles
- **No se puede linkear un servicio que no este en la lista de "Available"** (el campo `linkable_to` del service debe matchear el NRN de la aplicacion)
- Despues de linkear, los nuevos parametros requieren un re-deploy para estar disponibles en el runtime

---

## @action DELETE /link/{id}

Elimina un link existente. Existen dos metodos segun el tipo de link.

### Metodo 1: DELETE directo (links sin default actions)

Para links cuya link specification tiene `use_default_actions: false` (ej: SQS, Redis):

1. Verificar el link: `np-api fetch-api "/link/<link_id>"`
2. Confirmar con el usuario
3. Ejecutar: `DELETE /link/{id}`
4. Verificar eliminacion

```bash
action-api.sh exec-api --method DELETE --data '{}' "/link/<link_id>"
```

La eliminacion es inmediata (HTTP 200/204, sin body).

### Metodo 2: Action-based (links con default actions) — RECOMENDADO

Para links cuya link specification tiene `use_default_actions: true` (ej: database-user para Postgres):

> **IMPORTANTE**: Este es el metodo que usa la UI de Nullplatform y es el recomendado porque
> ejecuta el deprovisioning completo (elimina usuario DB, revoca permisos, etc.).
> El `DELETE /link/{id}?force=true` es un atajo que salta el deprovisioning.

#### Paso 1: Obtener la delete action specification

```bash
# Obtener la link specification del link
np-api fetch-api "/link/<link_id>"
# Del response, obtener specification_id

# Obtener action specifications de la link specification
np-api fetch-api "/link_specification/<link_spec_id>/action_specification"
# Filtrar la de type: "delete"
```

#### Paso 2: Confirmar con el usuario

#### Paso 3: Ejecutar

```bash
action-api.sh exec-api --method POST --data '{
  "name": "delete-<slug-del-link>",
  "specification_id": "<delete_action_spec_id>",
  "parameters": { <campos_del_schema> }
}' "/link/<link_id>/action"
```

#### Paso 4: Verificar

```bash
np-api fetch-api "/link/<link_id>"
```

El link pasa por: `active` → `deleting` → (eliminado).

**IMPORTANTE**: La eliminacion via action es **asincrona**. El link no desaparece inmediatamente.
Hay que esperar a que el agent procese la delete action y el link pase a estado eliminado.

### Metodo alternativo: Force DELETE (no recomendado)

Para links con `use_default_actions: true`, se puede forzar el DELETE directo:

```bash
action-api.sh exec-api --method DELETE --data '{}' "/link/<link_id>?force=true"
```

**ATENCION**: Esto elimina el registro del link pero **NO ejecuta deprovisioning**.
Los recursos (usuario DB, permisos) quedan huerfanos. Usar solo como ultimo recurso.

### Notas

- Se pueden eliminar links en cualquier status (active, pending, failed)
- Al eliminar un link, los parametros exportados se eliminan de los scopes afectados
- Requiere un re-deploy para que los cambios se reflejen en runtime
- **Un servicio no puede eliminarse mientras tenga links activos o en proceso de eliminacion**
- La eliminacion de links con default actions es asincrona — verificar que todos los links
  hayan terminado de eliminarse antes de intentar borrar el servicio
