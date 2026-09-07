<!-- JSON code blocks are intentionally minified. Do NOT reformat/prettify. -->

# Post-persist Render Verification

A report that saved cleanly is not guaranteed to render. On first load the frontend sends every
unset filter as the empty string `""`, so the only faithful "does it work in the UI" check is to
run each query the way the FE will. This step runs AFTER persist and BEFORE telling the user the
report is done.

## Step 0 — Binding check (static, no queries needed)

Run this BEFORE the query runs: a query can return perfect rows into a widget that will never render
them. It needs nothing but the definition — no Lake, no token, no write — so run it **at design time
too** (`SKILL.md` §4 / §5), before the first `POST`. Repeating it here against the persisted copy
costs nothing and catches anything the write reshaped. For every entry in `queries`, check its
`target` against `schema.properties`:

- **Target resolves?** The property named by `target` exists. If it does not, the widget renders
  blank with no error anywhere — see `docs/json-schema-reference.md` § "The binding contract".
- **Every widget has a query?** Walk it the OTHER way too: for each `Control` in the `ui_schema` that
  carries `options.widget` (or whose property is an array), some query must `target` it. A widget no
  query writes to renders a tile reading **`--`** (or an empty chart) — it never gets a `queryStates`
  entry, so there is no skeleton and no error to notice, and a `--` KPI reads as a real zero. That is
  why this direction cannot be inferred from the query list. Filter controls are exempt: users populate those.
- **Shape matches the widget?** Array widgets (all charts, `data-table`) need `type: "array"` with
  `items.properties`; `kpi` needs `type: "number"`.
- **Numeric columns typed?** Every numeric field in `items.properties` is `number` or `integer`, or
  the Lake's string numbers reach the chart uncast.
- **Aliases match?** Each SQL alias equals the key its widget reads (`labelKey`/`valueKey`,
  `categoryKey`/`series[].dataKey`, or the column `accessor`).

A failure here is a **✗**, exactly like a failing query — fix it and `PATCH` before reporting done.
This check is free, catches the most common silent breakage, and no amount of query running can
substitute for it.

## Procedure

For each entry in the report's `queries`, take its `source` (the real `SELECT`, ending in
`FORMAT JSON`) and run it through the sibling np-lake script twice — once with **every filter
placeholder empty** (`--param x=`), once with the **filter defaults**:

```bash
# empty-param run — what the FE sends on first render
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --format tsv --param days= --param environment= "<source>"
# default run
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --format tsv --param days=7 --param environment= "<source>"
```

Pass exactly the params each query declares (see its `params` map). Count the returned rows.

## Per-widget status table

Report a table mapping each query's `target` to its result in both runs:

All rows must belong to the SAME report — this table is the dashboard's verdict, not a sample:

| Widget (target) | Binding | Empty-param | Default |
|---|---|---|---|
| `#/properties/total` | ✓ number | ✓ 1 row (155) | ✓ 1 row (302) |
| `#/properties/byEnvironment` | ✓ array+items | ✓ 2 rows | ✓ 2 rows |
| `#/properties/successRate` | ✓ number | ⚠ 0 rows | ✓ 1 row |
| `#/properties/trend` | ✗ not in schema | ✓ 30 rows | ✓ 30 rows |

Binding column — state the declared shape, or why it fails:

- **✓ number** / **✓ array+items** — the target resolves and its shape matches its widget.
- **✗ not in schema** — no such property; **✗ shape** — declared, but wrong type for the widget;
  **✗ no query** — a widget nothing targets (it will render `--` / empty, with no error).

Query columns:

- **✓ renders** — query returned rows.
- **⚠ empty** — query ran but returned 0 rows (renders, but the widget is blank for those params).
- **✗ binding** — the target is missing from the schema, or its shape does not match the widget. The
  query works but the widget will render blank. Fix the schema and `PATCH`, then re-check.
- **✗ error** — query failed. The dashboard is BROKEN in the UI. Fix the SQL and `PATCH` the report,
  then re-run this verification. Never leave a `✗` and call the report done.

## Empty / anomalous data guards

Using the preview numbers, narrate (do not block) in the final summary:

- **All-empty / 0 rows:** "the dashboard renders but is empty for the current defaults — likely no
  data in the selected period, or the filters are too narrow." Suggest widening the period.
- **Anomalous rate** (0% or 100% success, or total = 0): explain it with a quick drill so a genuine
  result is not mistaken for a bug. Example drill and phrasing: run
  `SELECT status, count() c FROM core_entities_deployment FINAL WHERE _deleted = 0 AND created_at > now() - INTERVAL 7 DAY GROUP BY status ORDER BY c DESC FORMAT JSON`
  and report "this org's deployments in the window are mostly `cancelled`/`rolled_back`; the low
  success rate is real, not a report bug."

## Caveat

`ch_query.sh` hits the same Customer Lake the FE proxy queries, so it is the closest faithful
simulation available to the skill — state this when reporting the table. If the Lake is unreachable
or the token is expired, say the render check was skipped and the dashboard is unverified.
