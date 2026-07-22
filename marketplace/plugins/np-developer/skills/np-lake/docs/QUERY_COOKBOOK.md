# Customer Lake Query Cookbook

Pre-built queries for the nullplatform data lake.

## Important Notes

1. **Organization filter is automatic**: The server filters by org via the Bearer token. Never add `WHERE organization_id = ...`.
2. **Always use `WHERE _deleted = 0`**: Exclude soft-deleted records. Exceptions: `audit_events`, `scm_code_commits`, `scm_code_repositories`, and the view `auth_resource_grants_expanded` don't have this column.
3. **Always use `FINAL`**: Deduplicates `ReplacingMergeTree` rows. Syntax: `FROM table AS alias FINAL` (alias BEFORE `FINAL`). **Exception:** views (e.g. `auth_resource_grants_expanded`) do not take `FINAL`.
4. **Always use `LIMIT`**: Cap exploratory query results.
5. **Select specific columns**: Avoid `SELECT *` in production.
6. **JOINs work with correct syntax**: `FROM table AS alias FINAL JOIN table2 AS alias2 FINAL ON ...`. Do NOT use `FROM table FINAL AS alias` (syntax error).
7. **Column names vary by table**: See SCHEMA.md for the correct column names per table. Key examples: `app_id`/`app_name` (applications), `account_id`/`account_name` (accounts), `namespace_id`/`namespace_name` (namespaces), `org_id`/`org_name` (organizations).
8. **Services tables** have **both** `_deleted` (sync) and `deleted_at` (application-level). Use `WHERE _deleted = 0 AND deleted_at IS NULL` for the strict "truly live" view.

---

## Exploration

### List all applications

```sql
SELECT app_id, app_name, application_slug, status, nrn
FROM core_entities_application FINAL
WHERE _deleted = 0
ORDER BY app_name
LIMIT 100
```

### Search application by name

```sql
SELECT app_id, app_name, application_slug, status, nrn
FROM core_entities_application FINAL
WHERE _deleted = 0
AND app_name ILIKE '%search-term%'
LIMIT 20
```

### List scopes of an application

```sql
SELECT id, name, scope_slug, status, type, provider, tier, nrn
FROM core_entities_scope FINAL
WHERE _deleted = 0
AND application_id = {app_id}
ORDER BY name
```

### List namespaces of an account

```sql
SELECT namespace_id, namespace_name, namespace_slug, status, nrn
FROM core_entities_namespace FINAL
WHERE _deleted = 0
AND account_id = {account_id}
ORDER BY namespace_name
```

### Hierarchical exploration: Org → Account → Namespace → Application

```sql
-- Step 1: List accounts
SELECT account_id, account_name, slug, nrn
FROM core_entities_account FINAL WHERE _deleted = 0 LIMIT 20

-- Step 2: List namespaces of an account
SELECT namespace_id, namespace_name, namespace_slug, nrn
FROM core_entities_namespace FINAL WHERE _deleted = 0 AND account_id = {account_id} LIMIT 20

-- Step 3: List apps of a namespace
SELECT app_id, app_name, application_slug, nrn
FROM core_entities_application FINAL WHERE _deleted = 0 AND namespace_id = {namespace_id} LIMIT 20

-- Step 4: List scopes of an app
SELECT id, name, type, status, nrn
FROM core_entities_scope FINAL WHERE _deleted = 0 AND application_id = {app_id} LIMIT 20
```

### Count entities by level

```sql
SELECT 'accounts' AS entity, count() AS cnt FROM core_entities_account FINAL WHERE _deleted = 0
UNION ALL
SELECT 'namespaces', count() FROM core_entities_namespace FINAL WHERE _deleted = 0
UNION ALL
SELECT 'applications', count() FROM core_entities_application FINAL WHERE _deleted = 0
UNION ALL
SELECT 'scopes', count() FROM core_entities_scope FINAL WHERE _deleted = 0
UNION ALL
SELECT 'deployments', count() FROM core_entities_deployment FINAL WHERE _deleted = 0
```

---

## Deployments

### Recent deployments with app and scope names (JOIN + FINAL)

```sql
SELECT d.id AS deploy_id, d.status, d.strategy, d.created_at,
       s.name AS scope_name, a.app_name
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id
JOIN core_entities_application AS a FINAL ON s.application_id = a.app_id
WHERE d._deleted = 0
ORDER BY d.created_at DESC
LIMIT 10
```

### Recent deployments (simple, single table)

```sql
SELECT id, status, strategy, scope_id, release_id, created_by,
       created_at, status_in_scope, nrn
FROM core_entities_deployment FINAL
WHERE _deleted = 0
ORDER BY created_at DESC
LIMIT 20
```

### My deployments (filter by user ID)

The user ID can be extracted from the JWT token's `cognito:groups` field (`@nullplatform/user=XXXXX`).

```sql
SELECT id, status, strategy, scope_id, release_id,
       created_at, updated_at, nrn
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_by = {user_id}
ORDER BY created_at DESC
LIMIT 10
```

### Deployments by application (preferred: JOIN through scope)

Since deployments have no `application_id`, join through scope to filter by app:

```sql
SELECT d.id, d.status, d.strategy, d.scope_id, d.release_id, d.created_by, d.created_at
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id AND s._deleted = 0
WHERE d._deleted = 0
AND s.application_id = {app_id}
ORDER BY d.created_at DESC
LIMIT 20
```

### Deployments by NRN prefix (alternative)

If using NRN filtering, ALWAYS use the full prefix with parents (never leading `%`):

```sql
-- First resolve the full NRN prefix from the application:
-- SELECT nrn FROM core_entities_application FINAL WHERE _deleted = 0 AND app_id = {app_id}
-- Then use the returned NRN as prefix:
SELECT id, status, strategy, scope_id, release_id, created_by, created_at
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND nrn LIKE 'organization={org_id}:account={acct_id}:namespace={ns_id}:application={app_id}%'
ORDER BY created_at DESC
LIMIT 20
```

### Deployment count by NRN (top apps by deploys)

```sql
SELECT nrn,
       count(DISTINCT id) AS deploy_count,
       countIf(DISTINCT id, status = 'finalized') AS finalized,
       countIf(DISTINCT id, status = 'failed') AS failed
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_at >= now() - INTERVAL 7 DAY
GROUP BY nrn
ORDER BY deploy_count DESC
LIMIT 15
```

Then resolve app names in a separate query:

```sql
SELECT app_id, app_name
FROM core_entities_application FINAL
WHERE _deleted = 0
AND app_id IN ({id1}, {id2}, {id3})
```

### Failed deployments

```sql
SELECT id, status, scope_id, release_id, created_by, created_at, messages, nrn
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND status = 'failed'
ORDER BY created_at DESC
LIMIT 20
```

### Deployment groups

```sql
SELECT id, status, application_id, release_id, last_directive,
       deployments_amount, created_by, created_at
FROM core_entities_deployment_group FINAL
WHERE _deleted = 0
ORDER BY created_at DESC
LIMIT 20
```

---

## Builds & Releases

### Recent builds

```sql
SELECT id, app_id, status, branch, commit, description, created_at
FROM core_entities_build FINAL
WHERE _deleted = 0
ORDER BY created_at DESC
LIMIT 20
```

### Releases of an application

```sql
SELECT id, semver, build_id, status, app_id, created_at
FROM core_entities_release FINAL
WHERE _deleted = 0
AND app_id = {app_id}
ORDER BY created_at DESC
LIMIT 20
```

### Build assets (container images)

```sql
SELECT id, build_id, type, url, name, platform, created_at
FROM core_entities_asset FINAL
WHERE _deleted = 0
AND build_id = {build_id}
```

---

## Approval Workflows

### Pending approval requests

```sql
SELECT id, entity_name, entity_action, entity_id, status,
       user_id, execution_status, created_at
FROM approvals_approval_request FINAL
WHERE _deleted = 0
AND status = 'pending'
ORDER BY created_at DESC
LIMIT 50
```

### Active approval actions

```sql
SELECT id, entity, action, status, on_policy_success, on_policy_fail
FROM approvals_approval_action FINAL
WHERE _deleted = 0
AND status = 'active'
LIMIT 50
```

### Approval policies

```sql
SELECT id, name, slug, status, created_at
FROM approvals_policy FINAL
WHERE _deleted = 0
AND status = 'active'
ORDER BY name
LIMIT 50
```

### Entity hook requests

```sql
SELECT id, entity_name, entity_action, entity_id, status,
       execution_status, type, `when`, `on`, created_at
FROM approvals_entity_hook_request FINAL
WHERE _deleted = 0
ORDER BY created_at DESC
LIMIT 20
```

---

## Parameters

### List parameters of an application (via NRN)

```sql
SELECT id, name, type, secret, handle, encoding, read_only, nrn
FROM parameters_parameter FINAL
WHERE _deleted = 0
AND nrn LIKE 'organization={org_id}:account={account_id}:namespace={namespace_id}:application={app_id}%'
ORDER BY name
LIMIT 100
```

### Parameter versions

```sql
SELECT id, parameter_id, user_id, created_at
FROM parameters_parameter_version FINAL
WHERE _deleted = 0
AND parameter_id = {parameter_id}
ORDER BY created_at DESC
LIMIT 20
```

### Secret parameters

```sql
SELECT id, name, type, nrn, created_at
FROM parameters_parameter FINAL
WHERE _deleted = 0
AND secret = 1
ORDER BY name
LIMIT 50
```

---

## Governance (Action Items)

### Open action items (cost optimization, security, etc.)

```sql
SELECT action_item_id, title, status, priority, score, created_by, created_at, nrn
FROM governance_action_items_action_items FINAL
WHERE _deleted = 0
AND status = 'open'
ORDER BY score DESC
LIMIT 20
```

### Action items by category

```sql
SELECT ai.action_item_id, ai.title, ai.priority, ai.score,
       c.category_name, ai.created_at
FROM governance_action_items_action_items AS ai FINAL
JOIN governance_action_items_categories AS c FINAL ON ai.category_id = c.category_id
WHERE ai._deleted = 0
AND ai.status = 'open'
ORDER BY ai.score DESC
LIMIT 20
```

### Suggestions for action items

```sql
SELECT suggestion_id, action_item_id, status, created_by, owner,
       description, created_at
FROM governance_action_items_suggestions FINAL
WHERE _deleted = 0
AND action_item_id = '{action_item_id}'
```

---

## SCM (Source Code Management)

### Recent commits

```sql
SELECT sha, message, author_name, author_email, date, code_repository_id
FROM scm_code_commits
ORDER BY date DESC
LIMIT 20
```

### Code repositories

```sql
SELECT id, name, provider, language, url, private, date_created
FROM scm_code_repositories
ORDER BY date_created DESC
LIMIT 20
```

---

## Audit Events

> ⚠️ **`audit_events` is partitioned by `date` (daily) and has 180M+ rows.**
> **Every query MUST include a `date` filter** — without it, the engine scans the full ~35 GiB table. Even an `INTERVAL 1 YEAR` is far better than no bound.
> Skip-indexes also exist for `entity`, `method`, `status`, `user_email`, `user_id`, `entity_id`, `affected_nrn` — filtering by these is cheap.

### Recent events (last 24h)

```sql
SELECT entity, method, url, status, entity_id, user_id, user_email, date
FROM audit_events
WHERE date >= now() - INTERVAL 24 HOUR
ORDER BY date DESC
LIMIT 50
```

### Events by user (last 30 days)

```sql
SELECT entity, method, url, status, entity_id, date
FROM audit_events
WHERE date >= now() - INTERVAL 30 DAY
  AND user_email = '{email}'
ORDER BY date DESC
LIMIT 50
```

### Deployment events (last 7 days)

```sql
SELECT entity, method, url, status, entity_id, user_email, date
FROM audit_events
WHERE date >= now() - INTERVAL 7 DAY
  AND entity = 'deployment'
ORDER BY date DESC
LIMIT 20
```

### Failed mutations in the last 24h

```sql
SELECT entity, method, url, status, user_email, date
FROM audit_events
WHERE date >= now() - INTERVAL 24 HOUR
  AND method IN ('POST','PATCH','DELETE')
  AND status >= 400
ORDER BY date DESC
LIMIT 50
```

### Events affecting a specific application

Use the pre-extracted `affected_nrn` column (faster than parsing JSON):

```sql
SELECT entity, method, status, date, user_email
FROM audit_events
WHERE date >= now() - INTERVAL 7 DAY
  AND affected_nrn LIKE 'organization=4:account=17:namespace=507252312:application=1798062750%'
ORDER BY date DESC LIMIT 100
```

### Activity per namespace (mutations created)

```sql
SELECT
  toInt64OrZero(extractAll(affected_nrn, 'namespace=(\d+)')[1]) AS namespace_id,
  count() AS mutations
FROM audit_events
WHERE date >= now() - INTERVAL 30 DAY
  AND method = 'POST'
  AND affected_nrn != ''
GROUP BY namespace_id
HAVING namespace_id > 0
ORDER BY mutations DESC LIMIT 20
```

### Access JSON fields (native subcolumn)

```sql
SELECT entity, url, status, date,
       request_body.event.email AS user_email
FROM audit_events
WHERE date >= now() - INTERVAL 7 DAY
  AND entity = 'login_success'
ORDER BY date DESC
LIMIT 10
```

---

## User Filtering

### How to get the current user's ID from JWT token

The user ID is embedded in the JWT token's `cognito:groups` claim:

```
@nullplatform/user=515129179
```

Use this ID to filter `created_by` or `updated_by` columns.

### My deployments

```sql
SELECT id, status, strategy, created_at, nrn
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_by = {user_id}
ORDER BY created_at DESC
LIMIT 10
```

### My deployment groups

```sql
SELECT id, status, application_id, deployments_amount, created_at
FROM core_entities_deployment_group FINAL
WHERE _deleted = 0
AND created_by = {user_id}
ORDER BY created_at DESC
LIMIT 10
```

---

## Performance Tips

### NRN filtering — ALWAYS use full prefix

When filtering by NRN, build the full hierarchical prefix from `organization=` down. **Never** use a leading wildcard (`LIKE '%application=123%'`) — it disables index usage and forces a full scan.

```sql
-- ✅ Good: anchored prefix, index-friendly
WHERE nrn LIKE 'organization=123:account=456:namespace=789:application=012%'

-- ❌ Bad: leading wildcard, full scan
WHERE nrn LIKE '%application=012%'
```

If you only have the leaf ID (e.g., `app_id`), resolve the full NRN first:

```sql
SELECT nrn FROM core_entities_application FINAL WHERE _deleted = 0 AND app_id = {app_id}
```

Then use the returned value as the anchored prefix in the second query.

### Date filtering

```sql
-- Last N days
WHERE created_at >= now() - INTERVAL 7 DAY

-- Specific range
WHERE created_at BETWEEN '2026-01-01' AND '2026-01-31'

-- Today
WHERE toDate(created_at) = today()
```

### Group by period

```sql
-- By day
SELECT toDate(created_at) AS day, count() AS cnt
FROM core_entities_deployment FINAL
WHERE _deleted = 0
GROUP BY day ORDER BY day DESC LIMIT 30

-- By hour
SELECT toStartOfHour(created_at) AS hour, count() AS cnt
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_at >= now() - INTERVAL 24 HOUR
GROUP BY hour ORDER BY hour DESC
```

### Conditional counts

```sql
SELECT
    countIf(status = 'finalized') AS finalized,
    countIf(status = 'failed') AS failed,
    countIf(status = 'running') AS running,
    count() AS total
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_at >= now() - INTERVAL 7 DAY
```

---

## Auth

> **`auth_resource_grants_expanded` is a View** — do NOT use `FINAL` or `WHERE _deleted = 0` on it. Query it directly.

### List active users

```sql
SELECT id, email, first_name, last_name, user_type, status, provider, created_at
FROM auth_user FINAL
WHERE _deleted = 0
AND status = 'active'
ORDER BY email
LIMIT 50
```

### Find a user by email

```sql
SELECT id, email, first_name, last_name, status, user_type, provider, nrn
FROM auth_user FINAL
WHERE _deleted = 0
AND email ILIKE '%{search:String}%'
LIMIT 20
```

### Count users by type and status

```sql
SELECT user_type, status, count() AS total
FROM auth_user FINAL
WHERE _deleted = 0
GROUP BY user_type, status
ORDER BY user_type, total DESC
```

### List active roles

```sql
SELECT id, name, slug, level, status, organization_id
FROM auth_role FINAL
WHERE _deleted = 0
AND status = 'active'
ORDER BY level, name
LIMIT 50
```

### List every role a user has, with the NRN it applies to

Use the **view** `auth_resource_grants_expanded` for this — it pre-joins the role metadata so you don't need an extra join. Do **not** use `FINAL` or `WHERE _deleted = 0` on the view.

```sql
SELECT g.nrn, g.role_name, g.role_slug, g.role_level, g.status, g.created_at
FROM auth_resource_grants_expanded AS g
WHERE g.user_id = {user_id:Int32}
AND g.status = 'active'
ORDER BY g.created_at DESC
LIMIT 100
```

### Count active users per role

```sql
SELECT g.role_name, g.role_slug, count(DISTINCT g.user_id) AS users
FROM auth_resource_grants_expanded AS g
WHERE g.status = 'active'
GROUP BY g.role_name, g.role_slug
ORDER BY users DESC
LIMIT 50
```

### List all active grants on a resource NRN prefix

```sql
SELECT g.id, g.user_id, u.email, g.role_id, r.name AS role_name, r.level, g.status, g.created_at
FROM auth_resource_grants AS g FINAL
JOIN auth_user AS u FINAL ON u.id = g.user_id AND u._deleted = 0
JOIN auth_role AS r FINAL ON r.id = g.role_id AND r._deleted = 0
WHERE g._deleted = 0
AND g.status = 'active'
AND g.nrn LIKE 'organization={org_id}:account={acct_id}%'
ORDER BY g.created_at DESC
LIMIT 50
```

### Users with a specific role on a resource (NRN prefix)

```sql
SELECT g.user_id, g.role_name, g.role_level, g.nrn, g.created_at,
       u.email, u.first_name, u.last_name
FROM auth_resource_grants_expanded AS g
JOIN auth_user AS u FINAL ON g.user_id = u.id
WHERE u._deleted = 0
AND g.status = 'active'
AND g.nrn LIKE 'organization={org_id}%'
AND g.role_slug = '{role_slug}'
ORDER BY g.created_at DESC
LIMIT 50
```

### API keys for a user

```sql
SELECT id, name, status, masked_api_key, roles, internal, used_at, created_at
FROM auth_apikey FINAL
WHERE _deleted = 0
AND user_id = {user_id}
ORDER BY created_at DESC
LIMIT 20
```

### List active API keys (non-internal)

```sql
SELECT id, name, masked_api_key, status, used_at, created_at, nrn
FROM auth_apikey FINAL
WHERE _deleted = 0
AND status = 'active'
AND internal = 0
ORDER BY created_at DESC
LIMIT 50
```

### API keys touched in the last N days

```sql
SELECT id, name, masked_api_key, owner_id, used_at, nrn
FROM auth_apikey FINAL
WHERE _deleted = 0
AND used_at >= now() - INTERVAL 7 DAY
ORDER BY used_at DESC
LIMIT 50
```

### API keys that have never been used

```sql
SELECT id, name, masked_api_key, owner_id, created_at, nrn
FROM auth_apikey FINAL
WHERE _deleted = 0
AND used_at IS NULL
ORDER BY created_at DESC
LIMIT 100
```

### Find API keys not used recently

```sql
SELECT id, name, masked_api_key, status, used_at, created_at, nrn
FROM auth_apikey FINAL
WHERE _deleted = 0
AND status = 'active'
AND (used_at IS NULL OR used_at < now() - INTERVAL 90 DAY)
ORDER BY used_at ASC
LIMIT 50
```

---

## Services

### List all service instances, most recently updated first

```sql
SELECT id, name, slug, type, status, specification_id, entity_nrn, updated_at
FROM services_services FINAL
WHERE _deleted = 0
AND deleted_at IS NULL
ORDER BY updated_at DESC
LIMIT 50
```

### Find services attached to a specific entity (e.g., an application NRN)

```sql
SELECT id, name, slug, status, type, specification_id, nrn
FROM services_services FINAL
WHERE _deleted = 0
AND deleted_at IS NULL
AND entity_nrn = {entity_nrn:String}
ORDER BY name
```

### Count services per specification type

```sql
SELECT s.type, count() AS instances
FROM services_services AS s FINAL
WHERE s._deleted = 0 AND s.deleted_at IS NULL
GROUP BY s.type
ORDER BY instances DESC
LIMIT 50
```

### List all links for a given service (with spec names)

```sql
SELECT l.id, l.name, l.slug, l.status, l.entity_nrn, sp.name AS link_spec_name
FROM services_links AS l FINAL
LEFT JOIN services_link_specifications AS sp FINAL
       ON l.specification_id = sp.id
WHERE l._deleted = 0 AND l.deleted_at IS NULL
AND l.service_id = {service_id:UUID}
ORDER BY l.updated_at DESC
LIMIT 100
```

### Recent action invocations (with outcome)

```sql
SELECT id, name, slug, status, service_id, link_id, created_by, created_at
FROM services_actions FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND created_at >= now() - INTERVAL 24 HOUR
ORDER BY created_at DESC
LIMIT 100
```

### Action success/failure breakdown for the last 7 days

```sql
SELECT
    countIf(status = 'success') AS succeeded,
    countIf(status = 'failed')  AS failed,
    countIf(status = 'running') AS running,
    count() AS total
FROM services_actions FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND created_at >= now() - INTERVAL 7 DAY
```

### Parameter wiring for a service instance

```sql
SELECT id, entity_nrn, type, target, parameter_id
FROM services_parameters FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND service_id = {service_id:UUID}
LIMIT 100
```

### List active services with their specification name

```sql
SELECT s.id, s.name, s.type, s.status, sp.name AS spec_name, s.entity_nrn, s.created_at
FROM services_services AS s FINAL
LEFT JOIN services_service_specifications AS sp FINAL
  ON sp.id = s.specification_id AND sp._deleted = 0
WHERE s._deleted = 0 AND s.deleted_at IS NULL
AND s.status = 'active'
ORDER BY s.type, s.name
LIMIT 100
```

### List failed services

```sql
SELECT id, name, type, status, messages, entity_nrn, updated_at
FROM services_services FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND status = 'failed'
ORDER BY updated_at DESC
LIMIT 50
```

### Count services by type and status

```sql
SELECT type, status, count() AS total
FROM services_services FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
GROUP BY type, status
ORDER BY type, total DESC
```

### List active links for a specific service

```sql
SELECT l.id, l.name, l.status, l.entity_nrn, ls.name AS link_type, l.created_at
FROM services_links AS l FINAL
LEFT JOIN services_link_specifications AS ls FINAL
  ON ls.id = l.specification_id AND ls._deleted = 0
WHERE l._deleted = 0 AND l.deleted_at IS NULL
AND l.status = 'active'
AND l.service_id = {service_id:UUID}
ORDER BY l.created_at DESC
LIMIT 50
```

### List recent action executions on a service

```sql
SELECT a.id, a.name, a.status, a.created_by, a.created_at, a.updated_at
FROM services_actions AS a FINAL
WHERE a._deleted = 0 AND a.deleted_at IS NULL
AND a.service_id = {service_id:UUID}
ORDER BY a.created_at DESC
LIMIT 20
```

### List available service specification types

```sql
SELECT id, name, slug, type, created_at
FROM services_service_specifications FINAL
WHERE _deleted = 0
ORDER BY type, name
LIMIT 50
```

### Services for an application (via entity_nrn prefix)

```sql
SELECT id, name, slug, status, type, specification_id, entity_nrn, created_at
FROM services_services FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND entity_nrn LIKE 'organization={org_id}:account={account_id}:namespace={namespace_id}:application={app_id}%'
ORDER BY created_at DESC
LIMIT 20
```

### Failed or non-active services

```sql
SELECT id, name, status, type, entity_nrn, messages, created_at, updated_at
FROM services_services FINAL
WHERE _deleted = 0 AND deleted_at IS NULL
AND status != 'active'
ORDER BY updated_at DESC
LIMIT 20
```

### Links for an application (via entity_nrn prefix)

```sql
SELECT l.id, l.name, l.status, l.service_id, l.entity_nrn,
       s.name AS service_name, s.type AS service_type
FROM services_links AS l FINAL
JOIN services_services AS s FINAL ON l.service_id = s.id
WHERE l._deleted = 0 AND l.deleted_at IS NULL
AND l.entity_nrn LIKE 'organization={org_id}:account={account_id}:namespace={namespace_id}:application={app_id}%'
ORDER BY l.created_at DESC
LIMIT 20
```

### Exported parameters by service (via entity_nrn prefix)

Use when you need the application-level wiring (DATABASE_URL, REDIS_HOST, etc.) across all services attached to an app:

```sql
SELECT sp.id, sp.target, sp.type, sp.entity_nrn, sp.parameter_id,
       s.name AS service_name, s.type AS service_type
FROM services_parameters AS sp FINAL
JOIN services_services AS s FINAL ON sp.service_id = s.id
WHERE sp._deleted = 0 AND sp.deleted_at IS NULL
AND sp.entity_nrn LIKE 'organization={org_id}:account={account_id}:namespace={namespace_id}:application={app_id}%'
ORDER BY sp.created_at DESC
LIMIT 50
```
