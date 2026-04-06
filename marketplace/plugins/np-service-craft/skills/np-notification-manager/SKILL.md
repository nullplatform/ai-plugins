---
name: np-notification-manager
description: This skill should be used when the user asks to "create a notification channel", "debug notifications", "resend a notification", "check channel configuration", "inspect notification delivery", or needs to manage nullplatform notification channels, agent routing, and test notification delivery.
---

# np-notification-manager

Skill dedicado a la gestión de notification channels y notificaciones en NullPlatform. Centraliza la creación, inspección, y debugging de channels que conectan eventos de la plataforma con agentes.

## Critical Rules

1. **Siempre usar `/np-api fetch-api`** para acceder a la API. NUNCA usar `curl` directamente contra `api.nullplatform.com`.
2. **Confirmar antes de crear o modificar** channels. Mostrar la configuración completa y pedir confirmación explícita.
3. **Validar selector/tags** contra el agente target antes de crear un channel.

## Available Commands

| Command | Description |
|---------|-------------|
| `/np-notification-manager list` | Listar channels activos para un NRN |
| `/np-notification-manager create` | Crear un notification channel (guiado) |
| `/np-notification-manager inspect <channel-id>` | Ver configuración detallada de un channel |
| `/np-notification-manager notifications <nrn>` | Ver notificaciones recientes para un NRN |
| `/np-notification-manager resend <notification-id> [channel-id]` | Reenviar una notificación |
| `/np-notification-manager debug <channel-id>` | Diagnosticar problemas de delivery |

---

## Command: List Channels (`/np-notification-manager list`)

Listar todos los channels activos para un NRN:

```
/np-api fetch-api "/notification/channel?nrn=<account-nrn>&status=active"
```

Mostrar tabla resumen:

```
| ID        | Description       | Type  | Source           | Selector              | Filters                              |
|-----------|-------------------|-------|------------------|-----------------------|--------------------------------------|
| 848305398 | k8s scope         | agent | telemetry,service| cluster:runtime       | spec.slug=$eq:kubernetes-custom      |
| 848305399 | postgres service  | agent | service          | cluster:runtime       | spec.slug=$eq:postgres-k8s           |
```

---

## Command: Create Channel (`/np-notification-manager create`)

Flujo guiado para crear un notification channel.

### Preguntas

1. **NRN**: "What account/organization NRN should own this channel?"
2. **Description**: "Human-readable name for this channel?"
3. **Purpose**:
   - Scope (deployment actions + telemetry) → sources: `["telemetry", "service"]`
   - Service (provisioning actions only) → sources: `["service"]`
   - Telemetry only (logs/metrics) → sources: `["telemetry"]`
4. **Command configuration**:
   - Entrypoint path (e.g., `<repo-path>/entrypoint`)
   - Service path argument (e.g., `--service-path=<repo-path>/<scope-dir>`)
   - Overrides path (optional, e.g., `--overrides-path=<path>`)
5. **Agent selector tags**: Key-value pairs that must match the agent's `--tags`
   - e.g., `environment: demo`, `cluster: runtime`
6. **Filters**: Match notifications for specific scope/service types
   - Service specification slug (e.g., `kubernetes-custom`)
   - Or custom filter expressions

### Channel JSON Structure

```json
{
  "nrn": "<nrn>",
  "description": "<description>",
  "type": "agent",
  "source": ["<sources>"],
  "status": "active",
  "configuration": {
    "command": {
      "type": "exec",
      "data": {
        "cmdline": "<entrypoint-path> --service-path=<scope-path>",
        "environment": {
          "NP_ACTION_CONTEXT": "'${NOTIFICATION_CONTEXT}'"
        }
      }
    },
    "selector": {
      "<tag-key>": "<tag-value>"
    }
  },
  "filters": {
    "service.specification.slug": {
      "$eq": "<slug>"
    }
  }
}
```

### Campos clave

| Campo | Descripción | Valores comunes |
|-------|-------------|-----------------|
| `type` | Tipo de channel | `agent` (siempre para scopes/services) |
| `source` | Qué eventos recibe | `["service"]`, `["telemetry"]`, `["telemetry", "service"]` |
| `configuration.command.type` | Cómo ejecutar | `exec` (ejecuta comando en el agente) |
| `configuration.command.data.cmdline` | Comando a ejecutar | Path al entrypoint con args |
| `configuration.command.data.environment` | Variables de entorno | Siempre incluir `NP_ACTION_CONTEXT` |
| `configuration.selector` | Tags del agente target | Deben coincidir con `--tags` del agente |
| `filters` | Qué notificaciones matchear | Slug del service specification |

### Sources explicadas

- `"service"`: Recibe notificaciones de acciones sobre scopes y deployments (create, deploy, delete, etc.)
- `"telemetry"`: Recibe requests de logs, métricas, instancias, y parámetros
- Para un scope completo, siempre usar ambas: `["telemetry", "service"]`

### Filters avanzados

Operadores disponibles en filters:
- `$eq` — igualdad exacta
- `$ne` — diferente
- `$in` — uno de varios valores
- `$contains` — contiene substring

Ejemplo con múltiples filtros:
```json
{
  "filters": {
    "service.specification.slug": { "$eq": "my-scope" },
    "arguments.scope_provider": { "$eq": "<spec-id>" }
  }
}
```

### Crear el channel

Mostrar el JSON completo al usuario y pedir confirmación. Luego:

```
/np-api fetch-api "POST /notification/channel" con body: <channel-json>
```

Capturar el ID del channel creado y mostrarlo al usuario.

---

## Command: Inspect Channel (`/np-notification-manager inspect <channel-id>`)

Ver la configuración completa de un channel:

```
/np-api fetch-api "/notification/channel/<channel-id>"
```

Mostrar:
1. **Configuración general**: ID, NRN, description, type, status, sources
2. **Comando**: cmdline, environment variables
3. **Selector**: Tags que debe tener el agente
4. **Filters**: Qué notificaciones matchea
5. **Timestamps**: created_at, updated_at
6. **Validaciones**:
   - Verificar que el selector tiene tags razonables
   - Verificar que los filters referencian un slug válido
   - Verificar que el cmdline apunta a un path existente (si es local)

---

## Command: List Notifications (`/np-notification-manager notifications <nrn>`)

Ver notificaciones recientes:

```
/np-api fetch-api "/notification?nrn=<nrn>&per_page=20"
```

Mostrar tabla con:

```
| ID       | Action              | Status    | Created            | Channel Deliveries |
|----------|---------------------|-----------|--------------------|-------------------|
| 12345678 | start-initial       | delivered | 2025-05-17T16:37Z  | 1 success         |
| 12345679 | create-scope        | delivered | 2025-05-17T16:38Z  | 1 success         |
| 12345680 | log:read            | failed    | 2025-05-17T16:39Z  | 0 success         |
```

Para ver el detalle de delivery de una notificación:

```
/np-api fetch-api "/notification/<notification-id>/result"
```

---

## Command: Resend Notification (`/np-notification-manager resend <notification-id> [channel-id]`)

Reenvía una notificación para retesting sin necesidad de recrear recursos desde la UI.

```
/np-api fetch-api "POST /notification/<notification-id>/resend" con body:
```

Sin channel específico (reenvía a todos los channels que matchean):
```json
{}
```

Con channel específico:
```json
{
  "channels": [{ "id": <channel-id> }]
}
```

### Cuándo usar resend

- **Debugging**: El script falló y lo corregiste, querés reejecutar sin recrear el scope/deployment
- **Testing iterativo**: Estás desarrollando un scope y querés probar cambios en scripts
- **Validación**: Querés verificar que un fix en el agente resuelve el problema

### Encontrar el notification ID

```
/np-api fetch-api "/notification?nrn=<scope-nrn>&per_page=5"
```

Filtrar por acción específica si es necesario, revisando el campo `action` en cada notificación.

---

## Command: Debug Channel (`/np-notification-manager debug <channel-id>`)

Diagnóstico completo de un channel que no está funcionando.

### Checks automáticos

1. **Channel status**: Verificar que está `active`
   ```
   /np-api fetch-api "/notification/channel/<channel-id>"
   ```

2. **Agent connection**: Buscar agentes con tags que matcheen el selector
   ```
   /np-api fetch-api "/controlplane/agent"
   ```
   Filtrar por tags del selector y verificar que al menos un agente está activo.

3. **Filter validation**: Verificar que el slug en los filters corresponde a un service specification existente
   ```
   /np-api fetch-api "/service/specification?slug=<slug>"
   ```

4. **Recent deliveries**: Revisar las últimas notificaciones y sus resultados
   ```
   /np-api fetch-api "/notification?nrn=<channel-nrn>&per_page=10"
   ```
   Para cada una, revisar delivery result.

5. **Command path validation**: Si tenemos acceso local, verificar que el cmdline apunta a archivos existentes:
   - ¿Existe el entrypoint?
   - ¿Existe el service-path?
   - ¿Los scripts tienen permisos de ejecución?

### Reporte de diagnóstico

```
Channel Debug Report: <channel-id>
=====================================

Channel Status: [PASS] active
Agent Match:    [PASS] 1 agent(s) with matching tags
Filter Valid:   [PASS] slug "kubernetes-custom" exists (spec ID: 123)
Recent Delivery:[WARN] 2/5 notifications failed in last hour
Command Path:   [PASS] entrypoint exists and is executable

Issues Found:
  - 2 failed deliveries: Script error in build_context (line 45)
    Notification IDs: 12345678, 12345679
    → Review agent logs for details
    → Use /np-notification-manager resend <id> to retry after fix
```

---

## Reference: Channel Types

| Type | Uso | Configuración |
|------|-----|---------------|
| `agent` | Scopes y services — ejecuta comandos en el agente | `command.type: "exec"`, `cmdline`, `environment` |
| `webhook` | Integraciones externas — envía HTTP POST | `url`, `headers`, `body_template` |
| `sns` | AWS SNS — publica en un topic | `topic_arn`, `region` |

Para scopes y services, siempre usar `type: "agent"`.

## Reference: Notification Lifecycle

```
1. User Action (UI/API) → Service/Scope API
2. API creates Notification (status: pending)
3. Platform matches Notification against active channels:
   - source match (service, telemetry)
   - filter match (slug, custom filters)
4. For each matching channel:
   - Finds agents with matching selector tags
   - Sends command via WebSocket to agent
5. Agent executes command
6. Result reported back (success/failure)
7. Notification status updated (delivered/failed)
```

## Troubleshooting

| Problema | Causa probable | Diagnóstico |
|----------|---------------|-------------|
| Channel no matchea notificaciones | Filters incorrectos o source faltante | Verificar slug y sources con `/inspect` |
| Notificación delivered pero script no corre | cmdline incorrecto o permisos | Verificar path y `chmod +x` |
| Agent no recibe | Tags no coinciden con selector | Comparar `--tags` del agente con `selector` del channel |
| Delivery timeout | Script tarda mucho o se cuelga | Revisar agent logs con `--command-executor-debug` |
| Notificación failed | Error en la ejecución del script | Ver `/notification/<id>/result` para detalles del error |
| Channel en status inactive | Fue desactivado manual o automáticamente | Reactivar via API PATCH |
