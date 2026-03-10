# Workflows (Approvals, Notifications, Templates)

Entidades de workflow y configuración.

## @endpoint /approval/{id}

Obtiene detalles de una aprobación.

### Parámetros
- `id` (path, required): ID de la aprobación

### Respuesta
- `id`: ID de la aprobación
- `created_at`: Timestamp de creación
- `approval_action_id`: ID de la acción de approval (referencia interna)
- `entity_id`: ID de la entidad que requiere aprobación (ej: deployment ID como string)
- `aggregator_entity_id`: ID del agregador (null si no aplica)
- `entity_name`: Tipo de entidad (ej: `deployment`, `service:action`, `scope`)
- `nrn`: NRN completo del recurso
- `entity_action`: Acción que requiere aprobación (ej: `deployment:create`)
- `status`: `pending` | `approved` | `auto_approved` | `auto_denied` | `denied` | `cancelled` | `expired`
- `execution_status`: `pending` | `executing` | `success` | `failed` | `expired` - indica si la acción aprobada ya se ejecutó
- `user_id`: ID del usuario que solicitó
- `dimensions`: Dimensiones del contexto
  - `environment`: production | staging | development | etc
  - `country`: usa | mx | ar | etc
- `policy_context`: Contexto de evaluación de policies
  - `policies[]`: Array de policies evaluadas
    - `id`: ID de la policy
    - `name`: Nombre descriptivo (ej: "[SRE] Tests coverage should be above 80%")
    - `selector`: Pre-filtro que determina si la policy aplica al request (ej: por dimensions, entity type)
    - `conditions`: Condiciones requeridas. Usan sintaxis MongoDB: `$gte`, `$lte`, `$eq`, `$or`, `$nor`, `$and`
      - Ejemplo: `{"build_metadata_coverage_percent": {"$gte": 80}}`
      - Ejemplo rango: `{"scope.capabilities.memory.memory_in_gb": {"$gte": 2, "$lte": 4}}`
    - `evaluations[]`: Resultado de cada criterio
      - `criteria`: Criterio evaluado
      - `result`: `met` | `not_met`
    - `passed`: boolean - si la policy pasó
    - `selected`: boolean - si la policy aplica a este contexto (determinado por selector)
  - `action`: `auto` | `manual` - si se auto-aprobó o requirió intervención humana
  - `time_to_reply`: Ventana para responder (ms). Expira si no se responde a tiempo
  - `allowed_time_to_execute`: Ventana para ejecutar post-aprobacion (ms)
- `context`: Snapshot completo de las entidades relacionadas al momento de la aprobación
  - `user`: Datos del usuario que solicitó
  - `deployment`: Estado del deployment al momento del approval
  - `scope`: Datos del scope target
  - `release`: Release a desplegar
  - `build`: Build asociado al release
  - `application`: Aplicación
  - `namespace`, `account`, `organization`: Jerarquía organizacional
- `updated_at`: Timestamp de última actualización

### Navegación
- **→ deployment**: `entity_id` → `/deployment/{entity_id}` (cuando `entity_name` es `deployment`)
- **→ user**: `user_id` → `/user/{user_id}`
- **← deployment NRN**: `/approval?nrn={deployment_nrn_encoded}`

### Ejemplo
```bash
np-api fetch-api "/approval/541210877"
```

### Entity/action combinations soportadas

| Entity Name | Entity Action | Descripcion |
|-------------|---------------|-------------|
| `deployment` | `deployment:create` | Al crear un deployment |
| `scope` | `scope:create` | Al crear un scope |
| `scope` | `scope:recreate` | Al recrear un scope |
| `scope` | `scope:write` | Al modificar un scope (PATCH) |
| `scope` | `scope:delete` | Al eliminar un scope |
| `scope` | `scope:stop` | Al detener un scope |
| `service:action` | `service:action:create` | Al ejecutar una action de servicio |
| `parameter` | `parameter:read-secrets` | Al solicitar acceso a secretos |

### Approval request statuses

| Status | Descripcion |
|--------|-------------|
| `pending` | Esperando decision humana |
| `approved` | Aprobado manualmente |
| `auto_approved` | Aprobado automaticamente (todas las policies pasaron) |
| `denied` | Rechazado manualmente |
| `auto_denied` | Rechazado automaticamente (policies fallaron + config auto-deny) |
| `cancelled` | Cancelado por el usuario o sistema |
| `expired` | Expiro sin respuesta (superó `time_to_reply`) |

### Execution statuses

| Status | Descripcion |
|--------|-------------|
| `pending` | Aprobado pero no iniciado aun |
| `executing` | Ejecucion en progreso |
| `success` | Ejecutado exitosamente |
| `failed` | Ejecucion fallo |
| `expired` | Expiro sin ejecutar (superó `allowed_time_to_execute`) |

### Secret visibility (parameter:read-secrets)

Cuando `entity_action` es `parameter:read-secrets`, el approval controla el acceso temporal
a valores secretos de parametros. Flujo:
1. Usuario solicita ver secretos desde la UI
2. Se crea un approval request con `entity_action: parameter:read-secrets`
3. Si se aprueba, el usuario obtiene acceso por 24 horas
4. El approval expira a los 3 dias si no se responde

### Notas
- `status: approved` + `execution_status: pending` = aprobado pero esperando que se inicie el deployment ("Start deployment" en la UI)
- `status: approved` + `execution_status: executed` = aprobado y deployment ya iniciado
- `policy_context.action: manual` indica que las policies no pasaron y se requirió aprobación humana
- `policy_context.action: auto` indica que las policies pasaron y se auto-aprobó
- El `context` es un snapshot inmutable del momento del approval - útil para auditoría
- **Policy operators**: Las conditions usan sintaxis MongoDB: `$gte`, `$lte`, `$eq`, `$or`, `$nor`, `$and`
- **Selectors**: Actuan como pre-filtros antes de evaluar conditions. Determinan si la policy aplica al request
- **Scopes**: Cuando `entity_name` es `scope`, el approval se genera al crear un scope que no cumple las policies de la organización (ej: memoria fuera de rango, scope_type incorrecto, scheduled_stop deshabilitado). Ver `np-developer-actions/docs/scopes.md` Paso 5 para consultar policies antes de crear scopes

---

## @endpoint /approval

Lista aprobaciones con filtros.

### Parámetros
- `nrn` (query, required): NRN del recurso (URL-encoded). Soporta NRN a distintos niveles:
  - **NRN de aplicación**: retorna todos los approvals de la app (scopes + deployments)
  - **NRN de deployment**: retorna approvals de un deployment específico
  - **NRN de scope**: retorna approvals de un scope específico

### Respuesta
```json
{
  "paging": {"total": 1, "offset": 0, "limit": 30},
  "results": [...]
}
```

Cada resultado tiene la misma estructura que `/approval/{id}`.

### Ejemplo
```bash
# Buscar approvals de un deployment específico
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>%3Ascope%3D<scope_id>%3Adeployment%3D<deployment_id>"

# Buscar todos los approvals de una aplicación (incluye scopes y deployments)
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>"
```

### Notas
- El NRN debe estar URL-encoded (reemplazar `=` con `%3D` y `:` con `%3A`)
- Usar el NRN del deployment (no solo el ID) para filtrar approvals
- **Para descubrir policies de scopes**: usar NRN a nivel de aplicación para obtener approvals previos y extraer `policy_context.policies[]` con las condiciones que la organización evalúa
- El listado directo sin NRN puede dar error 403 (no autorizado)
- Retorna el mismo nivel de detalle que el GET individual, incluyendo `policy_context` y `context`

---

## @endpoint /approval/{id}/execute

Ejecuta un approval aprobado. Este es el endpoint que usa el boton "Start deployment" de la UI.
Aprueba el approval y ejecuta la accion asociada en un solo paso.

### Parametros
- `id` (path, required): ID del approval

### Request
- **Method**: POST
- **Body**: `{}` (vacio)

### Comportamiento

Al ejecutar, el approval:
1. Cambia `status` a `approved` (si estaba en `pending`)
2. Cambia `execution_status` a `executed`
3. Ejecuta internamente la accion asociada (ej: PATCH al deployment con `{"status": "creating"}`)
4. Popula el campo `context` con el snapshot de todas las entidades relacionadas

### Respuesta

Retorna el approval completo actualizado (misma estructura que GET `/approval/{id}`),
incluyendo `policy_context` con las policies evaluadas y `context` con el snapshot.

### Ejemplo
```bash
# NOTA: Este es un POST, no un GET. Usar desde np-developer-actions:
action-api.sh exec-api --method POST --data '{}' "/approval/<approval_id>/execute"
```

### Notas
- Body vacio (`{}`) - no requiere parametros adicionales
- Solo funciona con approvals en `status: pending` o `status: approved` + `execution_status: pending`
- Si el approval ya fue ejecutado o el deployment ya fue iniciado por otro medio, retorna `execution_status: failed`
- **Este es el camino correcto para iniciar un deployment aprobado** (en vez de PATCH directo al deployment)

---

## @endpoint /notification/channel/{id}

Obtiene detalles de un canal de notificación.

### Parámetros
- `id` (path, required): ID del canal

### Respuesta
- `id`: ID numérico
- `name`: Nombre del canal
- `type`: slack | email | webhook
- `status`: Estado
- `nrn`: NRN del contexto
- `configuration`: Config específica del tipo

### Dominio
```
https://notifications.nullplatform.com/notification/channel/{id}
```

### Ejemplo
```bash
np-api fetch-api "https://notifications.nullplatform.com/notification/channel/456"
```

---

## @endpoint /notification/channel

Lista canales de notificación.

### Parámetros
- `nrn` (query, required): NRN base
- `showDescendants` (query): **camelCase** - incluye canales de jerarquía inferior
- `limit` (query): Máximo de resultados

### Ejemplo
```bash
np-api fetch-api "https://notifications.nullplatform.com/notification/channel?nrn=organization%3D4&showDescendants=true&limit=500"
```

### Notas
- Usar `showDescendants` (**camelCase**) NO `show_descendants`
- Inconsistente con `/provider` que usa snake_case
- Sin `showDescendants=true` solo retorna canales a nivel del NRN especificado

---

## @endpoint /template/{id}

Obtiene detalles de un template de aplicación.

### Parámetros
- `id` (path, required): ID del template (puede ser nombre con versión)

### Respuesta
- `id`: ID/nombre del template
- `name`: Nombre descriptivo
- `version`: Versión
- `runtime`: Configuración de runtime
- `build_command`: Comando de build
- `health_check_config`: Config de health checks
- `resources`: Recursos default

### Ejemplo
```bash
np-api fetch-api "/template/react_18.2.0"
```

---

## @endpoint /template

Lista templates disponibles.

### Ejemplo
```bash
np-api fetch-api "/template"
```

---

## @endpoint /report

Lista reportes disponibles (analytics y compliance).

### Dominio
```
https://reports.nullplatform.com/report
```

### Ejemplo
```bash
np-api fetch-api "https://reports.nullplatform.com/report"
```

---

## @endpoint /user/{id}

Obtiene detalles de un usuario.

### Parámetros
- `id` (path, required): ID del usuario

### Respuesta
- `id`: ID numérico
- `email`: Email del usuario
- `name`: Nombre
- `role`: Rol
- `status`: Estado
- `created_at`, `last_login`: Timestamps

### Service Accounts Comunes
- `gabriel+scope_workflow_manager_job@nullplatform.io` - Lifecycle de scopes
- `nullmachineusers+approvals-api@nullplatform.io` - Workflow de approvals
- `nullmachineusers+ephemeral-scopes@nullplatform.io` - Auto-stop scheduler

### Ejemplo
```bash
np-api fetch-api "/user/111433570"
```

---

## @endpoint /user

Lista usuarios.

### Ejemplo
```bash
np-api fetch-api "/user"
```
