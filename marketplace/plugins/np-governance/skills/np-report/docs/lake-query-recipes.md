<!-- JSON code blocks are intentionally minified to reduce token usage when this file is loaded into the model context. Do NOT reformat/prettify. -->

# Lake Query Recipes

Ready-to-parameterize SQL for the report subjects requested most often. Every query here follows
the Global Constraints (see `SKILL.md` → **SQL rules**): table prefixes like `core_entities_*`,
`FINAL` + `_deleted = 0` on every table (except `audit_events`, `scm_code_commits`,
`scm_code_repositories`), deployment success = `status = 'finalized'`, build success =
`status = 'successful'`, environment lives in `core_entities_scope_dimension`, and every query ends
in `FORMAT JSON`.

For the full data model — every table, column, and type — see the sibling `np-lake` skill's
`docs/SCHEMA.md`. For more exploration/entity-browsing recipes (applications, scopes, namespaces,
approvals, governance, audit, parameters), see the sibling `np-lake` skill's
`docs/QUERY_COOKBOOK.md`. The recipes below cover only the report-shaped aggregate queries a
dashboard typically needs — count, rate, trend, breakdown, and join-based lookups.

Each recipe below is trusted baseline SQL (ported verbatim from the widget cookbook's global-filter
and date-range patterns) — reuse it as-is inside a query's `source`, wiring `params` to the
corresponding filter fields per `docs/json-schema-reference.md`.

## Deployments: Total Count

```sql
SELECT count() as total
FROM core_entities_deployment AS d FINAL
LEFT JOIN core_entities_scope_dimension AS sd FINAL
  ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment'
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
  AND ({environment:String} = '' OR sd.value_slug = {environment:String})
FORMAT JSON
```

## Deployments: Success Rate

```sql
SELECT round(countIf(status = 'finalized') * 100.0 / count(), 1) as successRate
FROM core_entities_deployment AS d FINAL
LEFT JOIN core_entities_scope_dimension AS sd FINAL
  ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment'
WHERE d._deleted = 0
  AND ({environment:String} = '' OR sd.value_slug = {environment:String})
  AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY)
  AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String}))
FORMAT JSON
```

## Deployments: Trend by Day

```sql
SELECT toDate(d.created_at) as date, count() as count
FROM core_entities_deployment AS d FINAL
LEFT JOIN core_entities_scope_dimension AS sd FINAL
  ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment'
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
  AND ({environment:String} = '' OR sd.value_slug = {environment:String})
GROUP BY date
ORDER BY date
FORMAT JSON
```

Swap the `{days:String}` bound for a date-range picker when the report needs precise start/end
selection — use the same `coalesce(parseDateTimeBestEffortOrNull(...), now() - INTERVAL N DAY)`
pattern as the Success Rate recipe above (see `docs/filters-reference.md` § Date Range Picker Filter).

## Deployments: By Environment

`environment` is a scope dimension, not a column on `core_entities_deployment` — join through
`core_entities_scope_dimension` filtered to `dimension_slug = 'environment'`:

```sql
SELECT sd.value_slug as environment, count() as count
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope_dimension AS sd FINAL
  ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment'
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
GROUP BY environment
ORDER BY count DESC
FORMAT JSON
```

Breakdown by environment AND status (e.g. for a stacked bar chart):

```sql
SELECT sd.value_slug as environment,
       countIf(d.status = 'finalized') as successful,
       countIf(d.status = 'failed') as failed
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope_dimension AS sd FINAL
  ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment'
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
GROUP BY environment
ORDER BY environment
FORMAT JSON
```

## Builds: Success Rate

Build success is `status = 'successful'` (NOT `finalized` — that's the deployment status value):

```sql
SELECT round(countIf(status = 'successful') * 100.0 / count(), 1) as successRate
FROM core_entities_build FINAL
WHERE _deleted = 0
  AND created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
FORMAT JSON
```

## Builds: Duration

`core_entities_build` has no explicit duration column — derive it from `created_at`/`updated_at`
for builds that have already finished (`status != 'in_progress'`):

```sql
SELECT round(avg(dateDiff('second', created_at, updated_at)) / 60.0, 2) as avgDurationMin
FROM core_entities_build FINAL
WHERE _deleted = 0
  AND status != 'in_progress'
  AND created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
FORMAT JSON
```

Duration trend by day:

```sql
SELECT toDate(created_at) as date,
       round(avg(dateDiff('second', created_at, updated_at)) / 60.0, 2) as avgDurationMin
FROM core_entities_build FINAL
WHERE _deleted = 0
  AND status != 'in_progress'
  AND created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
GROUP BY date
ORDER BY date
FORMAT JSON
```

## Top Applications by Deploy Count

Deployments have no `application_id` — join deployment → scope → application:

```sql
SELECT a.app_name as name, count() as count
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id AND s._deleted = 0
JOIN core_entities_application AS a FINAL ON a.app_id = s.application_id AND a._deleted = 0
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
GROUP BY a.app_name
ORDER BY count DESC
LIMIT 20
FORMAT JSON
```

With per-app success rate and average duration (for a "top apps" data table):

```sql
SELECT a.app_name as name,
       count() as deploys,
       round(countIf(d.status = 'finalized') * 100.0 / count(), 1) as successRate
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id AND s._deleted = 0
JOIN core_entities_application AS a FINAL ON a.app_id = s.application_id AND a._deleted = 0
WHERE d._deleted = 0
  AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY
GROUP BY a.app_name
ORDER BY deploys DESC
LIMIT 20
FORMAT JSON
```

Reference: this JOIN chain is `Deployment → Scope → Application` — see `SKILL.md` → **SQL rules**
for the canonical join snippet. Never join `scope.app_id` (that column doesn't exist); it's
`scope.application_id = application.app_id`.

## Lead Time (Deployment → Release → Build)

Lead time = time from build creation to a finalized deployment of the release built from it.
Only successful deployments (`status = 'finalized'`) count:

```sql
SELECT round(avg(dateDiff('second', b.created_at, d.created_at)) / 3600, 2) AS avgLeadTimeHours,
       round(median(dateDiff('second', b.created_at, d.created_at)) / 3600, 2) AS medianLeadTimeHours
FROM core_entities_deployment AS d FINAL
JOIN core_entities_release AS r FINAL ON d.release_id = r.id AND r._deleted = 0
JOIN core_entities_build AS b FINAL ON r.build_id = b.id AND b._deleted = 0
WHERE d._deleted = 0
  AND d.status = 'finalized'
  AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 90 DAY)
  AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String}))
FORMAT JSON
```

Lead-time trend by day:

```sql
SELECT toDate(d.created_at) AS day,
       round(avg(dateDiff('second', b.created_at, d.created_at)) / 3600, 2) AS avgLeadTimeHours
FROM core_entities_deployment AS d FINAL
JOIN core_entities_release AS r FINAL ON d.release_id = r.id AND r._deleted = 0
JOIN core_entities_build AS b FINAL ON r.build_id = b.id AND b._deleted = 0
WHERE d._deleted = 0
  AND d.status = 'finalized'
  AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 90 DAY)
  AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String}))
GROUP BY day
ORDER BY day
FORMAT JSON
```

If the date-range picker uses a custom preset (e.g. `last90Days`), the `coalesce` default above
MUST match that preset's duration — see `docs/filters-reference.md` § Date Range Picker Filter
("Custom ranges").

## Global Constraints Recap

- Table names have prefixes: `core_entities_deployment`, `core_entities_build`, `core_entities_scope`, etc.
- ALWAYS use `FINAL` and `_deleted = 0` (except `audit_events`, `scm_code_commits`, `scm_code_repositories`).
- Deployment success = `status = 'finalized'` (NOT `successful`). Build success = `status = 'successful'`.
- Environment (and every scope dimension) lives in `core_entities_scope_dimension` — never a JSON column on the entity.
- Time filtering: `now() - INTERVAL N DAY` (or `HOUR`) — never `TIMESTAMP_SUB`.
- Numeric filters (period days, min counts) arrive as possibly-empty **strings** on first render — read them as `String` and cast defensively (`toUInt32OrZero`/`toInt32OrZero`/`toFloat64OrZero` with a fallback), never as `{x:UInt32}`. An empty value against a numeric placeholder makes the Lake reject the statement (`SQL statement is not allowed`). See `docs/filters-reference.md` § Numeric filters.
- Deployment has NO `application_id` — join through `core_entities_scope.application_id = core_entities_application.app_id`.
- Empty-string checks: use `notEmpty(field)` / `empty(field)`, not `field != ''`.
- Every query ends in `FORMAT JSON` unless it already has an explicit `FORMAT ...` clause.
- Every filter referenced via `{name:Type}` must have a `default` on its schema field — see `docs/filters-reference.md`.
