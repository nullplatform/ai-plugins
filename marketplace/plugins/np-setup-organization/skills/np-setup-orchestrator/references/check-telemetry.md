# check-telemetry: Verify Telemetry

## Prerequisites

- `check-np` must have passed (requires auth and at least one active scope)
- There must be at least one application with an active scope

## Flow

### 1. Get an active scope for testing

Invoke `/np-api fetch-api "/scope?status=active&limit=10"`

Select the first one that has a non-empty `domain` and `status=active`. If there are no active scopes, warn and skip the check.

### 2. Verify Logs

Invoke `/np-api fetch-api "/telemetry/application/{app_id}/log?type=application&scope={scope_id}&limit=10"`

- If it returns `results` with data → ok
- If it returns empty `results` → warning (may be normal)
- If it returns error → error

### 3. Verify HTTP Metrics

Invoke `/np-api fetch-api "/telemetry/application/{app_id}/metric/http.rpm?scope_id={scope_id}&minutes=60&period=300"`

### 4. Verify System Metrics (CPU)

Invoke `/np-api fetch-api "/telemetry/application/{app_id}/metric/system.cpu_usage_percentage?scope_id={scope_id}&minutes=60&period=300"`

### 5. Verify System Metrics (Memory)

Invoke `/np-api fetch-api "/telemetry/application/{app_id}/metric/system.memory_usage_percentage?scope_id={scope_id}&minutes=60&period=300"`

## Problem Diagnosis

**If logs fail:**
- Verify that the application is running (`kubectl get pods -n nullplatform`)
- Verify that the log-controller is running in `nullplatform-tools`

**If HTTP metrics work but system metrics don't:**
- HTTP metrics come from the Istio sidecar
- System metrics require additional agent configuration
- Verify the telemetry provider configuration in Nullplatform

**If everything fails:**
- Verify agent connectivity to the API
- Review nullplatform-agent logs: `kubectl logs -n nullplatform-tools -l app=nullplatform-agent`

## Recommendation Logic

| Condition | Recommendation |
|-----------|----------------|
| No active scopes | Create scope from the UI |
| Logs error | Verify log-controller and connectivity |
| HTTP metrics warning | Normal if there's no traffic to the endpoint |
| CPU/Memory error | Verify agent telemetry configuration or provider |
| All OK | Telemetry working correctly |
