# Deployments

Deployments son instancias de releases desplegadas en scopes. Incluyen mensajes de eventos K8s.

## @endpoint /deployment/{id}

Obtiene detalles de un deployment.

### Parámetros
- `id` (path, required): ID del deployment
- `include_messages` (query, **recomendado**): Incluye mensajes de error. Default: false

### Respuesta
- `id`: ID numérico
- `status`: Estados posibles:
  - **En progreso**: `pending` | `provisioning` | `deploying` | `running` | `finalizing`
  - **Finalizados**: `finalized` | `rolled_back` | `cancelled` | `failed`
- `scope_id`: ID del scope
- `application_id`: ID de la aplicación
- `release_id`: ID del release desplegado
- `build_id`: ID del build (puede ser null en deployments sin build)
- `deployment_group_id`: ID del grupo si es parte de deploy multi-scope
- `specification.replicas`: Número de réplicas
- `specification.resources`: memory, cpu
- `status_started_at`: Timestamps de cada fase (provisioning, deploying, finalized, rolled_back)
- `messages[]`: Array de eventos (solo con `include_messages=true`)
  - `level`: INFO | ERROR | WARNING
  - `message`: Texto del evento
  - `timestamp`: Epoch milliseconds

### Navegación
- **→ scope**: `scope_id` → `/scope/{scope_id}`
- **→ application**: `application_id` → `/application/{application_id}`
- **→ release**: `release_id` → `/release/{release_id}`
- **→ build**: `build_id` → `/build/{build_id}`
- **→ deployment actions**: `scope_id` → `/scope/{scope_id}` → `instance_id` → `/service/{instance_id}/action`
- **← scope**: `/deployment?scope_id={scope_id}`

### Ejemplo
```bash
np-api fetch-api "/deployment/1470739357?include_messages=true"
```

### Notas
- **SIEMPRE usar `?include_messages=true`** para troubleshooting
- Sin include_messages, el array messages viene vacío o mínimo
- Timestamps en messages son epoch milliseconds (dividir por 1000)
- BackOff events = container crashes (indicador crítico)
- `status: finalized` NO significa éxito - revisar messages por errores
- Los errores reales de deployment están en `/service/{scope.instance_id}/action`, no en el deployment
- Deployments antiguos (>30 días) pueden tener messages truncados - usar BigQuery audit logs

---

## @endpoint /deployment

Lista deployments con filtros.

### Parámetros
- `scope_id` (query): Filtra por scope
- `application_id` (query): Filtra por aplicación
- `deployment_group_id` (query): Filtra por grupo
- `status` (query): Filtra por status (failed, finalized, running, etc)
- `sort` (query): Ordena resultados (ej: `created_at:desc` para más recientes primero)
- `limit` (query): Máximo de resultados (default 30)
- `offset` (query): Para paginación

### Respuesta
```json
{
  "paging": {"total": 150, "offset": 0, "limit": 30},
  "results": [...]
}
```

### Ejemplo
```bash
np-api fetch-api "/deployment?scope_id={scope_id}&limit=50"
np-api fetch-api "/deployment?application_id={app_id}&status=failed&limit=50"

# Obtener deployments más recientes primero (útil para encontrar deployments en progreso)
np-api fetch-api "/deployment?scope_id={scope_id}&sort=created_at:desc&limit=20"
```

### Notas
- Usar `sort=created_at:desc` para obtener deployments más recientes primero
- Los deployments en progreso (`running`, `deploying`, etc.) son los más recientes
- Para verificar instancias stale, comparar `deployment_id` de instancias vs `active_deployment` del scope

---

## @endpoint /deployment_group

Obtiene detalles de un grupo de deployments (deploys multi-scope).

### Parámetros
- `id` (query, required): ID del grupo - **usa query param, NO path param**
- `application_id` (query, required): ID de la aplicación

### Respuesta
- `id`: ID del grupo
- `status`: PENDING | RUNNING | FINALIZING | FINALIZED | FAILED | CANCELED | CREATING_APPROVAL_DENIED
- `application_id`: ID de la aplicación
- `release_id`: ID del release
- `deployments_amount`: Cantidad de deployments en el grupo

### Navegación
- **→ deployments**: `/deployment?deployment_group_id={id}&application_id={app_id}`

### Ejemplo
```bash
np-api fetch-api "/deployment_group?id=541542807&application_id=30290074"
```

### Notas
- Usa **query parameters** (id, application_id), NO path parameters
- Para ver deployments del grupo: `/deployment?deployment_group_id={id}`
