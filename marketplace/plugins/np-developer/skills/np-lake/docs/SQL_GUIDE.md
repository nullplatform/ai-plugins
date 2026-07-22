# SQL Guide for Customer Lake

## ReplacingMergeTree & FINAL

Most tables use `ReplacingMergeTree`, which deduplicates rows by `_version` — but deduplication is **asynchronous**. Without `FINAL`, queries may return duplicate rows for the same entity.

**Always use `FINAL`** when querying entity tables:

```sql
-- Without FINAL: may return duplicates
SELECT id, status FROM core_entities_deployment WHERE _deleted = 0 LIMIT 10

-- With FINAL: deduplicated results
SELECT id, status FROM core_entities_deployment FINAL WHERE _deleted = 0 LIMIT 10
```

**Exception:** `audit_events` uses `MergeTree` (append-only) — no `FINAL` needed.

## JOINs

JOINs work correctly. Syntax: `table AS alias FINAL` (alias BEFORE `FINAL`):

```sql
-- CORRECT: AS alias FINAL
SELECT d.id AS deploy_id, d.status, d.strategy, d.created_at,
       s.name AS scope_name, a.app_name
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id
JOIN core_entities_application AS a FINAL ON s.application_id = a.app_id
WHERE d._deleted = 0
ORDER BY d.created_at DESC
LIMIT 10

-- WRONG: FINAL AS alias (syntax error)
FROM core_entities_deployment FINAL AS d  -- ← FAILS
```

### Linking deployments to applications

`core_entities_deployment` has **NO `application_id`**. Use scope as a bridge:

```sql
-- Via scope (preferred for JOINs)
deployment.scope_id → scope.application_id → application.app_id

-- Via NRN prefix (alternative — ALWAYS use full prefix with parents, never leading %)
-- First resolve the parent IDs: SELECT nrn FROM core_entities_application FINAL WHERE _deleted = 0 AND app_id = 123
WHERE nrn LIKE 'organization={org_id}:account={acct_id}:namespace={ns_id}:application=123%'
```

**Never** use `nrn LIKE '%application=123%'` — the leading wildcard disables index usage and forces a full scan.

## Output Formats

The script appends `FORMAT JSONEachRow` by default. To change:

```bash
# Pretty table (good for exploration)
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --format pretty "SELECT ..."

# TSV output
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --format tsv "SELECT ..."

# JSON (default)
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh "SELECT ..."
```

## Date Functions

```sql
-- Last N days
WHERE created_at >= now() - INTERVAL 7 DAY

-- Specific range
WHERE created_at BETWEEN '2026-01-01' AND '2026-01-31'

-- Today
WHERE toDate(created_at) = today()

-- Group by day
SELECT toDate(created_at) AS day, count() AS cnt
FROM core_entities_deployment FINAL
WHERE _deleted = 0
GROUP BY day ORDER BY day DESC LIMIT 30

-- Group by hour
SELECT toStartOfHour(created_at) AS hour, count() AS cnt
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_at >= now() - INTERVAL 24 HOUR
GROUP BY hour ORDER BY hour DESC
```

## Conditional Aggregation

```sql
SELECT
    countIf(status = 'finalized') AS finalized,
    countIf(status = 'failed') AS failed,
    countIf(status = 'rolled_back') AS rolled_back,
    countIf(status = 'cancelled') AS cancelled,
    count() AS total
FROM core_entities_deployment FINAL
WHERE _deleted = 0
AND created_at >= now() - INTERVAL 7 DAY
```

## Forbidden SQL Syntax (Server-Side Restrictions)

The Customer Lake API has a server-side SQL validator that blocks certain syntax with `FST_ERR_FORBIDDEN_SQL`. These queries will be rejected before execution.

**Blocked operators:**

| Blocked Syntax | Error | Workaround |
|---------------|-------|------------|
| `IS NOT NULL` | `FST_ERR_FORBIDDEN_SQL` | Use `!= 0` for integers, or omit the filter |
| `!= ''` (empty string check) | `FST_ERR_FORBIDDEN_SQL` | Use `length(column) > 0` or omit |
| `IS NULL` | `FST_ERR_FORBIDDEN_SQL` | Avoid; Nullable columns default to empty/zero |

**Example:**

```sql
-- WRONG: will be rejected
SELECT provider FROM core_entities_scope FINAL
WHERE _deleted = 0 AND provider IS NOT NULL AND provider != ''

-- CORRECT: use simpler filters
SELECT provider FROM core_entities_scope FINAL
WHERE _deleted = 0 AND length(provider) > 0
```

**When in doubt:** If a query fails with `FST_ERR_FORBIDDEN_SQL`, simplify the WHERE clause and filter results after retrieval.

---

## Performance Tips

1. **Always use `FINAL`** — Deduplicates `ReplacingMergeTree` rows
2. **Always use `WHERE _deleted = 0`** — Exclude soft-deleted records (except `audit_events`, `scm_code_commits`, `scm_code_repositories`)
3. **Always use `LIMIT`** — Cap exploratory queries
4. **Avoid `SELECT *`** — Select only needed columns
5. **Filter by sorting key first** — Queries on the primary/sorting key skip data granules (see SCHEMA.md for keys per table)
6. **Organization filter is automatic** — Never add `WHERE organization_id = ...`
7. **Use `countIf`** — For conditional aggregation instead of multiple queries
8. **For `audit_events`: ALWAYS filter by `date`** — see section below

---

## Querying `audit_events` efficiently

`audit_events` is the largest table in the lake (>180M rows, ~35 GiB compressed). It's **partitioned by day** (`PARTITION BY toYYYYMMDD(date)`), so a date filter is the single most impactful optimization — it discards entire daily partitions before any other work.

### Rule #1: ALWAYS filter by `date`

```sql
-- ✅ GOOD: partition pruning cuts ~1500 parts → ~7 parts
SELECT entity, count() FROM audit_events
WHERE date >= now() - INTERVAL 7 DAY
  AND entity = 'deployment'
GROUP BY entity

-- ❌ BAD: full table scan (35 GiB, multiple minutes)
SELECT entity, count() FROM audit_events
WHERE entity = 'deployment'
GROUP BY entity
```

Even when the user asks for "all time" data, prefer an explicit bound (e.g., `INTERVAL 1 YEAR`) rather than no filter. If you truly need a full scan, say so explicitly to the user before running it.

### Skip-indexes available on `audit_events`

These columns have skip-indexes — filtering by them is cheap:

| Column | Index type | Best for |
|---|---|---|
| `entity` | `set(100)` | Equality / `IN` (57 distinct values) |
| `method` | `set(10)` | `POST`, `PATCH`, `GET`, `DELETE`, `PUT` |
| `status` | `minmax` | Range filters (`status >= 400`, `status IN (200,201)`) |
| `user_email` | `bloom_filter` | Equality / `LIKE 'prefix%'` (not `%suffix`) |
| `user_id` | `bloom_filter` | Equality |
| `entity_id` | `bloom_filter` | Equality |
| `affected_nrn` | `bloom_filter` | Equality / `LIKE 'organization=X%'` |

Combine the date filter with these for maximum pruning:

```sql
-- ✅ Uses partition (date) + skip-index (entity, method) + range (status)
SELECT count() FROM audit_events
WHERE date >= now() - INTERVAL 24 HOUR
  AND entity = 'deployment'
  AND method = 'POST'
  AND status >= 400
```

### `affected_nrn` — the NRN of the resource the event acted on

For mutating events (POST/PATCH/DELETE), the `response_body` contains the created/updated resource. Its NRN is exposed as a materialized column **`affected_nrn`** — already extracted, indexed, no JSON parsing needed.

```sql
-- ✅ Find which namespaces had services created in last 30d
SELECT
  toInt64OrZero(extractAll(affected_nrn, 'namespace=(\d+)')[1]) AS namespace_id,
  count() AS services_created
FROM audit_events
WHERE date >= now() - INTERVAL 30 DAY
  AND entity = 'service' AND method = 'POST'
  AND affected_nrn != ''
GROUP BY namespace_id
ORDER BY services_created DESC

-- ✅ All events affecting a specific application
SELECT entity, method, status, date, user_email
FROM audit_events
WHERE date >= now() - INTERVAL 7 DAY
  AND affected_nrn LIKE 'organization=4:account=17:namespace=507252312:application=1798062750%'
ORDER BY date DESC LIMIT 100
```

**Prefer `affected_nrn` over `JSONExtractString(toString(response_body), 'entity_nrn')`** — the latter forces decompression of the entire response JSON column (~3.7 GiB on disk, ~70 GiB uncompressed) for every matching row.

### JSON access on `request_body` / `response_body`

These are native `JSON` typed columns. Two access patterns:

```sql
-- ✅ Native subcolumn access (fastest, reads only the path)
SELECT request_body.event.email AS email
FROM audit_events WHERE date >= today() AND entity = 'login_success'

-- ⚠️ JSONExtractString on toString() — works but reads the full JSON blob
SELECT JSONExtractString(toString(request_body), 'event', 'email') AS email
FROM audit_events WHERE date >= today() AND entity = 'login_success'
```

Use subcolumn access whenever you know the path. Reserve `JSONExtractString` for paths that are dynamic or that vary across event types.

### Things to avoid

- `entity LIKE '%foo%'` — the skip-index can't help with a leading wildcard. Prefer `entity IN ('login_success','login_failure',...)` if you know the values.
- `SELECT * FROM audit_events` — always project specific columns; `headers`, `request_body`, `response_body`, `entity_data` are large JSON columns.
- `JOIN audit_events ... ON toString(u.id) = a.user_id` — the cast prevents efficient join. If joining with `auth_user`, project `toInt32OrZero(user_id)` once in a subquery first.

---

## Querying `core_entities_deployment` efficiently

Also has skip-indexes (added for common dashboard queries):

| Column | Index type | Best for |
|---|---|---|
| `status` | `set(20)` | `status = 'finalized'`, `status IN ('failed','rolled_back')` |
| `created_at` | `minmax` | `created_at > now() - INTERVAL X` |
| `scope_id` | `bloom_filter` | Equality lookups |

```sql
-- ✅ Uses skip-indexes on status + created_at
SELECT status, count() FROM core_entities_deployment FINAL
WHERE _deleted = 0
  AND created_at >= now() - INTERVAL 7 DAY
  AND status IN ('finalized','failed','rolled_back')
GROUP BY status
```

## Save Results

```bash
# Save to JSON file
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh "SELECT ..." output.json
```
