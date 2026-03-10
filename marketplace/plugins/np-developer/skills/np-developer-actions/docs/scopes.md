# Scopes

Acciones de escritura para scopes (ambientes/targets de deployment).

## @action POST /scope

Crea un nuevo scope en una aplicación.

### Flujo obligatorio de creación

**IMPORTANTE**: Crear un scope requiere un proceso de discovery previo. NO asumir valores.
Seguir estos pasos en orden:

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery, pasos 1-5)
> y `/np-developer-actions exec-api` para ESCRITURA (paso 8). NUNCA usar `curl` ni
> `/np-api` para operaciones POST/PUT/DELETE.

#### Paso 1: Obtener datos de la aplicación

```bash
# Obtener detalles de la aplicación (necesitamos el NRN completo)
np-api fetch-api "/application/<app_id>"
```

Del NRN extraer `organization_id`, `account_id`, `namespace_id` y `application_id`.
El NRN completo de la aplicación se usa en los pasos siguientes (URL-encoded).

Formato NRN: `organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>`
URL-encoded: `organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>`

#### Paso 2: Descubrir tipos de scope disponibles (scope_type)

Los tipos de scope NO son fijos. Cada organización/account puede tener diferentes tipos.
Se descubren consultando el endpoint `/scope_type` con el NRN de la aplicación.

```bash
# Listar tipos de scope disponibles
np-api fetch-api "/scope_type?nrn=<app_nrn_encoded>&status=active&include=capabilities,wildcard,available"
```

**Mostrar al usuario TODOS los tipos con `status: active`**, independientemente del campo `available`.
El campo `available` es solo informativo (indica si el provider está pre-configurado), pero **NO
bloquea la creación del scope**. La UI de Nullplatform muestra todos los tipos activos como
opciones seleccionables, incluso los que tienen `available: false`.

Campos clave de cada scope_type:

| Campo | Descripción |
|-------|-------------|
| `id` | ID numérico del tipo |
| `type` | Tipo para el POST: `web_pool`, `web_pool_k8s`, `serverless`, `custom` |
| `name` | Nombre amigable (ej: "Server instances", "Kubernetes", "Serverless", "Scheduled Task") |
| `description` | Descripción del tipo |
| `provider_type` | `null_native` o `service` |
| `provider_id` | ID del provider para el POST (ej: `"web_pool_k8s"` o un UUID) |
| `available` | Boolean — solo informativo, NO bloquea la creación. La UI muestra todos los tipos |
| `parameters.schema` | Schema de capabilities (solo para tipo `custom`) |

Ejemplo de resultado:

| Nombre | Tipo | Provider ID | Available |
|--------|------|-------------|-----------|
| Server instances | web_pool | web_pool | false |
| Kubernetes | web_pool_k8s | web_pool_k8s | true |
| Serverless | serverless | serverless | false |
| Scheduled Task | custom | `<uuid>` | true |

**Preguntar al usuario qué tipo de scope quiere crear, mostrando TODOS los tipos activos.**
El campo `available` no restringe la selección.

#### Paso 3: Obtener capabilities disponibles

Las capabilities definen qué se puede configurar en el scope.

**Para tipos nativos** (`web_pool_k8s`, `serverless`, `web_pool`):

```bash
# Obtener capabilities configurables para scopes
np-api fetch-api "/capability?nrn=<app_nrn_encoded>&target=scope"
```

Retorna una lista de capabilities individuales. Cada una tiene:
- `slug`: Identificador usado como key en el POST (ej: `auto_scaling`, `health_check`, `visibility`)
- `name`: Nombre amigable
- `definition`: JSON schema con la estructura del valor

Capabilities comunes para Kubernetes:

| Slug | Nombre | Descripción |
|------|--------|-------------|
| `visibility` | Visibility | Visibilidad: public/private (solo al crear, no se puede cambiar) |
| `listener_protocol` | Listener Protocol | Protocolo: http/grpc |
| `memory` | Memory | Memoria en GB |
| `kubernetes_processor` | Kubernetes Processor | CPU en millicores |
| `auto_scaling` | Auto Scaling | Config de HPA (instancias, CPU, memoria) |
| `health_check` | Health Check | Config de probes |
| `logs` | Logs | Provider y throttling de logs |
| `metrics` | Metrics | Providers de métricas |
| `continuous_delivery` | Continuous Delivery | Deploy automático desde branches |
| `scheduled_stop` | Scheduled Stop | Auto-stop después de inactividad |

**Para tipos `custom`** (como Scheduled Task):
El schema viene inline en `scope_type.parameters.schema` del paso 2.

#### Paso 4: Descubrir dimensions disponibles

```bash
# Obtener dimensions configuradas (usar NRN completo de la aplicación)
np-api fetch-api "/dimension?nrn=<app_nrn_encoded>"
```

Cada dimension tiene `values` con las opciones válidas. Ejemplo:

| Dimension | Valores disponibles |
|-----------|-------------------|
| Environment | development, staging, production |
| Country | argentina, mexico, us |

#### Paso 5: Consultar policies y approvals históricos

**IMPORTANTE**: Antes de armar el cuestionario, consultar approvals históricos de la misma aplicación
para descubrir qué policies aplican. Esto permite pre-configurar el scope para que cumpla TODAS
las policies y evitar que caiga en `pending_approval` (que requiere aprobación manual).

```bash
# Buscar approvals previos para descubrir policies
np-api fetch-api "/approval?nrn=<app_nrn_encoded>"
```

Si hay approvals previos, cada uno tiene `policy_context.policies[]` con las condiciones que la
organización evalúa. Extraer:

- `name`: nombre de la policy (ej: "[FinOps] Memory 2-4 GB")
- `conditions`: reglas (ej: `{"memory_in_gb": {"gte": 2, "lte": 4}}`)
- `evaluations[].result`: `met` o `not_met`
- `passed`: boolean — si la policy pasó
- `dimensions`: del approval — para saber a qué environment aplica cada policy

**Usar esta información para:**

1. **Pre-configurar capabilities**: Ajustar valores default para cumplir las policies
   - Ej: Si una policy exige `memory_in_gb >= 2`, usar 2 GB como mínimo en lugar de 1 GB
   - Ej: Si una policy exige `scheduled_stop.enabled = true`, habilitar scheduled_stop
2. **Elegir scope_type correcto**: Si una policy exige un tipo específico (ej: `web_pool` para stress-test),
   usarlo directamente — el campo `available` no bloquea la creación

**Método preferido: Dry-run de approval** (valida policies sin crear el scope):

```bash
# Validar scope contra policies sin crearlo
action-api.sh exec-api --method POST --data '{
  "nrn": "<app_nrn>",
  "action": "scope:create",
  "dimensions": {"environment": "stress-test", "country": "uruguay"},
  "requested": {
    "type": "web_pool",
    "dimensions": {"environment": "stress-test", "country": "uruguay"},
    "application_id": <app_id>,
    "capabilities": {
      "memory": {"memory_in_gb": 1},
      "scheduled_stop": {"timer": "3600", "enabled": true}
    }
  }
}' "/approval/dry-run"
```

La respuesta indica:
- `action: "approve"` → todas las policies pasan, el scope se auto-aprobará
- `action: "manual"` → alguna policy falló, requerirá aprobación manual

Cada policy evaluada incluye `name`, `conditions`, `evaluations[].result` (`met`/`not_met`) y `passed`.
Las `conditions` usan dot notation: `scope.type`, `scope.capabilities.memory.memory_in_gb`, etc.

**IMPORTANTE**: El campo `requested` usa la **misma estructura** que el body del POST `/scope`.
Probar con dry-run antes de crear permite ajustar la configuración hasta que `action` sea `"approve"`.

Ver `@action POST /approval/dry-run` más abajo para la documentación completa del endpoint.

#### Paso 5b: (Opcional) Consultar scopes existentes como referencia

```bash
np-api fetch-api "/scope?application_id=<app_id>"
```

Sirve para:
- Ver qué scopes ya existen (el nombre debe ser único)
- Usar un scope existente como referencia de configuración
- Ver la estructura real de capabilities (útil para entender el formato)

#### Paso 6: Armar cuestionario interactivo para el usuario

Basándose en los scope_types, capabilities y **policies descubiertas (paso 5)**, armar preguntas
usando `AskUserQuestion`. Usar las policies para pre-seleccionar valores que cumplan los requisitos.

**Primera ronda de preguntas** (siempre):
1. **Tipo de scope**: opciones disponibles del paso 2 (solo `available: true`).
   Si una policy exige un tipo específico, indicarlo al usuario
2. **Dimensions**: opciones del paso 4 (ej: environment=production, country=argentina)
3. **Memoria**: basado en capability `memory` (opciones de GB).
   **Respetar rangos de policies** (ej: si la policy exige 2-4 GB para production, el default debe ser 2 GB, no 1 GB)

**Segunda ronda de preguntas** (depende del tipo elegido):

Para **Kubernetes** (web_pool_k8s):
4. **Visibilidad**: public/private (capability `visibility`) — NOTA: solo se elige al crear, no se puede cambiar después
5. **Protocolo**: http/grpc (capability `listener_protocol`)
6. **Escalado**: fixed o auto (capability `auto_scaling`). Si auto → preguntar min/max replicas
7. **Opciones avanzadas** (multiSelect): Health check personalizado, Continuous Delivery, Scheduled Stop

Para **Scheduled Task** (custom):
4. **Cron expression**: frecuencia de ejecución
5. **Concurrency policy**: Allow, Forbid, Replace
6. **Retries**: número de reintentos (default 6)
7. **History limit**: ejecuciones pasadas a retener (default 3)
8. **Continuous Delivery**: habilitar o no

#### Paso 7: Confirmar con el usuario

Mostrar un resumen amigable para el usuario. NO mostrar detalles técnicos (POST, JSON, endpoints).
El usuario no necesita ver la request, solo entender qué se va a hacer.

Ejemplo de confirmación:

> Voy a crear el scope **Production** con estos datos:
>
> - **Tipo**: Kubernetes
> - **Environment**: production
> - **Country**: argentina
> - **Memoria**: 1 GB
> - **Visibilidad**: Pública (Internet)
> - **Protocolo**: HTTP
> - **Escalado**: Fijo, 1 instancia
> - **Health check**: /health (HTTP)
>
> ¿Confirmas?

Pedir confirmación explícita.

#### Paso 8: Ejecutar

```bash
action-api.sh exec-api --method POST --data '<json>' "/scope"
```

#### Paso 9: Verificar resultado post-creación

**IMPORTANTE**: Después de crear el scope, SIEMPRE verificar que no haya fallado.
El scope se crea en status `pending` o `pending_approval` y puede pasar a `failed`.

```bash
# 1. Esperar ~10 segundos y verificar status del scope
np-api fetch-api "/scope/<scope_id>"
```

Si el status es `failed`:

```bash
# 2. Obtener el instance_id del scope (campo instance_id en la respuesta)
#    y consultar las actions del service asociado
np-api fetch-api "/service/<instance_id>/action?limit=10"

# 3. Para cada action con status=failed, obtener los messages
np-api fetch-api "/service/<instance_id>/action/<action_id>?include_messages=true"
```

**Errores comunes y cómo resolverlos:**

| Error en messages | Causa | Solución |
|---|---|---|
| "Failed to deliver notification X to channel Y" + "You're not authorized" | La api_key del notification channel no tiene permisos | Verificar/regenerar la api_key del canal via `/notification/channel/<channel_id>` |
| "Failed to deliver notification X to channel Y" (sin detalle de auth) | El agent no está corriendo o el canal no matchea | Verificar agent activo via `/controlplane/agent` y que el canal tenga `source: ["entity", "service"]` |
| Timeout o sin messages | El agent recibió la notificación pero falló al ejecutar | Revisar logs del agent en el cluster |
| Queda en `pending`/`creating` sin error | Entity hook `before` bloqueando | `GET /entity_hook?nrn=<scope_nrn>&entity_name=scope` — buscar `status: pending/failed` |

**Flujo de diagnóstico completo:**

```bash
# Scope → instance_id → service actions → messages
np-api fetch-api "/scope/<scope_id>"
  # → instance_id

np-api fetch-api "/service/<instance_id>/action?limit=10"
  # → action id, status

np-api fetch-api "/service/<instance_id>/action/<action_id>?include_messages=true"
  # → error messages

# Si el error menciona un notification channel:
np-api fetch-api "/notification/channel/<channel_id>"
  # → verificar source, filters, api_key, selector

# Verificar que el agent esté activo:
np-api fetch-api "/controlplane/agent?organization_id=<org_id>&account_id=<account_id>"
  # → status, last_heartbeat
```

#### Paso 9b: Manejar approvals

Si el scope cae en `pending_approval` o cualquier estado de approval, consultar:

```bash
# 1. Buscar el approval asociado al scope
np-api fetch-api "/approval?nrn=<scope_nrn_encoded>"

# 2. Ver detalle del approval (incluye policies evaluadas)
np-api fetch-api "/approval/<approval_id>"
```

**Interpretar el estado del approval:**

| `status` | `execution_status` | Significado | Qué hacer |
|----------|-------------------|-------------|-----------|
| `pending` | `pending` | Esperando aprobación humana | Informar dónde aprobar, mencionar expiración si hay `time_to_reply` |
| `approved` | `pending` | Aprobado, sin ejecutar | Ofrecer `POST /approval/{id}/execute` |
| `approved` | `executing` | Ejecutándose | Esperar |
| `approved` | `success` | Completado | Continuar flujo |
| `approved` | `failed` | Ejecución falló | Diagnosticar |
| `approved` | `expired` | Ventana de ejecución expiró | Informar, puede necesitar recrear |
| `auto_approved` | `*` | Policies pasaron, auto-aprobado | Continuar flujo |
| `auto_denied` | - | Policies rechazaron automáticamente | Mostrar policies que fallaron, sugerir fixes |
| `denied` | - | Rechazado manualmente | Informar |
| `cancelled` | - | Cancelado | Informar |
| `expired` | - | Expiró sin respuesta | Informar, recrear si necesario |

Analizar `policy_context.policies[]` para identificar qué policies fallaron (`passed: false`)
y qué condiciones no se cumplieron (`evaluations[].result: "not_met"`).
Las conditions usan operadores MongoDB: `$gte`, `$lte`, `$eq`, `$or`, `$nor`, `$and`.

**Opciones según el estado:**

1. **`auto_denied` o `denied`**: Corregir y recrear con valores que cumplan las policies,
   o escalar a un administrador
2. **`pending`**: Indicar que debe solicitar aprobación por el canal correspondiente
   (Slack, UI de Nullplatform). Si tiene permisos, puede aprobar via:

```bash
action-api.sh exec-api --method POST --data '{}' "/approval/<approval_id>/execute"
```

3. **`approved` + `execution_status: pending`**: Ejecutar el approval:

```bash
action-api.sh exec-api --method POST --data '{}' "/approval/<approval_id>/execute"
```

4. **`expired`**: Recrear el scope si la ventana de aprobación expiró

#### Paso 9c: Si queda en `pending`/`creating` — Verificar entity hooks

Si el scope queda en `pending` o `creating` por más de ~30 segundos y NO hay approval
pendiente, puede haber un **entity hook `before`** bloqueando la operación.

```bash
# Verificar si hay hooks pendientes o fallidos para este scope
np-api fetch-api "/entity_hook?nrn=<scope_nrn_encoded>&entity_name=scope"
```

Filtrar resultados por `status: "pending"` o `status: "failed"`:

```bash
np-api fetch-api "/entity_hook?nrn=<scope_nrn_encoded>&entity_name=scope" | jq '[.results[] | select(.status == "pending" or .status == "failed") | {id, status, entity_action, messages}]'
```

Si hay hooks bloqueando:
- **`status: pending`**: El hook está esperando respuesta de un servicio externo. Informar al usuario y esperar.
- **`status: failed`**: El hook rechazó la operación. Mostrar `messages[]` al usuario. Contactar al platform team.
- **`status: recoverable_failure`**: Fallo recuperable — el sistema puede reintentar automáticamente.

**NOTA**: Los approvals tienen precedencia sobre hooks — se evalúan primero. Si hay approval
Y hooks, el approval se resuelve primero y luego se ejecutan los hooks.

### Campos requeridos (POST /scope)

- `application_id` (number): ID de la aplicación
- `name` (string): Nombre del scope (debe ser único en la aplicación)
- `type` (string): Valor del campo `type` del scope_type elegido (ej: `"web_pool_k8s"`, `"custom"`, `"serverless"`)
- `provider` (string): **IMPORTANTE**: Para tipos nativos (`web_pool_k8s`, `web_pool`, `serverless`), el campo `provider_id` del scope_type devuelve un valor simplificado (ej: `"web_pool_k8s"`) que **NO es válido** para el POST. El valor correcto para Kubernetes es `"AWS:WEB_POOL:EKS"`. Para obtener el provider real, consultar scopes existentes en el mismo account vía `/scope?application_id=<otra_app_id>`. Para tipos `custom`, el `provider_id` del scope_type (UUID) sí es válido directamente
- `dimensions` (object): Debe coincidir con los dimension values del paso 4
- `requested_spec` (object): Especificación de infraestructura
  - `cpu_profile` (string): Perfil de CPU (ej: `"standard"`)
  - `memory_in_gb` (number): Memoria en GB (ej: `1`)
  - `local_storage_in_gb` (number): Storage local en GB (ej: `8`)
- `capabilities` (object): Las keys son **slugs de capabilities** (no campos planos). Cada capability tiene su propia estructura según su schema

### Mapping de campos: scope_type → POST body

| Campo POST | Fuente |
|------------|--------|
| `type` | `scope_type.type` (ej: `web_pool_k8s`) |
| `provider` | Para tipos nativos: **NO usar** `scope_type.provider_id` directamente (ej: `web_pool_k8s` da error 400). Consultar scopes existentes para obtener el valor real (ej: `AWS:WEB_POOL:EKS`). Para tipos `custom`: usar `scope_type.provider_id` (UUID) |
| `capabilities.*` | Keys = capability `slug`, valores según `definition` de cada capability |

### Body ejemplo: Kubernetes (web_pool_k8s)

```json
{
  "application_id": "<app_id>",
  "name": "Production",
  "type": "web_pool_k8s",
  "provider": "AWS:WEB_POOL:EKS",
  "dimensions": {"environment": "production", "country": "argentina"},
  "requested_spec": {
    "cpu_profile": "standard",
    "memory_in_gb": 1,
    "local_storage_in_gb": 8
  },
  "capabilities": {
    "logs": {
      "throttling": {"unit": "line_seconds", "value": 1000, "enabled": false},
      "provider": "cloudwatch_logs"
    },
    "auto_scaling": {
      "enabled": false,
      "instances": {"amount": 1, "min_amount": 2, "max_amount": 10},
      "cpu": {"min_percentage": 30, "max_percentage": 50},
      "memory": {"target": 50, "enabled": false}
    },
    "metrics": {
      "custom_metrics_provider": "cloudwatch_metrics",
      "performance_metrics_provider": "cloudwatch_metrics"
    },
    "continuous_delivery": {"enabled": false},
    "memory": {"memory_in_gb": 1},
    "visibility": {"reachability": "public"},
    "kubernetes_processor": {"millicores": -1},
    "listener_protocol": {"name": "http"},
    "health_check": {
      "type": "http",
      "path": "/health",
      "configuration": {"timeout": 2, "interval": 5}
    },
    "scheduled_stop": {"timer": "3600", "enabled": false}
  }
}
```

### Body ejemplo: Scheduled Task (custom)

```json
{
  "application_id": "<app_id>",
  "name": "<scope_name>",
  "type": "custom",
  "provider": "<service_specification_uuid>",
  "dimensions": {"environment": "production"},
  "requested_spec": {
    "cpu_profile": "standard",
    "memory_in_gb": 1,
    "local_storage_in_gb": 8
  },
  "capabilities": {
    "ram_memory": 256,
    "cpu_millicores": 500,
    "cron": "0 3 * * *",
    "concurrency_policy": "Forbid",
    "retries": 6,
    "history_limit": 3,
    "continuous_delivery": {"enabled": false, "branches": ["main"]}
  }
}
```

> **NOTA**: El body de Scheduled Task usa capabilities planas (no por slug) porque es tipo `custom`
> con provider UUID. La estructura de capabilities depende del `parameters.schema` del scope_type.

### Consultas previas (via /np-api)

- Obtener aplicación: `np-api fetch-api "/application/<app_id>"`
- Listar tipos de scope: `np-api fetch-api "/scope_type?nrn=<app_nrn_encoded>&status=active&include=capabilities,wildcard,available"` → filtrar por `available: true`
- Capabilities disponibles: `np-api fetch-api "/capability?nrn=<app_nrn_encoded>&target=scope"` → cada capability tiene `slug` y `definition`
- Dimensions disponibles: `np-api fetch-api "/dimension?nrn=<app_nrn_encoded>"`
- Scopes existentes: `np-api fetch-api "/scope?application_id=<app_id>"`

### Respuesta

- `id`: ID del scope creado
- `status`: `pending` → `pending_approval` → `creating` → `active`
- `name`: Nombre del scope
- `slug`: Identificador URL-friendly generado
- `application_id`: ID de la aplicación
- `type`: Tipo del scope (ej: `web_pool_k8s`)
- `provider`: Provider del scope (ej: `AWS:WEB_POOL:EKS`)
- `domain`: Dominio asignado (ej: `app-name-production.org-account.nullapps.io`)
- `nrn`: NRN completo del scope
- `capabilities`: Capabilities con estructura por slugs
- `dimensions`: Dimensions tal como se enviaron

### Verificar resultado

```bash
# Verificar estado del scope creado
np-api fetch-api "/scope/<scope_id>"

# Ver notificaciones generadas (si falló)
np-api fetch-api "/notification?nrn=organization%3D<org_id>:account%3D<acc_id>&source=entity"
```

### Notas

- El scope se crea en status `pending`, puede pasar a `pending_approval` si hay policies, luego `creating` y finalmente `active`
- Si queda en `failed`: verificar que los notification channels tienen `entity` en el campo source
- Las dimensions deben coincidir con los dimension values configurados en la organización
- El nombre del scope debe ser único dentro de la aplicación
- Crear un scope genera una notificación de tipo `entity` que es procesada por el agent via notification channels
- **El campo `type` viene del `scope_type.type`** — puede ser `web_pool_k8s`, `custom`, `serverless`, `web_pool`
- **El campo `provider` viene del `scope_type.provider_id`** — puede ser un string fijo o un UUID
- **El campo `requested_spec` es requerido** (cpu_profile, memory_in_gb, local_storage_in_gb)
- **Para tipos nativos**: capabilities usan slugs como keys (`visibility`, `auto_scaling`, `health_check`, etc.)
- **Para tipo `custom`**: capabilities siguen el schema del `parameters.schema` del scope_type
- El campo `visibility.reachability` solo se puede elegir al crear, **no se puede cambiar después**
- Los tipos de scope varían entre organizaciones/accounts. **Nunca asumir que existen tipos específicos**; siempre descubrir via `/scope_type`
- **Policies**: La organización puede tener policies que validen el scope (ej: "producción debe ser K8s", "producción debe tener 2-4GB RAM"). Si hay conflictos, el scope queda en `pending_approval`. **Siempre consultar `/approval` en el Paso 5 para descubrir policies y cumplirlas**
- **`asset_name`**: El scope se crea sin `asset_name` (es `null`). Es necesario setearlo antes del primer deployment. Ver `deployments.md` Paso 5. Valores tipicos: `docker-image-asset` (K8s, EC2), `lambda-asset` (serverless)

### Policies conocidas (referencia, org 1255165411)

**IMPORTANTE**: Las policies varían por organización. SIEMPRE consultar `/approval` con el NRN
de la aplicación para descubrir las policies actuales antes de crear scopes. Esta tabla es solo
una referencia de policies descubiertas previamente.

| Environment | Policy | Condición |
|-------------|--------|-----------|
| stress-test | [SRE] Should be EC2 | `scope_type = web_pool` |
| stress-test | [FinOps] Memory 1-2 GB | `memory_in_gb >= 1 AND <= 2` |
| stress-test | [FinOps] Should Have Schedule Stop | `scheduled_stop.enabled = true`, `timer = "3600"` |
| production | [SRE] Should only be K8S | `scope_type = web_pool_k8s` |
| production | [FinOps] Memory 2-4 GB | `memory_in_gb >= 2 AND <= 4` |

**NOTA sobre `available: false`**: El campo `available` en scope_type es solo informativo y
NO bloquea la creación. Un scope_type con `available: false` se puede usar normalmente.
La UI de Nullplatform muestra todos los tipos activos sin filtrar por `available`.

### Anti-patrones de policies

| Mal | Por qué | Bien |
|-----|---------|------|
| Crear scopes sin consultar policies | Cae en `pending_approval`, requiere aprobación manual | Usar `POST /approval/dry-run` para validar antes de crear (Paso 5) |
| Asumir valores de memoria arbitrarios (ej: 1 GB) | Puede violar policies de FinOps que exigen rangos específicos | Revisar policies para conocer los rangos válidos por environment |
| No habilitar `scheduled_stop` en stress-test | Policy de FinOps puede exigirlo | Consultar policies y habilitar `scheduled_stop` si es requerido |

---

## @action POST /approval/dry-run

Valida una configuración de scope contra las policies de la organización **sin crear** el scope.
Permite verificar si la configuración cumple todas las policies antes de ejecutar el POST `/scope`.

Este es el mismo endpoint que usa el frontend de Nullplatform para mostrar feedback de policies
en tiempo real mientras el usuario llena el formulario de creación de scope (via BFF proxy en
`/bff/v1/approval/dry-run`).

### Request

```bash
action-api.sh exec-api --method POST --data '<json>' "/approval/dry-run"
```

### Body

```json
{
  "nrn": "<application_nrn>",
  "action": "scope:create",
  "dimensions": {
    "environment": "stress-test",
    "country": "uruguay"
  },
  "requested": {
    "id": null,
    "name": "Stress Test Uruguay",
    "type": "web_pool_k8s",
    "dimensions": {
      "environment": "stress-test",
      "country": "uruguay"
    },
    "application_id": 2021082335,
    "capabilities": {
      "memory": { "memory_in_gb": 1 },
      "scheduled_stop": { "timer": "3600", "enabled": true },
      "visibility": { "reachability": "public" },
      "health_check": { "type": "http", "path": "/health", "configuration": { "timeout": 2, "interval": 5 } },
      "auto_scaling": { "enabled": false, "instances": { "amount": 1, "min_amount": 2, "max_amount": 10 } },
      "continuous_delivery": { "enabled": false }
    }
  }
}
```

### Campos del body

- `nrn` (required): NRN de la aplicación
- `action` (required): `"scope:create"` para validar creación de scopes
- `dimensions` (required): Dimensions del scope (environment, country)
- `requested` (required): El scope completo que se crearía — **misma estructura que el body de POST `/scope`**
  - `type`: Tipo de scope (`web_pool`, `web_pool_k8s`, `serverless`, `custom`)
  - `capabilities`: Capabilities del scope (memory, scheduled_stop, visibility, etc.)

### Respuesta

```json
{
  "policies": [
    {
      "id": 737280069,
      "name": "[SRE] Stress-test Scopes Should be EC2",
      "conditions": { "scope.type": "web_pool" },
      "selector": {},
      "evaluations": [
        { "criteria": { "scope.type": "web_pool" }, "result": "not_met" }
      ],
      "passed": false,
      "selected": true
    }
  ],
  "action": "approve" | "manual",
  "approvalAction": {
    "id": 745472071,
    "entity": "scope",
    "action": "scope:create",
    "dimensions": { "environment": "stress-test" },
    "onPolicySuccess": "approve",
    "onPolicyFail": "manual",
    "policies": [...]
  }
}
```

### Campos clave de la respuesta

- `action`: **`"approve"`** = todas las policies pasan, el scope se auto-aprobará | **`"manual"`** = alguna policy falló, requerirá aprobación manual
- `policies[]`: Array con cada policy evaluada
  - `name`: Nombre descriptivo (ej: "[SRE] Stress-test Scopes Should be EC2")
  - `conditions`: Condiciones evaluadas — usan **dot notation** (ej: `scope.type`, `scope.capabilities.memory.memory_in_gb`)
  - `evaluations[]`: Resultado por criterio — `result`: `"met"` | `"not_met"`
  - `passed`: boolean — si la policy pasó
  - `selected`: boolean — si la policy aplica al contexto (basado en dimensions)
- `approvalAction`: La approval action configurada, incluyendo `onPolicySuccess` y `onPolicyFail`

### Comportamiento en el frontend

El frontend llama este endpoint **en cada cambio de campo** del formulario de creación de scope (debounced).
Según la respuesta:

- **`action: "approve"`**: Muestra checkmark verde: "This scope complies with your organization's policies and can be created right away."
- **`action: "manual"`**: Muestra X rojo: "This scope has conflicts with your organization's policies and your changes will require manual review." + botón "See conflicts"
  - "See conflicts" abre un modal con cada policy (pass/fail) y opción "See policy" que muestra el JSON
  - El modal ofrece "Close" o "Create anyway" (crea el scope sabiendo que caerá en `pending_approval`)

### Mapping UI → API (formulario de creación de scope)

| Campo UI | Campo API (`requested`) |
|----------|------------------------|
| Environment (dropdown) | `dimensions.environment` (lowercase, ej: `"stress-test"`) |
| Country (dropdown) | `dimensions.country` (lowercase, ej: `"uruguay"`) |
| Name (texto) | `name` (auto-generado: "{Environment} {Country}") |
| Target: Server instances | `type: "web_pool"` |
| Target: Kubernetes | `type: "web_pool_k8s"` |
| Target: Serverless | `type: "serverless"` |
| Target: Scheduled Task | `type: "custom"` |
| RAM Memory (dropdown) | `capabilities.memory.memory_in_gb` |
| Visibility: Internet | `capabilities.visibility.reachability: "public"` |
| Visibility: main Account | `capabilities.visibility.reachability: "private"` |
| Scheduled Stop: Enabled + Timer | `capabilities.scheduled_stop.enabled: true`, `.timer: "3600"` |
| Health Check: Path | `capabilities.health_check.path` |
| Continuous Deployment | `capabilities.continuous_delivery.enabled` |

### Notas

- **Usar siempre antes de crear un scope** para evitar `pending_approval`
- El campo `requested` acepta la misma estructura que POST `/scope` — se puede iterar ajustando capabilities hasta que `action` sea `"approve"`
- Las conditions con `$gte`/`$lte` indican rangos (ej: `{"$gte": 1, "$lte": 2}` = entre 1 y 2 GB)
- Si no hay approval actions configuradas para el environment, el dry-run puede retornar un error — esto indica que no hay policies y el scope se creará sin validación

---

## @action PATCH /scope/{id}

Modifica un scope existente. Permite cambiar capabilities, requested_spec, tier, asset_name y nombre.

### Flujo obligatorio

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery)
> y `/np-developer-actions exec-api` para ESCRITURA. NUNCA usar `curl` ni `/np-api` para PATCH.

#### Paso 1: Obtener estado actual del scope

```bash
np-api fetch-api "/scope/<scope_id>"
```

Verificar:
- `status` debe ser `active` (no se puede modificar un scope en `creating`, `failed`, `deleted`)
- Tomar nota de los valores actuales de `capabilities`, `requested_spec`, `tier`, `asset_name`

#### Paso 2: Identificar que se quiere cambiar

Preguntar al usuario que campo(s) quiere modificar. Campos modificables:

| Campo | Descripcion | Ejemplo |
|-------|-------------|---------|
| `name` | Nombre del scope | `"Production Argentina v2"` |
| `tier` | Prioridad: `important`, `default` | `"important"` |
| `asset_name` | Asset para deployments | `"docker-image-asset"` |
| `requested_spec` | CPU, memoria, storage | `{"memory_in_gb": 2}` |
| `capabilities` | Configuracion del scope | Ver estructura abajo |

**Campos NO modificables despues de crear:**
- `type` (web_pool_k8s, custom, etc.)
- `provider`
- `dimensions`
- `capabilities.visibility.reachability` (public/private)

#### Paso 3: Si se modifican capabilities, obtener capabilities actuales completas

```bash
np-api fetch-api "/scope/<scope_id>" | jq '.capabilities'
```

**IMPORTANTE**: El PATCH de capabilities hace merge parcial. Solo enviar las capabilities
que se quieren cambiar — las demas se mantienen. Pero dentro de cada capability, enviar
la estructura completa.

Ejemplo: para cambiar solo la memoria de 1GB a 2GB:
```json
{"capabilities": {"memory": {"memory_in_gb": 2}}}
```

Ejemplo: para cambiar auto_scaling:
```json
{
  "capabilities": {
    "auto_scaling": {
      "enabled": true,
      "instances": {"amount": 1, "min_amount": 2, "max_amount": 5},
      "cpu": {"min_percentage": 30, "max_percentage": 70},
      "memory": {"target": 50, "enabled": false}
    }
  }
}
```

#### Paso 4: Verificar contra policies (si aplica)

Si el cambio afecta campos evaluados por policies (memoria, scheduled_stop, tipo),
usar dry-run para validar:

```bash
action-api.sh exec-api --method POST --data '{
  "nrn": "<app_nrn>",
  "action": "scope:create",
  "dimensions": <scope_dimensions>,
  "requested": <scope_completo_con_cambios>
}' "/approval/dry-run"
```

#### Paso 5: Confirmar con el usuario

Mostrar un resumen amigable:

> Voy a modificar el scope **Production Argentina** (ID: 891203065):
>
> - **Memoria**: 1 GB -> 2 GB
> - **Auto-scaling**: deshabilitado -> habilitado (min: 2, max: 5)
>
> Confirmas?

#### Paso 6: Ejecutar

```bash
action-api.sh exec-api --method PATCH --data '<json>' "/scope/<scope_id>"
```

#### Paso 7: Verificar resultado

```bash
np-api fetch-api "/scope/<scope_id>"
```

Verificar que los campos modificados se actualizaron correctamente.
Si el scope pasa a `updating`, monitorear hasta que vuelva a `active`.

### Campos del body (PATCH)

Solo enviar los campos que se quieren cambiar:

```json
{
  "name": "Nuevo nombre",
  "tier": "important",
  "asset_name": "docker-image-asset",
  "requested_spec": {
    "cpu_profile": "standard",
    "memory_in_gb": 2,
    "local_storage_in_gb": 8
  },
  "capabilities": {
    "memory": {"memory_in_gb": 2},
    "auto_scaling": {"enabled": true, "instances": {"amount": 1, "min_amount": 2, "max_amount": 5}},
    "scheduled_stop": {"timer": "3600", "enabled": true}
  }
}
```

### Ejemplo

```bash
# Cambiar asset_name (prerequisito para primer deployment)
action-api.sh exec-api --method PATCH --data '{"asset_name":"docker-image-asset"}' "/scope/891203065"

# Cambiar memoria
action-api.sh exec-api --method PATCH --data '{"capabilities":{"memory":{"memory_in_gb":2}}}' "/scope/891203065"

# Habilitar auto-scaling
action-api.sh exec-api --method PATCH --data '{"capabilities":{"auto_scaling":{"enabled":true,"instances":{"amount":1,"min_amount":2,"max_amount":10},"cpu":{"min_percentage":30,"max_percentage":50},"memory":{"target":50,"enabled":false}}}}' "/scope/891203065"

# Habilitar scheduled stop
action-api.sh exec-api --method PATCH --data '{"capabilities":{"scheduled_stop":{"timer":"3600","enabled":true}}}' "/scope/891203065"
```

### Notas

- El PATCH es parcial — solo se actualizan los campos enviados
- Cambios de capabilities pueden requerir un re-deploy para aplicarse (depende del provider)
- Cambios de `requested_spec.memory_in_gb` pueden requerir que el scope pase por `updating`
- **`visibility.reachability` NO se puede cambiar** despues de crear el scope
- `asset_name` se usa frecuentemente en el flujo de deploy (ver deployments.md Paso 5)
- Si el PATCH activa policies que no se cumplen, el scope puede pasar a `pending_approval` (approval action `scope:write`). Consultar `GET /approval?nrn=<scope_nrn>` para ver el approval y sus policies
- Si el scope queda en `pending`/`updating` sin progreso, verificar entity hooks: `GET /entity_hook?nrn=<scope_nrn>&entity_name=scope`

---

## @action DELETE /scope/{id}

Elimina un scope. La eliminacion destruye toda la infraestructura asociada (instancias, servicios del scope).

### Flujo obligatorio

#### Paso 1: Verificar estado del scope

```bash
np-api fetch-api "/scope/<scope_id>"
```

Verificar:
- `status` debe ser `active` o `failed` (no se puede eliminar un scope en `creating` o `deleting`)
- Tomar nota del `name`, `dimensions`, y `type` para confirmar con el usuario

#### Paso 2: Verificar que no haya deployments activos

```bash
np-api fetch-api "/deployment?scope_id=<scope_id>&status=running"
```

Si hay deployments en status `running`:
- **Advertir al usuario** que eliminar el scope destruira los deployments activos
- Recomendar finalizar los deployments primero (PATCH status=finalizing)
- Si el usuario insiste, proceder con la advertencia

#### Paso 3: Verificar links asociados

```bash
np-api fetch-api "/link?nrn=<scope_nrn_encoded>"
```

Si hay links activos en el scope:
- Informar al usuario que los links se eliminaran junto con el scope
- Listar los servicios afectados

#### Paso 4: Confirmar con el usuario

Mostrar un resumen claro de lo que se va a destruir:

> **ATENCION: Operacion destructiva e irreversible**
>
> Voy a eliminar el scope **Production Argentina** (ID: 891203065):
>
> - **Tipo**: Kubernetes
> - **Dimensions**: environment=production, country=argentina
> - **Deployments activos**: 1 (se destruira)
> - **Links**: 2 (se eliminaran)
>
> Esta accion eliminara toda la infraestructura asociada. No se puede deshacer.
>
> Confirmas? (escribe "si, eliminar" para confirmar)

**Pedir confirmacion explicita y enfatica** dado que es una operacion destructiva.

#### Paso 5: Ejecutar

```bash
action-api.sh exec-api --method DELETE --data '{}' "/scope/<scope_id>"
```

#### Paso 6: Verificar resultado

```bash
np-api fetch-api "/scope/<scope_id>"
```

El scope deberia pasar a `deleting` y eventualmente a `deleted`.
Si queda en `deleting` por mucho tiempo, verificar service actions:

```bash
# Si el scope tiene instance_id
np-api fetch-api "/service/<instance_id>/action?limit=5"
```

### Comportamiento del DELETE

- **Response**: `DELETE /scope/{id}` devuelve **body vacío** (HTTP 204) en éxito. No hay JSON de confirmación.
- **Rename**: Al eliminarse, el scope se renombra automáticamente a `deleted-{timestamp}-{name}` (ej: `deleted-1772074494275-Production Argentina`)
- **Status `failed`**: Si el deprovisionamiento de infra falla (ej: error borrando ingress en K8s), el scope queda en status `failed` con el nombre ya renombrado a `deleted-...`. Usar `GET /scope/{id}?include_messages=true` para ver el error específico.
- **Scopes sin `instance_id`**: Los scopes que nunca tuvieron infraestructura provisionada (`instance_id: null`) pueden fallar al eliminar porque no hay service actions que consultar. Los errores se ven en `messages[]` del scope (con `include_messages=true`).

### Notas

- La eliminacion es **asincrona** — el scope pasa por `deleting` antes de llegar a `deleted`
- La eliminacion destruye: instancias, load balancers, DNS records, y cualquier recurso del scope
- Los parametros asociados al scope se eliminan
- Los links se desvinculan/eliminan
- Si el scope tiene deployments `running`, se destruyen sin ventana de rollback
- **No se puede deshacer** — para recuperar, hay que crear un scope nuevo desde cero
- La eliminación puede triggerear un approval de `scope:delete`. Si el scope no pasa a `deleting`, verificar `GET /approval?nrn=<scope_nrn>` para ver si hay un approval pendiente
- Si el scope queda bloqueado sin approval, verificar entity hooks: `GET /entity_hook?nrn=<scope_nrn>&entity_name=scope`
