# Nullplatform API - Concepts and Entities

## Main Hierarchy

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
        │     │     │     └── Parameter (env vars per scope)
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
        └── Agent (runtime on client infrastructure)
```

## NRN-associated Entities (any level)

These entities are created at a specific NRN level and cascade to children.
They are not fixed to a hierarchy level.

| Entity | Description | See docs |
|--------|-------------|----------|
| **Dimension** | Variation axes (environment, country, region). Cascade to NRN children | `dimensions.md` |
| **Entity Hook** (Action) | Lifecycle interceptors (before/after create/write/delete) | `entity-hooks.md` |
| **Notification Channel** | Alert destination: Slack, email, webhook, agent | `workflows.md` |
| **NRN Config** | Hierarchical key-value store with inheritance and merge (potentially deprecated) | - |
| **Runtime Configuration** | Reusable environments for scopes (potentially deprecated) | `runtime-configuration.md` |

## Cross-cutting Entities

| Entity | Description |
|--------|-------------|
| **Agent** | Outbound-only runtime on client infrastructure, executes commands via control plane. See `infrastructure.md` |
| **Agent Command** | Remote command executed via control plane (e.g., diagnostic dump) |
| **Template** | Application template (React, Node.js, Java, etc) |
| **Catalog Specification** | Per-entity metadata schema (formerly "Metadata Specification"). See `metadata.md` |
| **Report** | Analytics and compliance reports |
| **User** | Human users and service accounts |
| **API Key** | Programmatic credentials with assigned roles (grants). See `api-keys.md` |

## Microservices and URL Prefixes

The public API (`api.nullplatform.com`) is a gateway that routes to different microservices.
Most endpoints go directly without prefix, but some microservices require a prefix:

| Prefix | Microservice | Endpoints |
|--------|-------------|-----------|
| *(none)* | `api.nullplatform.io` (core) | account, namespace, application, scope, deployment, build, release, template, etc. |
| `/metadata/` | `metadata.nullplatform.io` | metadata_specification, {entity}/{id} (entity metadata) |

**Example**: `np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=..."` reaches `metadata.nullplatform.io/metadata_specification`.

## Key Concepts

### Dimension
Variation axes defined at a **specific NRN level** (not necessarily organization).
Cascade downward to NRN children. The same dimension cannot exist in a parent-child relationship (but can in siblings).
- `environment`: prod, staging, qa, dev
- `country`: us, mx, ar, br
- `compliance`: banxico, pci, hipaa

See `dimensions.md` for endpoints and details.

### Capability
Configurable features per scope:
- `scheduled_stop`: Auto-stop after inactivity (timer in seconds)
- `auto_scaling`: HPA configuration (min, max, cpu threshold)
- `health_check`: K8s probe configuration
- `logs`: Log provider and throttling

### Resource Specification
Resource allocation for containers:
- CPU: in millicores (300m = 0.3 cores)
- Memory: in binary units (512Mi, 1Gi)

### NRN (Nullplatform Resource Name)
Unique hierarchical identifier for any resource:
```
organization=123:account=456:namespace=789:application=101:scope=202
```

**NRN as configuration scope**: Many entities (dimensions, entity hooks, notification
channels, runtime configurations) are created at an NRN level and cascade to children. Children
inherit and can extend (but not duplicate) the parent's configuration.

**NRN as config store** (potentially deprecated): The `/nrn/{nrn_string}` endpoint works
as a hierarchical key-value store with automatic inheritance, JSON object merge, namespaces and
profiles. Recommended to use platform settings/providers instead.

**Wildcards**: Some endpoints support wildcards in NRN (`account=*`) to scan
all children of a level.

### Status Lifecycle

**Scope**: pending → creating → active → updating → stopped → deleted | failed | unhealthy

**Deployment**: pending → provisioning → deploying → finalizing → finalized | rolled_back | canceled | failed

**Build**: pending → running → success | failed | canceled

**Service**: pending → active → updating → deleting | failed

**API Key**: active → revoked

## CLI Usage

```bash
np-api                                  # Shows this entity map
np-api search-endpoint <term>           # Search endpoints by term
np-api describe-endpoint <endpoint>     # Complete endpoint documentation
np-api fetch-api <url>                  # Execute API request
```

### Examples

```bash
np-api search-endpoint deployment       # List all deployment endpoints
np-api describe-endpoint /deployment    # Documentation for GET /deployment
np-api fetch-api "/application/123"
```

## Bootstrap - Discovery from the JWT

The only guaranteed data at startup is the `organization_id`, extracted from the JWT token
(shown by `check-auth`). Accounts, namespaces, or applications may not always exist.

The discovery chain to navigate the hierarchy is:

```
organization_id (from JWT)
  → GET /account?organization_id=<org_id>           → list accounts
    → GET /namespace?account_id=<account_id>         → list namespaces
      → GET /application?namespace_id=<namespace_id> → list applications
```

### Complete Example

```bash
# 1. Get organization_id from token (check-auth shows it)
np-api check-auth
# Output: Organization ID: 1255165411

# 2. List organization accounts
np-api fetch-api "/account?organization_id=1255165411"
# Result: accounts with id, name, slug, status, repository_prefix, nrn

# 3. Choose an account and list its namespaces
np-api fetch-api "/namespace?account_id=95118862&status=active&limit=50"
# Result: namespaces with id, name, slug, status, nrn

# 4. Choose a namespace and list its applications
np-api fetch-api "/application?namespace_id=463208973&status=active&limit=100"
# Result: applications with id, name, slug, status, template_id, repository_url, nrn
```

### Notes
- Each level may have no children (e.g., namespace without applications if we're creating the first one)
- Filter by `status=active` to exclude inactive/archived entities
- All list responses are paginated with `paging` and `results`
- Each entity's `nrn` contains the complete hierarchy up to that level
