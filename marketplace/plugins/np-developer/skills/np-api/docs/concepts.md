# Nullplatform API - Conceptos y Entidades

## Jerarquía Principal

```
Organization
  └── Account
        ├── Namespace
        │     ├── Application
        │     │     ├── Build → Asset (container image)
        │     │     ├── Release (build + runtime config)
        │     │     ├── Scope (environment: qa/staging/prod)
        │     │     │     ├── Deployment → DeploymentGroup
        │     │     │     │     └── Deployment Action (blue-green steps)
        │     │     │     └── Parameter (env vars por scope)
        │     │     ├── Service Link → Service Link Action
        │     │     ├── Telemetry (Logs, Metrics)
        │     │     └── Catalog/Metadata (tags, schemas)
        │     ├── Service (database, cache, load balancer, etc)
        │     │     ├── Service Specification (template/blueprint)
        │     │     │     ├── Link Specification
        │     │     │     └── Action Specification
        │     │     └── Service Action (provision, update, delete)
        │     └── Approval → Approval Action → Policy
        ├── Provider (AWS, GCP, Azure)
        └── Agent (runtime en infra del cliente)
```

## Entidades asociadas a NRN (cualquier nivel)

Estas entidades se crean a un nivel de NRN especifico y cascadean a hijos.
No estan fijas a un nivel de la jerarquia.

| Entidad | Descripción | Ver docs |
|---------|-------------|----------|
| **Dimension** | Ejes de variación (environment, country, region). Cascadean a hijos del NRN | `dimensions.md` |
| **Entity Hook** (Action) | Interceptores de ciclo de vida (before/after create/write/delete) | `entity-hooks.md` |
| **Notification Channel** | Destino de alertas: Slack, email, webhook, agent | `workflows.md` |
| **NRN Config** | Key-value store jerarquico con herencia y merge (potencialmente deprecado) | - |
| **Runtime Configuration** | Ambientes reutilizables para scopes (potencialmente deprecado) | `runtime-configuration.md` |

## Entidades Transversales

| Entidad | Descripción |
|---------|-------------|
| **Agent** | Runtime outbound-only en infra del cliente, ejecuta comandos via control plane. Ver `infrastructure.md` |
| **Agent Command** | Comando remoto ejecutado via control plane (ej: dump de diagnóstico) |
| **Template** | Plantilla de aplicación (React, Node.js, Java, etc) |
| **Catalog Specification** | Schema de metadata por entidad (antes "Metadata Specification"). Ver `metadata.md` |
| **Report** | Analytics y reportes de compliance |
| **User** | Usuarios humanos y service accounts |
| **API Key** | Credenciales programáticas con roles asignados (grants). Ver `api-keys.md` |

## Microservicios y prefijos de URL

La API publica (`api.nullplatform.com`) es un gateway que rutea a distintos microservicios.
La mayoria de endpoints van directo sin prefijo, pero algunos microservicios requieren prefijo:

| Prefijo | Microservicio | Endpoints |
|---------|---------------|-----------|
| *(ninguno)* | `api.nullplatform.io` (core) | account, namespace, application, scope, deployment, build, release, template, etc. |
| `/metadata/` | `metadata.nullplatform.io` | metadata_specification, {entity}/{id} (metadata de entidades) |

**Ejemplo**: `np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=..."` llega a `metadata.nullplatform.io/metadata_specification`.

## Conceptos Clave

### Dimension
Ejes de variación definidos a un **nivel de NRN especifico** (no necesariamente organización).
Cascadean hacia hijos del NRN. No puede haber la misma dimension en parent Y child (si en siblings).
- `environment`: prod, staging, qa, dev
- `country`: us, mx, ar, br
- `compliance`: banxico, pci, hipaa

Ver `dimensions.md` para endpoints y detalles.

### Capability
Features configurables por scope:
- `scheduled_stop`: Auto-stop después de inactividad (timer en segundos)
- `auto_scaling`: Configuración de HPA (min, max, cpu threshold)
- `health_check`: Configuración de probes K8s
- `logs`: Provider y throttling de logs

### Resource Specification
Asignación de recursos para containers:
- CPU: en millicores (300m = 0.3 cores)
- Memory: en unidades binarias (512Mi, 1Gi)

### NRN (Nullplatform Resource Name)
Identificador jerárquico único de cualquier recurso:
```
organization=123:account=456:namespace=789:application=101:scope=202
```

**NRN como scope de configuracion**: Muchas entidades (dimensions, entity hooks, notification
channels, runtime configurations) se crean a un nivel de NRN y cascadean a hijos. Los hijos
heredan y pueden extender (pero no duplicar) la configuracion del parent.

**NRN como config store** (potencialmente deprecado): El endpoint `/nrn/{nrn_string}` funciona
como key-value store jerarquico con herencia automatica, merge de JSON objects, namespaces y
profiles. Recomendado usar platform settings/providers en su lugar.

**Wildcards**: Algunos endpoints soportan wildcards en NRN (`account=*`) para escanear
todos los hijos de un nivel.

### Status Lifecycle

**Scope**: pending → creating → active → updating → stopped → deleted | failed | unhealthy

**Deployment**: pending → provisioning → deploying → finalizing → finalized | rolled_back | canceled | failed

**Build**: pending → running → success | failed | canceled

**Service**: pending → active → updating → deleting | failed

**API Key**: active → revoked

## Uso del CLI

```bash
np-api                                  # Muestra este mapa de entidades
np-api search-endpoint <term>           # Busca endpoints por término
np-api describe-endpoint <endpoint>     # Documentación completa del endpoint
np-api fetch-api <url>                  # Ejecuta request a la API
```

### Ejemplos

```bash
np-api search-endpoint deployment       # Lista todos los endpoints de deployment
np-api describe-endpoint /deployment    # Documentación de GET /deployment
np-api fetch-api "/application/123"
```

## Bootstrap - Discovery desde el JWT

El unico dato garantizado al inicio es el `organization_id`, que se extrae del JWT token
(lo muestra `check-auth`). No siempre existen accounts, namespaces o aplicaciones previas.

La cadena de discovery para navegar la jerarquia es:

```
organization_id (del JWT)
  → GET /account?organization_id=<org_id>           → lista accounts
    → GET /namespace?account_id=<account_id>         → lista namespaces
      → GET /application?namespace_id=<namespace_id> → lista aplicaciones
```

### Ejemplo completo

```bash
# 1. Obtener organization_id del token (check-auth lo muestra)
np-api check-auth
# Output: Organization ID: 1255165411

# 2. Listar accounts de la organizacion
np-api fetch-api "/account?organization_id=1255165411"
# Resultado: accounts con id, name, slug, status, repository_prefix, nrn

# 3. Elegir un account y listar sus namespaces
np-api fetch-api "/namespace?account_id=95118862&status=active&limit=50"
# Resultado: namespaces con id, name, slug, status, nrn

# 4. Elegir un namespace y listar sus aplicaciones
np-api fetch-api "/application?namespace_id=463208973&status=active&limit=100"
# Resultado: aplicaciones con id, name, slug, status, template_id, repository_url, nrn
```

### Notas
- Cada nivel puede no tener hijos (ej: namespace sin aplicaciones si estamos creando la primera)
- Filtrar por `status=active` para excluir entidades inactivas/archivadas
- Todas las respuestas de lista son paginadas con `paging` y `results`
- El `nrn` de cada entidad contiene la jerarquia completa hasta ese nivel
