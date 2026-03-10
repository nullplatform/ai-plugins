# Entity Hooks

Entity hooks son interceptores de ciclo de vida que se ejecutan antes o despues de operaciones
sobre entidades (applications, scopes, deployments). Permiten validar, notificar o bloquear
operaciones automaticamente.

## @endpoint /entity_hook

Lista instancias de entity hooks ejecutadas.

### Parametros
- `nrn` (query, required): NRN con URL encoding
- `entity_name` (query): Filtrar por tipo de entidad: `application` | `scope` | `deployment`
- `limit` (query): Maximo de resultados (default 30)

### Respuesta
```json
{
  "paging": {"total": 247, "offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "entity_hook_action_id": "uuid-de-la-definicion-del-hook",
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

### Campos clave
- `id`: UUID de la instancia del hook (ejecucion especifica)
- `entity_hook_action_id`: UUID de la definicion del hook (template/regla)
- `entity_name`: Tipo de entidad: `application`, `scope`, `deployment`
- `entity_action`: Accion completa: `application:create`, `scope:create`, `deployment:create`, `deployment:write`
- `entity_id`: ID de la entidad afectada
- `nrn`: NRN completo de la entidad
- `status`: Estado del hook: `success` (paso), `pending` (esperando), `failed` (fallo), `recoverable_failure` (fallo recuperable), `cancelled`
- `execution_status`: Estado de ejecucion: `pending`, `running`, `completed`
- `when`: `before` (pre-operacion, puede bloquear) | `after` (post-operacion, notificacion)
- `on`: Tipo de operacion: `create` | `write` | `delete`
- `messages[]`: Logs de la ejecucion del hook (info/warning/error)
- `dimensions`: Dimensions de la entidad afectada (puede estar vacio)
- `context`: Snapshot de la entidad al momento del hook (puede ser null o contener el objeto completo)

### Entity actions conocidas
- `application:create` - Al crear una aplicacion
- `scope:create` - Al crear un scope
- `scope:delete` - Al eliminar un scope
- `deployment:create` - Al crear un deployment
- `deployment:write` - Al modificar un deployment (ej: traffic switch)

### Ejemplo
```bash
# Todos los hooks de la organizacion
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411"

# Solo hooks de scopes
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&entity_name=scope"

# Solo hooks de deployments
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&entity_name=deployment"

# Filtrar hooks fallidos con jq
np-api fetch-api "/entity_hook?nrn=organization%3D1255165411&limit=100" | jq '[.results[] | select(.status == "failed")]'
```

### Notas
- Los hooks `before` pueden **bloquear** la operacion si fallan (status=failed)
- Los hooks `after` son informativos y no bloquean
- `context` contiene el snapshot de la entidad — util para diagnosticar que se estaba creando/modificando
- Si un scope queda en `pending` o `creating`, verificar si hay un hook `before` bloqueandolo
- Los hooks se definen via `entity_hook_action` (la definicion/template), este endpoint muestra las instancias/ejecuciones

---

## @endpoint /entity_hook/{id}

Obtiene detalle de una instancia de entity hook.

### Parametros
- `id` (path, required): UUID de la instancia del hook

### Respuesta
Misma estructura que un elemento de la lista (ver arriba).

### Ejemplo
```bash
np-api fetch-api "/entity_hook/2477f213-926d-423e-89ce-d18c5570d24c"
```

### Notas
- Util para verificar el estado de un hook especifico
- El campo `context` puede contener el objeto completo de la entidad al momento del hook

---

## @endpoint /entity_hook/action

Lista las definiciones (templates/reglas) de entity hooks. Estas son las reglas que determinan
que hooks se ejecutan cuando ocurre una operacion sobre una entidad.

### Parametros
- `nrn` (query, required): NRN con URL encoding

### Respuesta
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

### Campos clave
- `id`: UUID de la definicion del hook
- `entity`: Tipo de entidad monitoreada: `application` | `scope` | `deployment`
- `action`: Accion que dispara el hook: `application:create`, `scope:create`, `scope:delete`, `deployment:create`, `deployment:write`
- `when`: `before` (puede bloquear) | `after` (informativo)
- `on`: Tipo de operacion: `create` | `write` | `delete`
- `nrn`: NRN donde aplica la regla (cascadea a hijos)
- `dimensions`: Filtro de dimensions — el hook solo se ejecuta si las dimensions de la entidad coinciden
- `notification_channel_id`: Canal de notificacion que recibe y procesa el hook

### Relacion con instancias

Las definiciones (`/entity_hook/action`) son las reglas. Las instancias (`/entity_hook`) son
las ejecuciones concretas. Cada vez que se crea/modifica una entidad que matchea una regla,
se crea una instancia con `entity_hook_action_id` apuntando a la definicion.

### Ejemplo
```bash
# Listar todas las definiciones de hooks de la organizacion
np-api fetch-api "/entity_hook/action?nrn=organization%3D1255165411"

# Filtrar por entity_name
np-api fetch-api "/entity_hook/action?nrn=organization%3D1255165411" | jq '[.results[] | select(.entity == "scope")]'
```

### Notas
- Las definiciones requieren un notification channel configurado previamente
- El campo `dimensions` permite que un hook solo aplique a ciertos environments/countries
- Hooks `before` bloquean la operacion hasta recibir respuesta: `success`, `failed`, `recoverable_failure`, o `cancelled`
- Approvals tienen precedencia sobre hooks (se evaluan primero)

---

## @endpoint /entity_hook/action/{id}

Obtiene detalle de una definicion de entity hook especifica.

### Parametros
- `id` (path, required): UUID de la definicion

### Respuesta
Misma estructura que un elemento de la lista de `/entity_hook/action`.

### Ejemplo
```bash
np-api fetch-api "/entity_hook/action/5c545ae0-bb00-424c-8dcd-d4e64af51ad8"
```

---

## Uso en diagnostico

Los entity hooks son una causa comun de entidades que quedan "stuck" en `pending` o `creating`:

1. Verificar si hay hooks pendientes: `GET /entity_hook?nrn=...&entity_name=scope`
2. Filtrar por `status: "pending"` o `status: "failed"`
3. Revisar `messages[]` para entender por que fallo
4. El `entity_id` indica que entidad esta bloqueada
