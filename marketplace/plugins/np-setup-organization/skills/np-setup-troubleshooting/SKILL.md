---
name: np-setup-troubleshooting
description: This skill should be used when the user asks "why did my scope fail", "why is my application broken", "diagnose setup failure", "troubleshoot permissions", "fix telemetry", or needs to diagnose why nullplatform entities (scopes, applications, telemetry, permissions) failed during setup.
---

# Nullplatform Setup Troubleshooting

Skill para diagnosticar por qué fallaron entidades en Nullplatform.

## Comandos Disponibles

| Comando | Propósito |
|---------|-----------|
| `/np-setup-troubleshooting scope <id>` | Diagnosticar por qué falló un scope |
| `/np-setup-troubleshooting app <id>` | Diagnosticar por qué falló una aplicación |

---

## Comando: scope <id>

Diagnostica por qué un scope está en estado `failed`.

### Flujo

1. **Obtener el scope**:
   - Invocar `/np-api fetch-api "/scope/{id}"`
   - Extraer `instance_id` de la respuesta

2. **Listar actions del service**:
   - Invocar `/np-api fetch-api "/service/{instance_id}/action"`
   - Buscar actions con `status: failed`

3. **Para cada action fallida**:
   - Invocar `/np-api fetch-api "/service/{instance_id}/action/{action_id}?include_messages=true"`
   - Extraer los mensajes de error

4. **Generar reporte**:
   - Resumir los errores encontrados
   - Interpretar los mensajes técnicos
   - Sugerir posibles soluciones

### Ejemplo de uso

```
Usuario: El scope 1019650520 está en failed, ¿por qué?

Claude: Usaré /np-setup-troubleshooting scope 1019650520 para diagnosticar.
```

### Errores comunes

| Error | Causa probable | Solución |
|-------|----------------|----------|
| "You're not authorized to perform this operation" | API key sin permisos | Ver **Diagnóstico de Permisos** abajo |
| "Timeout waiting for ingress reconciliation" | Problemas de networking K8s | Revisar configuración de ingress y certificados |
| "ECR repository not found" | Falta ECR o permisos | Ejecutar `/np-infrastructure-wizard` |
| "Unsupported DNS type 'aws'" | `dns_type` incorrecto en terraform.tfvars | Ver **Diagnóstico de dns_type** abajo |

### Diagnóstico de Permisos (para "not authorized")

Cuando el error contiene "not authorized", ejecutar diagnóstico extendido de API keys:

#### Flujo Adicional

1. **Identificar el notification channel del scope**:
   - Del scope fallido, obtener el `nrn`
   - Invocar `/np-api fetch-api "https://notifications.nullplatform.com/notification/channel?nrn={nrn}&showDescendants=true"`
   - Buscar canales de tipo `agent`

2. **Obtener la API key del canal**:
   - Invocar `/np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"`
   - El nombre de la API key está en `configuration.agent.api_key` (parcialmente visible)
   - Buscar la API key completa: `/np-api fetch-api "/api-key?name={nombre_api_key}"`

3. **Comparar roles de la API key**:
   - Invocar `/np-api fetch-api "/api-key/{api_key_id}"`
   - Extraer `grants[].role_slug`
   - Verificar contra roles requeridos

4. **Generar reporte de permisos**:

   | Rol | Requerido | Presente |
   |-----|-----------|----------|
   | `controlplane:agent` | Sí | ✓/✗ |
   | `ops` | Sí | ✓/✗ |

#### Roles Requeridos para Notification Channels

| Rol | Propósito |
|-----|-----------|
| `controlplane:agent` | Comunicación con el control plane |
| `ops` | Ejecutar comandos en el agente |

#### Causa Raíz Común

Si falta el rol `ops`, el problema está en el módulo Terraform `scope_definition_agent_association`.

**Archivo problemático:** `nullplatform/scope_definition_agent_association/auth.tf`

```hcl
# INCORRECTO - solo tiene controlplane:agent
resource "nullplatform_api_key" "nullplatform_agent_api_key" {
  grants {
    role_slug = "controlplane:agent"
  }
}

# CORRECTO - necesita también ops
resource "nullplatform_api_key" "nullplatform_agent_api_key" {
  grants {
    role_slug = "controlplane:agent"
  }
  grants {
    role_slug = "ops"
  }
}
```

**Solución:** Actualizar el módulo y re-aplicar bindings con `tofu apply`

---

### Diagnostico de Error 404 (Istio vs ALB mismatch)

Cuando el scope despliega correctamente pero el servicio retorna 404 desde `istio-envoy`.

#### Sintoma

- DNS resuelve correctamente
- Certificado TLS valido
- Pod corriendo
- Pero curl retorna: `upstream connect error` o 404 desde istio-envoy

#### Flujo de Diagnostico

1. **Verificar arquitectura de LB**:

```bash
# Si retorna algo → Istio activo
kubectl get svc -n istio-system istio-ingressgateway
```

2. **Verificar recursos creados por agent**:

```bash
kubectl get httproute -A -l scope_id={scope_id}
kubectl get ingress -A -l scope_id={scope_id}
```

3. **Verificar configuracion del agent**:

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent \
  -o jsonpath='{.data.INITIAL_INGRESS_PATH}' | base64 -d
```

- Si contiene "istio" → Configurado para Istio (HTTPRoute)
- Si vacio → Configurado para ALB (Ingress)

4. **Generar tabla de mismatch**:

| Componente | Detectado | Esperado |
|------------|-----------|----------|
| Load Balancer | NLB (Istio) / ALB | - |
| Recursos creados | HTTPRoute / Ingress | - |
| Config agent | Istio / ALB | Debe coincidir con LB |

#### Causa Raiz

| DNS apunta a | Agent crea | Resultado |
|--------------|------------|-----------|
| NLB (Istio) | HTTPRoute | OK |
| NLB (Istio) | Ingress | **404** |
| ALB | Ingress | OK |
| ALB | HTTPRoute | No routing |

#### Solucion

Si hay mismatch, actualizar `infrastructure/aws/main.tf`:

**Para Istio** (si tienes NLB/Istio Gateway):

```hcl
module "agent" {
  # Agregar estas lineas:
  initial_ingress_path    = "$SERVICE_PATH/deployment/templates/istio/initial-httproute.yaml.tpl"
  blue_green_ingress_path = "$SERVICE_PATH/deployment/templates/istio/blue-green-httproute.yaml.tpl"
}
```

Y en terraform.tfvars:

```hcl
resources = ["service", "istio-gateway"]
```

**Para ALB** (si tienes ALB):

```hcl
module "agent" {
  # NO incluir initial_ingress_path ni blue_green_ingress_path
}
```

Y en terraform.tfvars:

```hcl
resources = ["ingress", "service"]
```

Luego:

1. `tofu apply`
2. `kubectl rollout restart deployment -n nullplatform-tools nullplatform-agent-nullplatform-agent`
3. Eliminar recursos viejos: `kubectl delete ingress -n nullplatform -l scope_id={id}` o `kubectl delete httproute...`
4. Redesplegar scope desde UI de Nullplatform

Ver documentacion completa: `infrastructure/aws/ISTIO_VS_ALB.md`

---

### Diagnostico de dns_type (para "Unsupported DNS type")

Cuando el error contiene "Unsupported DNS type", el valor de `dns_type` en terraform.tfvars no es válido.

#### Valores válidos por cloud

| Cloud | dns_type correcto | Incorrecto |
| ----- | ----------------- | ---------- |
| AWS   | `route53`         | `aws`      |
| Azure | `azure`           | -          |
| GCP   | `gcp`             | -          |

#### Flujo de diagnóstico

1. **Verificar valor en K8s:**

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d
```

2. **Verificar valor en terraform.tfvars:**

```bash
grep dns_type infrastructure/aws/terraform.tfvars
```

3. **Si no coinciden con la tabla** → Corregir tfvars:

```hcl
# Incorrecto
dns_type = "aws"

# Correcto
dns_type = "route53"
```

4. **Aplicar cambios:**

```bash
cd infrastructure/aws && tofu apply
```

5. **Verificar que el agente tomó el cambio:**

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d
# Debe mostrar: route53
```

---

## Comando: app <id>

Diagnostica por qué una aplicación está en estado `failed`.

### Flujo

1. **Obtener la aplicación**:
   - Invocar `/np-api fetch-api "/application/{id}"`
   - Revisar status y mensajes

2. **Revisar builds fallidos**:
   - Invocar `/np-api fetch-api "/build?application_id={id}&status=failed&limit=5"`
   - Para cada build fallido, revisar `error_message`

3. **Revisar scopes fallidos**:
   - Invocar `/np-api fetch-api "/scope?application_id={id}"`
   - Para cada scope en `failed`, ejecutar diagnóstico de scope

4. **Generar reporte**:
   - Consolidar errores de builds y scopes
   - Identificar el problema raíz

---

## Diagnóstico de Telemetría (Logs y Métricas via API)

Cuando la API de telemetría de Nullplatform (`/telemetry/application/{id}/log` o `/telemetry/application/{id}/metric/{name}`) no funciona.

### Síntomas

| Error | Recurso | Causa |
|-------|---------|-------|
| `"Keys not present for NRN"` | Logs | No hay `global.logProvider` configurado |
| `"Oops.. there was an internal error"` | Métricas | telemetry-api no puede conectar a Prometheus interno |

### Flujo de Diagnóstico

#### 1. Verificar configuración del NRN

```bash
np-api fetch-api "/nrn/organization={org_id}:account={account_id}?ids=global.logProvider,global.metricsProvider"
```

**Respuesta esperada:**
```json
{
  "namespaces": {
    "global": {
      "logProvider": "external",
      "metricsProvider": "externalmetrics"
    }
  }
}
```

**Si `logProvider` no existe:** El default es `cloudwatchlogs`, que falla si no hay CloudWatch configurado.

**Si `metricsProvider` es `prometheusmetrics`:** Fallará porque telemetry-api no puede conectarse a Prometheus interno del cluster.

#### 2. Para scopes de Service Specifications (containers-default, etc.)

Los scopes creados por service specifications tienen un problema conocido:

- El provider `k8slogs` existe en telemetry-api pero **NO soporta** scopes de service specifications
- El código espera `scope.provider = "AWS:WEB_POOL:EKS"` pero recibe el UUID del service specification
- Ver código: `telemetry-api/services/providers/commons/k8s_commons.js:20-31`

### Solución para Logs: Usar Provider "external"

El provider `external` delega la obtención de logs al agente via notification channel.

#### Fix Inmediato (via API)

```bash
# 1. Obtener token desde secrets.tfvars
NP_KEY=$(grep 'np_api_key' secrets.tfvars | sed 's/.*= *"\(.*\)"/\1/')
TOKEN=$(curl -s -X POST "https://api.nullplatform.com/token" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$NP_KEY\"}" | jq -r '.access_token')

# 2. Configurar logProvider como external
curl -X PATCH "https://api.nullplatform.com/nrn/organization={org_id}:account={account_id}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"global.logProvider": "external"}'
```

#### Verificar que funciona

```bash
# Debe retornar logs del scope
np-api fetch-api "/telemetry/application/{app_id}/log?type=application&scope={scope_id}&limit=5"
```

### Solución para Métricas: Usar Provider "externalmetrics"

El provider `externalmetrics` delega la obtención de métricas al agente via notification channel.

**Causa raíz del problema:** El provider `prometheusmetrics` intenta conectarse directamente a Prometheus usando la URL configurada (`prometheus.url`), pero esta URL es interna del cluster y no es accesible desde telemetry-api.

#### Fix Inmediato (via API)

```bash
# 1. Obtener token desde secrets.tfvars
NP_KEY=$(grep 'np_api_key' secrets.tfvars | sed 's/.*= *"\(.*\)"/\1/')
TOKEN=$(curl -s -X POST "https://api.nullplatform.com/token" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$NP_KEY\"}" | jq -r '.access_token')

# 2. Configurar metricsProvider como externalmetrics
curl -X PATCH "https://api.nullplatform.com/nrn/organization={org_id}:account={account_id}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"global.metricsProvider": "externalmetrics"}'
```

#### Verificar que funciona

```bash
# Debe retornar métricas del scope
np-api fetch-api "/telemetry/application/{app_id}/metric/http.rpm?scope_id={scope_id}&minutes=30&period=300"
```

**Nota:** El provider Prometheus sigue siendo necesario para configurar `prometheus.url` que el agente usa internamente.

### Estado Actual y Pendientes

| Recurso | Provider | Estado | Notas |
|---------|----------|--------|-------|
| Logs | `external` | ✅ Funciona | Delega al agente via notification channel |
| Métricas | `externalmetrics` | ✅ Funciona | Delega al agente via notification channel |

### PENDIENTE: Solución Permanente (Equipo Nullplatform)

**Problema:** No existen provider specifications para configurar `global.logProvider` y `global.metricsProvider` via OpenTofu.

**Propuesta:** Crear provider specifications para logs y métricas:

```json
{
  "name": "Agent Logs (K8s)",
  "slug": "agent-logs-configuration",
  "icon": "mdi:kubernetes",
  "description": "Delegates log retrieval to the Nullplatform agent for K8s-based services",
  "visible_to": ["organization=*"],
  "schema": {
    "type": "object",
    "properties": {
      "log_provider": {
        "type": "string",
        "const": "external",
        "default": "external",
        "visible": false
      }
    }
  },
  "mapping": {
    "log_provider": "global.logProvider"
  },
  "categories": [{"slug": "logs"}]
}
```

**Beneficios:**
1. Configuración via OpenTofu (no requiere PATCH manual al NRN)
2. Consistente con el patrón del provider Prometheus
3. No requiere cambios en telemetry-api

**Referencias:**
- Prometheus provider spec: `/provider_specification/e88cbbd3-7df9-4985-9210-a075420b619e`
- Código del provider external: `telemetry-api/services/providers/logs/external_log_service.js`
- Entrypoint del agente: `scopes/entrypoint:66-67` (maneja `log:read`)

### Archivos de Referencia

| Archivo | Propósito |
|---------|-----------|
| `telemetry-api/services/nrn_service.js:220-253` | `getLogProvider()` - determina qué provider usar |
| `telemetry-api/services/nrn_service.js:9` | `DEFAULT_LOG_PROVIDER = "cloudwatchlogs"` |
| `telemetry-api/services/providers/commons/k8s_commons.js:20-31` | Switch que falla con service specs |
| `scopes/entrypoint:66-67` | Agente maneja `log:read` action |

---

## Notas importantes

- **SIEMPRE usar `include_messages=true`** al consultar actions - sin este parámetro los mensajes vienen vacíos
- El campo `instance_id` del scope es el UUID del service que contiene las actions
- Los errores de creación de scope están en `/service/{instance_id}/action`, NO en el scope directamente
- Este skill usa `/np-api` de forma declarativa - no conoce detalles de implementación

---

## Flujo Visual de Diagnóstico

```
Scope failed
    │
    ▼
GET /scope/{id} → extraer instance_id
    │
    ▼
GET /service/{instance_id}/action
    │
    ▼
GET action con ?include_messages=true
    │
    ▼
Analizar error en logs
    │
    ├─► "not authorized" → Diagnóstico de Permisos
    ├─► "Unsupported DNS type" → Diagnóstico de dns_type
    ├─► "ECR repository not found" → /np-infrastructure-wizard
    └─► Otro error → Revisar K8s y Terraform
```
