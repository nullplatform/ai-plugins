# check-telemetry: Verificar Telemetría

## Prerequisitos

- `check-np` debe haber pasado (necesita auth y al menos un scope activo)
- Debe existir al menos una aplicación con un scope activo

## Flujo

### 1. Obtener un scope activo para testear

Invocar `/np-api fetch-api "/scope?status=active&limit=10"`

Seleccionar el primero que tenga `domain` no vacío y `status=active`. Si no hay scopes activos, advertir y saltar el check.

### 2. Verificar Logs

Invocar `/np-api fetch-api "/telemetry/application/{app_id}/log?type=application&scope={scope_id}&limit=10"`

- Si retorna `results` con datos → ok
- Si retorna `results` vacío → warning (puede ser normal)
- Si retorna error → error

### 3. Verificar Métricas HTTP

Invocar `/np-api fetch-api "/telemetry/application/{app_id}/metric/http.rpm?scope_id={scope_id}&minutes=60&period=300"`

### 4. Verificar Métricas de Sistema (CPU)

Invocar `/np-api fetch-api "/telemetry/application/{app_id}/metric/system.cpu_usage_percentage?scope_id={scope_id}&minutes=60&period=300"`

### 5. Verificar Métricas de Sistema (Memoria)

Invocar `/np-api fetch-api "/telemetry/application/{app_id}/metric/system.memory_usage_percentage?scope_id={scope_id}&minutes=60&period=300"`

## Diagnóstico de Problemas

**Si logs fallan:**
- Verificar que la aplicación está corriendo (`kubectl get pods -n nullplatform`)
- Verificar que el log-controller está corriendo en `nullplatform-tools`

**Si métricas HTTP funcionan pero sistema no:**
- Las métricas HTTP vienen del Istio sidecar
- Las métricas de sistema requieren configuración adicional del agente
- Verificar la configuración del provider de telemetría en Nullplatform

**Si todo falla:**
- Verificar conectividad del agente a la API
- Revisar logs del nullplatform-agent: `kubectl logs -n nullplatform-tools -l app=nullplatform-agent`

## Lógica de Recomendaciones

| Condición | Recomendación |
|-----------|---------------|
| Sin scopes activos | Crear scope desde la UI |
| Logs error | Verificar log-controller y conectividad |
| HTTP metrics warning | Normal si no hay tráfico al endpoint |
| CPU/Memory error | Verificar configuración de telemetría del agente o provider |
| Todo OK | Telemetría funcionando correctamente |
