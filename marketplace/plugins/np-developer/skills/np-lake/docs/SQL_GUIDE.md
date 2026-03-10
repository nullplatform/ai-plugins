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

-- Via NRN (alternative, for single-table queries)
WHERE nrn LIKE '%application=123%'
```

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

## Save Results

```bash
# Save to JSON file
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh "SELECT ..." output.json
```
