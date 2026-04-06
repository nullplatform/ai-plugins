# Scopes

Scopes representan ambientes/targets para deployments (qa, staging, prod).

## @endpoint /scope/{id}

Obtiene detalles de un scope.

### Parámetros
- `id` (path, required): ID del scope

### Respuesta
- `id`: ID numérico
- `name`: Nombre del scope (cambia a `deleted-{timestamp}-{name}` cuando se elimina)
- `status`: active | unhealthy | deleted | failed | updating | stopped | stopping | creating | pending
- `application_id`: ID de la aplicación
- `asset_name`: Nombre del asset asociado (ej: `docker-image-asset`, `lambda-asset`). **CRITICO para deployments**: si es `null`, los deployments fallan con error confuso. Debe setearse antes de desplegar
- `instance_id`: ID del service asociado (**importante para obtener deployment actions**)
- `active_deployment`: ID del deployment activo (**SOLO en GET individual, NO en listados**)
- `current_active_deployment`: ID del deployment activo (igual que active_deployment)
- `nrn`: organization=X:account=Y:namespace=Z
- `provider`: Identificador del tipo de scope. Puede ser:
  - **Legacy (string fijo)**: `AWS:SERVERLESS:LAMBDA`, `AWS:WEB_POOL:EKS`, `AWS:WEB_POOL:EC2INSTANCES`
  - **Nuevo (UUID)**: referencia a un `service_specification` que define el schema de capabilities
- `dimensions`: Clasificación del scope
  - `environment`: dev | qa | staging | prod
  - `country`: us | mx | ar | br
  - `compliance`: banxico | pci | hipaa
- `capabilities`: **depende del provider** - cada service_specification define su propio schema. Ejemplo típico para K8s:
  - `scheduled_stop`: auto-stop config (enabled, timer en segundos)
  - `auto_scaling`: HPA config (min_amount, max_amount, cpu, memory)
  - `health_check`: config de probes
  - `logs`: provider y throttling
  - Schema completo K8s: [nullplatform/scopes](https://github.com/nullplatform/scopes/blob/main/k8s/specs/service-spec.json.tpl)
- `specification.replicas`: Réplicas default
- `specification.resources`: memory, cpu
- `stops_at`: Timestamp de próximo auto-stop (si scheduled_stop habilitado)

### Navegación
- **→ application**: `application_id` → `/application/{application_id}`
- **→ deployments**: `/deployment?scope_id={id}`
- **→ deployment actions**: `instance_id` → `/service/{instance_id}/action`
- **→ instances**: `/telemetry/instance?application_id={app_id}&scope_id={id}`
- **→ namespace**: del NRN extraer namespace_id
- **← application**: `/scope?application_id={application_id}`

### Ejemplo
```bash
np-api fetch-api "/scope/415005828"

# Con mensajes de error (útil para diagnosticar fallos de delete o creación)
np-api fetch-api "/scope/415005828?include_messages=true"
```

### Notas
- **`include_messages=true`**: Incluye el array `messages[]` con errores y eventos del scope. Sin este param, `messages` viene vacío. Útil para diagnosticar scopes en status `failed` (ej: errores de deprovisionamiento como "Error deleting ingress...")
- `instance_id` es clave para obtener deployment actions via `/service/{instance_id}/action`
- Cuando scope es deleted, el name cambia a `deleted-{timestamp}-{original-name}`
- `status: active` NO cambia cuando scope auto-stops - solo métricas muestran 0
- Scopes eliminados no se pueden recuperar - hay que recrear
- **IMPORTANTE**: `active_deployment` y `current_active_deployment` SOLO aparecen en GET individual (`/scope/{id}`), NO en listados (`/scope?application_id=X`)
- **IMPORTANTE**: `asset_name` debe estar seteado para que los deployments funcionen. Si es `null`, `POST /deployment` falla con `"The scope and the release belongs to different applications"`. Setear con `PATCH /scope/{id}` enviando `{"asset_name": "docker-image-asset"}`

---

## @endpoint /scope

Lista scopes de una aplicación.

### Parámetros

- `application_id` (query, required): ID de la aplicación
- `status` (query): Filtra por status (active, deleted, etc.)
- `limit` (query): Máximo de resultados
- `offset` (query): Para paginación

### Respuesta

Objeto paginado:

```json
{
  "paging": {"total": 3, "offset": 0, "limit": 30},
  "results": [
    {"id": 415005828, "name": "qa private", "status": "active", ...}
  ]
}
```

### Ejemplo

```bash
np-api fetch-api "/scope?application_id=489238271"

# Solo scopes activos
np-api fetch-api "/scope?application_id=489238271&status=active"
```

### Notas

- Retorna objeto con `paging` y `results` (como otros endpoints)
- Scopes eliminados pueden NO aparecer en la lista por defecto
- **IMPORTANTE**: El listado NO incluye `active_deployment` - usar GET individual para obtenerlo

---

## Listar scopes por provider

El endpoint `/scope` no soporta filtro por provider. Para listar scopes de toda la organización por provider:

### Método: via /service (type=scope)

Cada scope con provider UUID tiene un service asociado donde `specification_id` = provider.

```bash
# 1. Listar todos los services type=scope de la org
np-api fetch-api "/service?nrn=organization%3D{org_id}:account%3D*&type=scope&limit=1500"

# 2. Filtrar por specification_id (provider UUID)
| jq '[.results[] | select(.specification_id == "480c7522-...") | {name, status, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### Campos útiles del service (type=scope)

- `specification_id`: UUID del provider (service_specification)
- `entity_nrn`: contiene el NRN completo del scope
- `attributes`: equivalente a `capabilities` del scope
- `status`: active | failed | creating | etc

### Ejemplo: encontrar scopes sin ciertas capabilities

```bash
# Comparar attributes de services contra un scope de referencia
jq '[.results[] | select(.specification_id == "UUID") |
  select((.attributes | has("traffic_management")) | not) |
  {name, scope_id: (.entity_nrn | split("scope=")[1])}]'
```

### URL de UI

Para armar la URL de un scope en la UI:
```
https://{organization_slug}.app.nullplatform.io/{entity_nrn}
```

---

## @endpoint /scope_type

Lista los tipos de scope disponibles para una aplicación. Este endpoint reemplaza
el uso de `/service_specification` para descubrir tipos de scope.

### Parámetros

- `nrn` (query, required): NRN URL-encoded de la aplicación (ej: `organization%3D123%3Aaccount%3D456%3Anamespace%3D789%3Aapplication%3D101`)
- `status` (query): Filtrar por status (ej: `active`)
- `include` (query): Campos adicionales a incluir (ej: `capabilities,wildcard,available`)

### Respuesta

Array de scope types:

```json
[
  {
    "id": 123,
    "type": "web_pool_k8s",
    "name": "Kubernetes",
    "description": "Docker containers on pods",
    "provider_type": "null_native",
    "provider_id": "AWS:WEB_POOL:EKS",
    "available": true,
    "parameters": {"schema": {...}}
  }
]
```

### Campos clave

- `id`: ID numérico del tipo
- `type`: Tipo técnico — `web_pool`, `web_pool_k8s`, `serverless`, `custom`
- `name`: Nombre amigable (ej: "Kubernetes", "Scheduled Task", "Server instances")
- `description`: Descripción del tipo
- `provider_type`: `null_native` (tipos built-in) o `service` (tipos custom via service_specification)
- `provider_id`: ID del provider para el POST /scope — puede ser string fijo (`AWS:WEB_POOL:EKS`) o UUID
- `available`: Boolean — indica si el tipo está disponible para la aplicación/account actual
- `parameters.schema`: JSON schema de capabilities (principalmente para tipo `custom`)

### Navegación

- **→ scope creation**: `type` y `provider_id` se usan en POST `/scope`
- **→ capabilities**: `/capability?nrn={nrn}&target=scope` para tipos nativos
- **← application**: filtrar por NRN de la aplicación

### Ejemplo

```bash
# Listar scope types disponibles para una aplicación
np-api fetch-api "/scope_type?nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973%3Aapplication%3D1914258629&status=active&include=capabilities,wildcard,available"
```

### Notas

- **Solo mostrar tipos con `available: true`** al usuario — los demás no están habilitados
- Los tipos varían entre organizaciones/accounts — nunca asumir que existen tipos específicos
- Para tipo `custom`, el `provider_id` es un UUID que referencia un `service_specification`
- Para tipos nativos (`web_pool_k8s`, `serverless`), el `provider_id` es un string fijo
- El campo `type` del scope_type se usa directamente como `type` en el POST `/scope`

---

## @endpoint /capability

Lista las capabilities configurables para un target (scope, deployment, etc.).
Usado para descubrir qué se puede configurar al crear un scope de tipo nativo.

### Parámetros

- `nrn` (query, required): NRN URL-encoded de la aplicación
- `target` (query, required): Target de las capabilities (ej: `scope`)

### Respuesta

Array de capabilities:

```json
[
  {
    "id": 456,
    "slug": "auto_scaling",
    "name": "Auto Scaling",
    "target": "scope",
    "definition": {
      "type": "object",
      "properties": {
        "enabled": {"type": "boolean"},
        "instances": {
          "type": "object",
          "properties": {
            "amount": {"type": "integer"},
            "min_amount": {"type": "integer"},
            "max_amount": {"type": "integer"}
          }
        }
      }
    }
  }
]
```

### Campos clave

- `id`: ID numérico de la capability
- `slug`: Identificador usado como **key en el objeto capabilities** del POST /scope
- `name`: Nombre amigable
- `target`: Target al que aplica (ej: `scope`)
- `definition`: JSON schema que define la estructura del valor de la capability

### Capabilities comunes para scopes K8s

| Slug | Nombre | Descripción |
|------|--------|-------------|
| `visibility` | Visibility | Visibilidad pública/privada (solo al crear) |
| `listener_protocol` | Listener Protocol | Protocolo HTTP/gRPC |
| `memory` | Memory | Memoria en GB |
| `kubernetes_processor` | Kubernetes Processor | CPU en millicores |
| `auto_scaling` | Auto Scaling | HPA: instancias, CPU%, memoria% |
| `health_check` | Health Check | Probes de salud (path, timeout, interval) |
| `logs` | Logs | Provider de logs y throttling |
| `metrics` | Metrics | Providers de métricas |
| `continuous_delivery` | Continuous Delivery | Deploy automático desde branches |
| `scheduled_stop` | Scheduled Stop | Auto-stop después de inactividad |

### Navegación

- **→ scope creation**: `slug` se usa como key en `capabilities` del POST `/scope`
- **→ scope_type**: tipos nativos usan capabilities de este endpoint; tipos `custom` usan `parameters.schema`

### Ejemplo

```bash
# Obtener capabilities para scopes de una aplicación
np-api fetch-api "/capability?nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973%3Aapplication%3D1914258629&target=scope"
```

### Notas

- Las capabilities aplican a tipos **nativos** (`web_pool_k8s`, `serverless`, `web_pool`)
- Para tipos `custom`, las capabilities se definen en `scope_type.parameters.schema`
- El `slug` de cada capability se usa como key en el objeto `capabilities` del POST `/scope`
- Cada capability tiene su propio JSON schema en `definition` que describe la estructura esperada
