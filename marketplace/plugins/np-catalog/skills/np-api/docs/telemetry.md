# Telemetry (Logs and Metrics)

Application logs and metrics. There are two distinct types of logs.

## @endpoint /telemetry/application/{app_id}/log

Gets application logs (container stdout/stderr).

### Parameters
- `app_id` (path, required): Application ID
- `type` (query, required): `application` (required)
- `scope` (query, required): Scope ID (numeric, NOT `scope_id`)
- `limit` (query): Maximum results (default 50, max 1000)
- `deploy` (query): Filter by deployment ID
- `instance` (query): Filter by pod/instance
- `container` (query): Filter by container name
- `start_time` (query): Range start (ISO 8601)
- `end_time` (query): Range end (ISO 8601)
- `q` (query): Full-text search
- `next_page_token` (query): Pagination

### Response
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

### Example
```bash
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&limit=100"

# With search filter
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&q=error&limit=100"

# By time range
np-api fetch-api "/telemetry/application/489238271/log?type=application&scope=415005828&start_time=2025-11-28T17:00:00Z&end_time=2025-11-28T18:00:00Z"
```

### Notes
- **Application logs** = container stdout/stderr (application code)
- **Deployment messages** (in `/deployment/{id}?include_messages=true`) = K8s events
- Use `scope` (NOT `scope_id`) as the parameter name
- `type=application` is required

---

## @endpoint /telemetry/application/{app_id}/metric/{metric_name}

Gets application metrics.

### Parameters
- `app_id` (path, required): Application ID
- `metric_name` (path, required): Metric name
- `scope_id` (query): Scope ID (numeric)
- `minutes` (query): Time window in minutes
- `start_time` (query): Range start
- `end_time` (query): Range end
- `period` (query, **recommended**): Granularity in seconds (use 300+)
- `dimensions` (query): Additional filters (e.g., `scope_id:123`)

### Available Metrics
- `system.cpu_usage_percentage` - CPU usage
- `system.memory_usage_percentage` - Memory usage
- `http.rpm` - HTTP requests per minute
- `http.error_rate` - HTTP error rate
- `http.response_time` - Response time (may require instrumentation)

### Response
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

### Example
```bash
np-api fetch-api "/telemetry/application/489238271/metric/system.cpu_usage_percentage?scope_id=415005828&minutes=60&period=300"
```

### Notes
- **Use `period=300` or greater** - period=60 may cause CloudWatch anomalies
- Response uses `results[].data[]`, NOT `datapoints[]`
- Dimensions use numeric IDs, NOT slugs (`scope_id:123`, NOT `scope:production`)
- `http.response_time` may return empty if there's no adequate instrumentation
- Endpoint is `/telemetry/application/...` NOT `logs.nullplatform.com` (that domain doesn't resolve)
- Metrics for auto-stopped scopes show 0 even though `status` remains `active`

---

## @endpoint /telemetry/instance

Lists instances/pods of a scope.

### Parameters
- `application_id` (query, required): Application ID
- `scope_id` (query, required): Scope ID

### Response
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

### Example
```bash
np-api fetch-api "/telemetry/instance?application_id={app_id}&scope_id={scope_id}"
```

### Notes
- Returns all running instances/pods for the scope
- `deployment_id` indicates which deployment each instance comes from
- Useful to verify if there are instances from old deployments (stale instances)
- `state` can be: running, pending, terminated
- If there are no instances, returns `results: []`
