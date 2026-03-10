# Customer Lake Query Cookbook

Pre-built queries for the nullplatform data lake.

## Important Notes

1. **Organization filter is automatic**: The server filters by org via the Bearer token. Never add `WHERE organization_id = ...`.
2. **Always use `WHERE _deleted = 0`**: Exclude soft-deleted records. Exception: `audit_events`, `scm_code_commits`, `scm_code_repositories` don't have this column.
3. **Always use `FINAL`**: Deduplicates `ReplacingMergeTree` rows. Syntax: `FROM table AS alias FINAL` (alias BEFORE `FINAL`).
4. **Always use `LIMIT`**: Cap exploratory query results.
5. **Select specific columns**: Avoid `SELECT *` in production.
6. **JOINs work with correct syntax**: `FROM table AS alias FINAL JOIN table2 AS alias2 FINAL ON ...`. Do NOT use `FROM table FINAL AS alias` (syntax error).
7. **Column names vary by table**: See SCHEMA.md for the correct column names per table. Key examples: `app_id`/`app_name` (applications), `account_id`/`account_name` (accounts), `namespace_id`/`namespace_name` (namespaces), `org_id`/`org_name` (organizations).

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

### Deployments by NRN (per application)

Since deployments have no `application_id`, use NRN prefix to filter by app:

```sql
SELECT id, status, strategy, scope_id, release_id, created_by, created_at
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND nrn LIKE '%application={app_id}%'
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
AND nrn LIKE '%application={app_id}%'
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

### Recent events

```sql
SELECT entity, method, url, status, entity_id, user_id, user_email, date
FROM audit_events
ORDER BY date DESC
LIMIT 50
```

### Events by user

```sql
SELECT entity, method, url, status, entity_id, date
FROM audit_events
WHERE user_email = '{email}'
ORDER BY date DESC
LIMIT 50
```

### Deployment events

```sql
SELECT entity, method, url, status, entity_id, user_email, date
FROM audit_events
WHERE entity = 'deployment'
ORDER BY date DESC
LIMIT 20
```

### Access JSON fields

```sql
SELECT entity, url, status, date,
       request_body.additional_data
FROM audit_events
WHERE entity = 'login_success'
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
