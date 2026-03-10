# Infrastructure (Organization, Account, Namespace, Provider, Agent)

Entidades de infraestructura y jerarquía organizacional.

## @endpoint /organization/{id}

Obtiene detalles de una organización.

### Parámetros
- `id` (path, required): ID de la organización

### Respuesta
- `id`: ID numérico
- `name`: Nombre de la organización
- `settings`: Configuración a nivel de org

### Navegación
- **→ accounts**: `/account?organization_id={id}` (si existe filtro)

### Ejemplo
```bash
np-api fetch-api "/organization/549683990"
```

---

## @endpoint /organization

Lista organizaciones.

### Ejemplo
```bash
np-api fetch-api "/organization"
```

---

## @endpoint /account/{id}

Obtiene detalles de un account.

### Parámetros
- `id` (path, required): ID del account

### Respuesta
- `id`: ID numérico
- `name`: Nombre del account
- `slug`: Identificador URL-friendly
- `status`: Estado
- `organization_id`: ID de la organización padre
- `settings`: Configuración (region, tier)
- `created_at`, `updated_at`: Timestamps

### Navegación
- **→ organization**: `organization_id` → `/organization/{organization_id}`
- **→ namespaces**: `/namespace?account_id={id}` (si existe filtro)
- **← organization**: parte del NRN

### Ejemplo
```bash
np-api fetch-api "/account/463975847"
```

---

## @endpoint /account

Lista accounts de una organizacion.

### Parámetros
- `organization_id` (query, required): ID de la organizacion. Se obtiene del JWT token (check-auth lo muestra).
- `status` (query): Filtra por status (active, inactive)
- `limit` (query): Máximo de resultados (default 30)
- `offset` (query): Para paginacion

### Respuesta
```json
{
  "paging": {"total": 8, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 95118862,
      "name": "main",
      "organization_id": 1255165411,
      "repository_prefix": "kwik-e-mart",
      "repository_provider": "github",
      "status": "active",
      "slug": "kwik-e-mart-main",
      "nrn": "organization=1255165411:account=95118862"
    }
  ]
}
```

### Navegacion
- **← organization**: `organization_id` del JWT token
- **→ namespaces**: `/namespace?account_id={id}`

### Ejemplo
```bash
# Listar accounts de la organizacion (organization_id del JWT)
np-api fetch-api "/account?organization_id=1255165411"

# Solo accounts activos
np-api fetch-api "/account?organization_id=1255165411&status=active"
```

### Notas
- Este es el primer paso del bootstrap: JWT → accounts → namespaces → aplicaciones
- `repository_prefix` y `repository_provider` indican donde se crean los repos de las apps
- Respuesta paginada con `paging` y `results`

---

## @endpoint /namespace/{id}

Obtiene detalles de un namespace.

### Parámetros
- `id` (path, required): ID del namespace

### Respuesta
- `id`: ID numérico
- `name`: Nombre del namespace
- `slug`: Identificador URL-friendly
- `status`: Estado
- `account_id`: ID del account padre
- `nrn`: NRN completo
- `configuration`: region, cluster settings
- `metadata`: Propiedades adicionales

### Navegación
- **→ account**: `account_id` → `/account/{account_id}`
- **→ applications**: `/application?namespace_id={id}`

### Ejemplo
```bash
np-api fetch-api "/namespace/476951634"
```

---

## @endpoint /namespace

Lista namespaces de un account.

### Parámetros
- `account_id` (query, required): ID del account. Se obtiene de `GET /account?organization_id=<org_id>`.
- `status` (query): Filtra por status (active, inactive)
- `limit` (query): Máximo de resultados (default 30)
- `offset` (query): Para paginacion

### Respuesta
```json
{
  "paging": {"total": 143, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 463208973,
      "name": "Nullplatform Demos",
      "account_id": 95118862,
      "slug": "nullplatform-demos",
      "status": "active",
      "nrn": "organization=1255165411:account=95118862:namespace=463208973"
    }
  ]
}
```

### Navegacion
- **← account**: `account_id` → `/account/{account_id}`
- **→ applications**: `/application?namespace_id={id}`

### Ejemplo
```bash
# Listar namespaces de un account
np-api fetch-api "/namespace?account_id=95118862&status=active&limit=50"
```

### Notas
- Segundo paso del bootstrap: JWT → accounts → **namespaces** → aplicaciones
- Respuesta paginada con `paging` y `results`
- Un namespace puede no tener aplicaciones (ej: namespace recien creado)

---

## @endpoint /provider

Lista providers (instancias de cloud providers configuradas).

### Parámetros
- `nrn` (query, required): NRN base
- `show_descendants` (query): **snake_case** - incluye providers de jerarquía inferior
- `limit` (query): Máximo de resultados

### Ejemplo
```bash
np-api fetch-api "/provider?nrn=organization=4&show_descendants=true&limit=200"
```

### Notas
- Usar `show_descendants` (**snake_case**) NO `showDescendants`
- Sin `show_descendants=true` solo retorna providers a nivel del NRN especificado

---

## @endpoint /provider_specification

Lista especificaciones de providers disponibles.

### Parámetros
- `nrn` (query): NRN para filtrar

### Dominio
```
https://providers.nullplatform.com/provider_specification?nrn=organization=123
```

### Ejemplo
```bash
np-api fetch-api "https://providers.nullplatform.com/provider_specification?nrn=organization=549683990"
```

---

## @endpoint /controlplane/agent

Lista agents (runtime agents en infraestructura del cliente).

Los agents son servicios ligeros outbound-only que conectan la infraestructura del cliente
con Nullplatform. Se conectan a `agents.nullplatform.com:443` y pollan por tareas que
matcheen sus tags.

### Parámetros
- `organization_id` (query): ID de la organización
- `account_id` (query): ID del account
- `nrn` (query): NRN alternativo (ej: `organization=1:account=2`)

### Respuesta
```json
{
  "results": [
    {
      "id": "uuid",
      "name": "my-agent-name",
      "nrns": ["organization=1255165411:account=95118862"],
      "status": "active",
      "capabilities": [],
      "tags": {"cloud": "aws", "region": "us-east-1"},
      "heartbeat": "2026-02-25T10:00:00Z",
      "version": "1.2.3",
      "channel_selectors": {}
    }
  ]
}
```

### Campos clave
- `id`: UUID del agent
- `name`: Nombre del agent
- `nrns[]`: Array de NRNs donde el agent esta registrado (puede estar en multiples accounts)
- `status`: `active` | otros
- `capabilities`: Capacidades del agent
- `tags`: Tags para routing. Las tareas se rutean al agent cuyas tags matcheen
- `heartbeat`: Ultimo heartbeat — util para verificar si el agent esta vivo
- `version`: Version del agent

### Agent notification channels

Los agents pueden procesar notificaciones de la plataforma ejecutando scripts en la infraestructura
del cliente. Hay dos tipos de canales de notificacion para agents:

| Tipo | Descripcion |
|------|-------------|
| `agent` | Ejecuta un script local en la infraestructura donde corre el agent |
| `http` | Hace un HTTP request a un handler remoto |

Los agent notification channels se configuran en `/notification/channel` con `type: agent` o
`type: http`. El agent polls por notificaciones que matcheen sus tags y las procesa.

### Autenticacion
Los agents requieren una API key con roles `controlplane:agent` y `ops` para registrarse
y autenticarse con el control plane.

### Ejemplo
```bash
# Por organization_id y account_id
np-api fetch-api "/controlplane/agent?organization_id=1255165411&account_id=95118862"

# Por NRN
np-api fetch-api "/controlplane/agent?nrn=organization%3D1255165411%3Aaccount%3D95118862"
```

### Notas
- Agents son outbound-only: se conectan a Nullplatform, no al reves
- Tag-based routing: los agents solo procesan tareas que matcheen sus tags
- Soporta deployment via: Helm, Docker, binary, serverless
- Si un agent no tiene heartbeat reciente, esta caido o desconectado
