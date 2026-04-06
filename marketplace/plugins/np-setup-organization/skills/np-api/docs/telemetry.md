# Telemetry (Logs y Metrics)

Logs y métricas de aplicaciones. Hay dos tipos distintos de logs.

## @endpoint /telemetry/application/{app_id}/log

Obtiene logs de aplicación (stdout/stderr del container).

### Parámetros
- `app_id` (path, required): ID de la aplicación
- `type` (query, required): `application` (requerido)
- `scope` (query, required): ID del scope (numérico, NO `scope_id`)
- `limit` (query): Máximo de resultados (default 50, max 1000)
- `deploy` (query): Filtra por deployment ID
- `instance` (query): Filtra por pod/instance
- `container` (query): Filtra por container name
- `start_time` (query): Inicio del rango (ISO 8601)
- `end_time` (query): Fin del rango (ISO 8601)
- `q` (query): Búsqueda full-text
- `next_page_token` (query): Paginación

### Respuesta
```json
{
  "results": [
    {
      "id": "39346312298110922706803320582238329922042752239624716288",
      "message": "{\"level\":30,\"time\":1764349667314,\"msg\":\"Starting server on port: 8080\"}",
      "date": "2025-11-28T17:07:47.511Z"
    }
  ],
  "next_page_token": "..."
}
```

### Ejemplo
```bash
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&limit=100"

# Con filtro de búsqueda
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&q=error&limit=100"

# Por rango de tiempo
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&start_time=2025-11-28T17:00:00Z&end_time=2025-11-28T18:00:00Z"
```

### Notas
- **Application logs** = stdout/stderr del container (código de aplicación)
- **Deployment messages** (en `/deployment/{id}?include_messages=true`) = eventos K8s
- Usar `scope` (NO `scope_id`) como nombre del parámetro
- `type=application` es requerido

---

## @endpoint /telemetry/application/{app_id}/metric/{metric_name}

Obtiene métricas de una aplicación.

### Parámetros
- `app_id` (path, required): ID de la aplicación
- `metric_name` (path, required): Nombre de la métrica
- `scope_id` (query): ID del scope (numérico)
- `minutes` (query): Ventana de tiempo en minutos
- `start_time` (query): Inicio del rango
- `end_time` (query): Fin del rango
- `period` (query, **recomendado**): Granularidad en segundos (usar 300+)
- `dimensions` (query): Filtros adicionales (ej: `scope_id:123`)

### Métricas Disponibles
- `system.cpu_usage_percentage` - Uso de CPU
- `system.memory_usage_percentage` - Uso de memoria
- `http.rpm` - HTTP requests per minute
- `http.error_rate` - Tasa de errores HTTP
- `http.response_time` - Tiempo de respuesta (puede requerir instrumentación)

### Respuesta
```json
{
  "application_id": 989212014,
  "metric": "system.cpu_usage_percentage",
  "start_time": "2025-11-28T16:55:46Z",
  "end_time": "2025-11-28T17:15:46Z",
  "period_in_seconds": 300,
  "results": [
    {
      "dimensions": {},
      "data": [
        {"value": 2.52, "timestamp": "2025-11-28T17:14:00.000Z"}
      ]
    }
  ]
}
```

### Ejemplo
```bash
np-api fetch-api "/telemetry/application/489238271/metric/system.cpu_usage_percentage?scope_id=415005828&minutes=60&period=300"
```

### Notas
- **Usar `period=300` o mayor** - period=60 puede causar anomalías de CloudWatch
- Respuesta usa `results[].data[]`, NO `datapoints[]`
- Dimensiones usan IDs numéricos, NO slugs (`scope_id:123`, NO `scope:production`)
- `http.response_time` puede retornar vacío si no hay instrumentación adecuada
- Endpoint es `/telemetry/application/...` NO `logs.nullplatform.com` (ese dominio no resuelve)
- Métricas de scopes auto-stopped muestran 0 aunque `status` siga siendo `active`

---

## @endpoint /telemetry/instance

Lista instancias/pods de un scope.

### Parámetros
- `application_id` (query, required): ID de la aplicación
- `scope_id` (query, required): ID del scope

### Respuesta
```json
{
  "results": [
    {
      "instance_id": "main-app-name-scope-name-{scope_id}-d-{deployment_id}{hash}",
      "launch_time": "2026-01-27T08:16:42.000Z",
      "state": "running",
      "spot": false,
      "deployment_id": 123456789,
      "details": {
        "namespace": "nullplatform",
        "ip": "10.x.x.x",
        "dns": "10.x.x.x.nullplatform.pod.cluster.local",
        "cpu": {"requested": 0.2, "limit": 0.8},
        "memory": {"requested": "256Mi", "limit": "384Mi"},
        "architecture": "x86"
      },
      "account": "account-name",
      "account_id": 123,
      "application": "app-name",
      "application_id": 456,
      "namespace": "namespace-name",
      "namespace_id": 789,
      "scope": "scope-name",
      "scope_id": 101112
    }
  ],
  "filters": {"application_id": 456, "scope_id": 101112}
}
```

### Ejemplo
```bash
np-api fetch-api "/telemetry/instance?application_id={app_id}&scope_id={scope_id}"
```

### Notas
- Devuelve todas las instancias/pods corriendo para el scope
- `deployment_id` indica de qué deployment proviene cada instancia
- Útil para verificar si hay instancias de deployments antiguos (stale instances)
- `state` puede ser: running, pending, terminated
- Si no hay instancias, devuelve `results: []`
