<!-- JSON code blocks are intentionally minified. Do NOT reformat/prettify. -->

# Post-persist Render Verification

A report that saved cleanly is not guaranteed to render. On first load the frontend sends every
unset filter as the empty string `""`, so the only faithful "does it work in the UI" check is to
run each query the way the FE will. This step runs AFTER persist and BEFORE telling the user the
report is done.

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

| Widget (target) | Empty-param | Default |
|---|---|---|
| `#/properties/total` | ✓ 1 row (155) | ✓ 1 row (302) |
| `#/properties/byEnvironment` | ✓ 2 rows | ✓ 2 rows |
| `#/properties/successRate` | ⚠ 0 rows | ✓ 1 row |

- **✓ renders** — query returned rows.
- **⚠ empty** — query ran but returned 0 rows (renders, but the widget is blank for those params).
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
