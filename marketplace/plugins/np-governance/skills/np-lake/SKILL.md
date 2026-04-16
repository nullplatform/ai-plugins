---
name: np-lake
description: Query nullplatform Customer Lake. Use for cross-entity relationship queries, bulk entity state analysis, approval workflow investigation, parameter configuration audit, auth/RBAC audits, service & link inventory, and complex SQL queries across 62 tables in 8 domains (Approvals, Audit, Auth, Core Entities, Governance, Parameters, SCM, Services). Use when users need current state of multiple entities, joins across tables, or analytical queries. PREFERRED over individual API calls for data retrieval — a single SQL query replaces multiple API requests.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/*.sh)
---

# Nullplatform Data Lake (Customer Lake)

Skill to query the nullplatform data lake hosted on Customer Lake.

**This is the preferred method for fetching data.** A single SQL query can retrieve and join information that would require multiple API calls. Use this skill first; fall back to the REST API only for write operations or when the lake is unavailable.

## Prerequisites

### Authentication

Authentication uses the nullplatform user token as `Authorization: Bearer <token>`. The API resolves the organization automatically from the token.

**BEFORE using any other script in this skill, ALWAYS run first:**

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/check_ch_auth.sh
```

If the script fails (exit code 1), **DO NOT stop**. Use `AskUserQuestion` to offer the user to configure authentication:

| Option | Label | Description |
|--------|-------|-------------|
| 1 | I have the token | I can provide my nullplatform token |
| 2 | Skip Data Lake | Continue without data lake |

**Based on the response:**

- **Option 1 (token)**: Ask whether they have an API key or a personal token. Configure `export NP_API_KEY="<key>"` (preferred) or `export NP_TOKEN="<token>"`. Re-run `check_ch_auth.sh` to confirm.
- **Option 2 (skip)**: Inform the user that the data lake will not be available and continue using the REST API as fallback.

Authentication is delegated to the `np-api` skill. Token lookup priority (handled by np-api):

1. `NP_API_KEY` environment variable (recommended — exchanged for a JWT and cached in `~/.claude/`)
2. `NP_TOKEN` environment variable (personal JWT, ~24h expiry)

## Organization Filter (Server-Side)

**The organization filter is automatic.** The API resolves the organization from the Bearer token and filters results server-side.

**You don't need to add `WHERE organization_id = ...`** in your queries. The server handles it.

## Handling Permissions and Empty Results

The user's token determines what data they can access. Handle these scenarios:

### Empty results (no rows returned)

This is **normal** and can mean:
- The entity doesn't exist
- The user doesn't have permission to see those resources
- The filter criteria don't match anything

**DO NOT assume an error.** Present it naturally:

> "I didn't find any [entities] matching that criteria. This could mean they don't exist yet, or your account may not have visibility into those resources."

### HTTP 401/403 errors

The user's token is invalid or lacks permissions for the lake:

> "I can't access the data lake with your current credentials. You can check this directly from the nullplatform dashboard."

**DO NOT retry more than once.** Fall back to the REST API if available.

### Partial visibility

The user may see some entities but not others (e.g., they have access to one account but not another). **Never tell the user they are missing data they can't see.** Only present what the query returns.

## Detailed Documentation

| Document | Content |
|----------|---------|
| [docs/SCHEMA.md](docs/SCHEMA.md) | Full schema for all 62 tables, organized by domain |
| [docs/QUERY_COOKBOOK.md](docs/QUERY_COOKBOOK.md) | Pre-built queries by use case |
| [docs/SQL_GUIDE.md](docs/SQL_GUIDE.md) | SQL tips, formats, date functions, and performance best practices |

## Inspecting Table Schemas (DO THIS BEFORE QUERYING UNFAMILIAR COLUMNS)

`ch_query.sh` accepts read-only introspection statements as well as SELECT: `DESCRIBE` (alias `DESC`), `SHOW`, and `EXPLAIN`. Use them before writing a query whose columns you don't know for sure — do NOT guess field names from the table name, since the static schema in this skill can drift from the live lake.

| Goal | Command |
|------|---------|
| List all tables in the lake | `ch_query.sh --format tsv "SHOW TABLES FROM customers_lake"` |
| Inspect columns + types of a table | `ch_query.sh --format pretty "DESCRIBE TABLE customers_lake.core_entities_scope"` |
| Alternate — machine-readable columns | `ch_query.sh "SELECT name, type FROM system.columns WHERE database='customers_lake' AND table='core_entities_scope'"` |
| See the CREATE TABLE of a table | `ch_query.sh --format pretty "SHOW CREATE TABLE customers_lake.core_entities_scope"` |
| Explain a query plan | `ch_query.sh --format pretty "EXPLAIN SELECT count() FROM core_entities_scope"` |

**Rule:** if you're about to filter, project, or JOIN on a column that isn't listed in the Quick Reference below, `DESCRIBE` the table first. This is cheap (one round-trip) and avoids inventing fields that don't exist.

## Domains and Main Tables (Quick Reference)

### Approvals (18 tables)
| Table | Description |
|-------|-------------|
| `approvals_approval_action` | Approval actions (entity, action, on_policy_success/fail) |
| `approvals_approval_action_policy` | Relation: action <-> policy |
| `approvals_approval_policy` | Approval policies (entity, action, status) |
| `approvals_approval_policy_notification` | Policy notifications |
| `approvals_approval_policy_spec` | Relation: policy <-> spec |
| `approvals_approval_reply` | Replies to approval requests |
| `approvals_approval_request` | Approval requests (status, context, policy_context) |
| `approvals_approval_spec` | Approval specifications |
| `approvals_approval_spec_value` | Spec values with rules |
| `approvals_entity_hook_action` | Entity hook actions |
| `approvals_entity_hook_action_policy` | Relation: hook action <-> policy |
| `approvals_entity_hook_http_request` | Hook HTTP requests |
| `approvals_entity_hook_http_response` | Hook HTTP responses |
| `approvals_entity_hook_policy` | Hook policies |
| `approvals_entity_hook_policy_value` | Hook policy values |
| `approvals_entity_hook_request` | Hook requests |
| `approvals_policy` | Named policies with slug |
| `approvals_policy_value` | Policy values with conditions |

### Audit (1 table)
| Table | Description |
|-------|-------------|
| `audit_events` | Audit events with native JSON columns (NO `_deleted` column) |

### Auth (5 tables)
| Table | ID Column | Description |
|-------|-----------|-------------|
| `auth_user` | `id` | Users (email, first_name, last_name, status, user_type, provider, avatar, organization_id) |
| `auth_role` | `id` | Roles (name, slug, description, level, assignment_restriction, organization_id) |
| `auth_resource_grants` | `id` | User ↔ role grants scoped by `nrn`. Flat table, needs joins to enrich. |
| `auth_resource_grants_expanded` | `id` | **VIEW** over `auth_resource_grants` ⨝ `auth_role`. Pre-joined with `role_name`, `role_slug`, `role_level`. **NO `_version`, `_deleted`, `_synced_at`** — don't use `FINAL` or `WHERE _deleted = 0`. |
| `auth_apikey` | `id` | API keys (name, masked_api_key, roles, owner_id, user_id, account_id, organization_id, used_at, internal, status, tags) |

### Core Entities (22 tables)
| Table | ID Column | Name Column | Description |
|-------|-----------|-------------|-------------|
| `core_entities_organization` | `org_id` | `org_name` | Organizations |
| `core_entities_account` | `account_id` | `account_name` | Accounts |
| `core_entities_namespace` | `namespace_id` | `namespace_name` | Namespaces |
| `core_entities_application` | `app_id` | `app_name` | Applications |
| `core_entities_scope` | `id` | `name` | Scopes (environments) |
| `core_entities_build` | `id` | — | Code builds (FK: `app_id`) |
| `core_entities_release` | `id` | — | Releases (`semver`, FK: `app_id`) |
| `core_entities_deployment` | `id` | — | Deployments (**NO `application_id`**, use `nrn`) |
| `core_entities_deployment_group` | `id` | — | Deployment groups |
| `core_entities_asset` | `id` | `name` | Build assets (docker images) |
| `core_entities_deployment_strategy` | `id` | `name` | Deployment strategies |
| `core_entities_deployment_strategy_scope_type` | `id` | — | Strategy <-> scope type |
| `core_entities_metadata` | `id` (UUID) | — | Entity metadata |
| `core_entities_runtime_configuration` | `id` | — | Runtime configurations |
| `core_entities_runtime_configuration_dimension` | `id` | `name` | RC dimensions |
| `core_entities_runtime_configuration_dimension_value` | `id` | `name` | RC dimension values |
| `core_entities_runtime_configuration_scope` | `id` | — | RC <-> scope relation |
| `core_entities_runtime_configuration_values` | `id` | — | RC values |
| `core_entities_scope_dimension` | `id` | — | Scope dimensions |
| `core_entities_scope_domain` | `id` (UUID) | `domain` | Custom domains |
| `core_entities_scope_type` | `id` | `name` | Scope types |
| `core_entities_technology_template` | `template_id` | `name` | Technology templates |

### Parameters (3 tables)
| Table | Description |
|-------|-------------|
| `parameters_parameter` | Parameter definitions (name, type, secret, handle) |
| `parameters_parameter_value` | Parameter values (FK: parameter_id, parameter_version) |
| `parameters_parameter_version` | Parameter versions (FK: parameter_id, user_id) |

### Governance (4 tables)
| Table | Description |
|-------|-------------|
| `governance_action_items_action_items` | Action items (cost optimization, security, etc.) |
| `governance_action_items_categories` | Action item categories |
| `governance_action_items_suggestions` | AI-generated suggestions for action items |
| `governance_action_items_units` | Measurement units (USD, etc.) |

### SCM (2 tables)
| Table | Description |
|-------|-------------|
| `scm_code_commits` | Git commits (NO `_deleted` column) |
| `scm_code_repositories` | Code repositories (NO `_deleted` column) |

### Services (7 tables)
| Table | ID Column | Description |
|-------|-----------|-------------|
| `services_services` | `id` (UUID) | Service instances (name, slug, status, type, specification_id, desired_specification_id, entity_nrn, attributes, selectors, dimensions, linkable_to, messages) |
| `services_service_specifications` | `id` (UUID) | Service templates (name, slug, type, attributes, selectors, visible_to, dimensions, assignable_to, scopes, use_default_actions) |
| `services_links` | `id` (UUID) | Service ↔ entity bindings (service_id, specification_id, desired_specification_id, entity_nrn, status, attributes, selectors, dimensions, messages) |
| `services_link_specifications` | `id` (UUID) | Link templates (name, slug, specification_id, attributes, selectors, dimensions, visible_to, assignable_to, scopes, unique, use_default_actions, external) |
| `services_actions` | `id` (UUID) | Service / link action invocations (name, slug, status, service_id, link_id, specification_id, desired_specification_id, parameters, results, is_test, created_by) |
| `services_action_specifications` | `id` (UUID) | Action templates (name, slug, type, service_specification_id, link_specification_id, parameters, results, retryable, parallelize, enabled_when, icon, annotations, external) |
| `services_parameters` | `id` (UUID) | Parameter mappings for services / links (entity_nrn, service_id, type, target, parameter_id) |

Services tables have **both** `_deleted` (sync-level soft delete, use `WHERE _deleted = 0`) and a separate `deleted_at` (nullable DateTime, app-level logical delete). Filter on both if you need a strict "truly live" view.

## Available Scripts

| Script | Purpose | Example |
|--------|---------|---------|
| `./scripts/check_ch_auth.sh` | **Validate auth (RUN FIRST)** | `${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/check_ch_auth.sh` |
| `./scripts/ch_query.sh` | Execute Customer Lake queries | `${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh "SELECT ..."` |

### Parameterized Queries

Use `{name:Type}` placeholders in your SQL and pass values with `--param name=value`. The API receives them as `?param_name=value` in the URL, which ClickHouse interpolates server-side (safe from SQL injection).

```bash
# Single parameter
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh \
  --param entity=deployment \
  "SELECT count() as total FROM audit_events WHERE entity = {entity:String}"

# Multiple parameters
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh \
  --param entity=deployment \
  --param status=active \
  "SELECT count() as total FROM audit_events WHERE entity = {entity:String} AND status = {status:String}"
```

**Supported types**: All ClickHouse types are valid — `String`, `Int64`, `UInt64`, `Float64`, `Date`, `DateTime`, `DateTime64(3)`, `Array(String)`, `Nullable(Int32)`, `LowCardinality(String)`, etc.

**Validation**: The script detects all `{name:Type}` placeholders in the query and fails with a clear error if any `--param` flag is missing. If a query has no placeholders, `--param` flags are not required.

## Database & Schema Overview

| Field | Value |
|-------|-------|
| Database | `customers_lake` |
| Tables | 62 tables in 8 domains |
| Engine | Customer Lake (HTTP interface) |

### Common Columns Across All Tables

| Column | Type | Description |
|--------|------|-------------|
| `nrn` | String | Nullplatform Resource Name - unique hierarchical identifier |
| `_version` | UInt64 | Record version (for change tracking) |
| `_deleted` | UInt8 | Soft-delete flag (0 = active, 1 = deleted) |
| `_synced_at` | DateTime | Last sync timestamp to the data lake |

### Critical Query Rules

1. **ALWAYS use `WHERE _deleted = 0`** — Exclude soft-deleted records. **Exceptions:** `audit_events`, `scm_code_commits`, `scm_code_repositories`, and the view `auth_resource_grants_expanded` don't have this column.
2. **ALWAYS use `LIMIT`** — For exploratory queries, cap results
3. **Avoid `SELECT *`** — Select only needed columns
4. **Organization filter is automatic** — Never add `WHERE organization_id = ...`
5. **Column names vary by table** — `app_id`/`app_name` (applications), `account_id`/`account_name` (accounts), `namespace_id`/`namespace_name` (namespaces), `org_id`/`org_name` (organizations). Other tables use `id`/`name`.
6. **Deployment has NO `application_id`** — Use `nrn LIKE '%application={app_id}%'` to filter by app, or query separately and correlate.
7. **JOINs require `AS alias FINAL` syntax** — Use `table AS alias FINAL` (alias BEFORE `FINAL`). `FINAL` deduplicates `ReplacingMergeTree` rows. Example: `FROM core_entities_deployment AS d FINAL JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id`

### User Filtering (My Resources)

The user's ID is embedded in the JWT token's `cognito:groups` claim: `@nullplatform/user=XXXXX`. Extract this ID to filter `created_by` or `updated_by` columns:

```sql
-- My deployments
SELECT id, status, created_at, nrn
FROM core_entities_deployment
WHERE _deleted = 0 AND created_by = {user_id}
ORDER BY created_at DESC LIMIT 10
```

### NRN (Nullplatform Resource Name)

Hierarchical format: `organization=123:account=456:namespace=789:application=012:scope=345`

Filter by hierarchy prefix:
```sql
WHERE nrn LIKE 'organization=123:account=456:namespace=789:application=012%'
```

### JSON Columns (audit_events)

The `request_body` and `response_body` columns support native JSON dot notation:
```sql
SELECT entity, url, status, date, request_body.additional_data
FROM audit_events
WHERE entity = 'deployment'
ORDER BY date DESC
LIMIT 10
```

## Data Lake Boundaries (What's NOT in the Lake)

The data lake contains entity **state** but NOT all **configuration details**. For the following data, you must fall back to the REST API:

| Data | Lake has | API required |
|------|----------|-------------|
| Cloud provider type | `core_entities_scope.provider` (e.g., `AWS:WEB_POOL:EKS`) | Full provider config |
| Region | NO | `GET /provider?nrn=organization={org_id}&show_descendants=true` -> `GET /runtime_configuration/{data_source.key}` -> `values.{cloud}.region` |
| Provider credentials/config | NO | `GET /runtime_configuration/{id}` -> nested values |
| Cluster details (ID, namespace) | NO | `GET /runtime_configuration/{id}` -> `values.k8s.*` |
| Networking config (VPC, subnets) | NO | `GET /runtime_configuration/{id}` -> `values.aws.*` |

### Cloud/Region Workflow

When a user asks "what cloud/region are my scopes in":

1. **Lake**: Identify cloud types
   ```sql
   SELECT provider, count() AS cnt
   FROM core_entities_scope FINAL
   WHERE _deleted = 0
   GROUP BY provider
   ORDER BY cnt DESC
   LIMIT 20
   ```
2. **API**: Get provider details -> `GET /provider?nrn=organization={org_id}&show_descendants=true`
3. **API**: Get actual config -> `GET /runtime_configuration/{data_source.key}` -> look for `values.aws.region`, `values.google.location`, etc.

### Provider Hierarchy

Providers have overrides at different levels:
```
Account level (base config)
  └── Namespace level (override)
       └── Application level (override)
            └── Per-dimension (e.g., environment=prod, country=uruguay)
```

Each provider has:
- `specification_id` — type of provider (AWS account, EKS cluster, GitHub, Azure, GKE, etc.)
- `data_source.key` — runtime_configuration ID with actual values
- `data_source.stored_keys` — which config keys this provider manages
- `dimensions` — under which dimensions the override applies

## Error Handling: Fail Fast

1. Run `check_ch_auth.sh` first. If it fails, offer auth options (see Prerequisites)
2. If a query fails, try **ONE more time** maximum
3. If it fails again, tell the user and suggest the nullplatform dashboard
4. **NEVER** write custom scripts, use wget/curl directly, or explore skill directories as workarounds

**Failure template:**
> "I'm having technical difficulties accessing the data lake right now. You can check this directly from the nullplatform dashboard: [give specific UI path]. If the issue persists, please try again later."
