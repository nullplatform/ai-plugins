<!-- JSON code blocks are intentionally minified to reduce token usage when this file is loaded into the model context. Do NOT reformat/prettify. -->

# Widget Cookbook for Schema Reports

Patterns optimized for data lake report generation with DynamicForm in `isDisplayMode={true}`. A
report definition is a single object — there is only one format. See
`docs/json-schema-reference.md` for the full envelope.

> **Language note.** The examples below are in English (the default). The dashboard's language is the user's choice, confirmed in the plan step — render every label/title/header/axis in that single chosen language, never mixed. See `SKILL.md` → **Language**.

## Pattern 1: KPI Dashboard

Top-level metrics with charts below.

```json
{"schema":{"type":"object","properties":{"total":{"type":"number","title":"Total"},"successRate":{"type":"number","title":"Success Rate"},"failed":{"type":"number","title":"Failed"},"trend":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"count":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/total","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%"}},{"type":"Control","scope":"#/properties/failed","options":{"widget":"kpi","thresholds":[{"value":0,"color":"#10b981"},{"value":10,"color":"#f59e0b"},{"value":50,"color":"#ef4444"}]}}]},{"type":"Control","scope":"#/properties/trend","label":"Trend","options":{"widget":"line-chart","categoryKey":"date","series":[{"dataKey":"count","name":"Total"}],"xAxisLabel":"Date","yAxisLabel":"Count","height":300}}]},"data":{"total":1234,"successRate":92.5,"failed":93,"trend":[{"date":"2024-01-01","count":45},{"date":"2024-01-02","count":40}]}}
```

## Pattern 2: Distribution Dashboard

Donut/pie chart with table breakdown.

```json
{"schema":{"type":"object","properties":{"distribution":{"type":"array","items":{"type":"object","properties":{"status":{"type":"string"},"count":{"type":"number"}}}},"details":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"total":{"type":"number"},"rate":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Control","scope":"#/properties/distribution","label":"Distribution","options":{"widget":"donut-chart","labelKey":"status","valueKey":"count","height":300}},{"type":"Control","scope":"#/properties/details","label":"Detail","options":{"widget":"data-table","features":["sorting","pagination"]}}]}}
```

## Pattern 3: Comparison Dashboard

Side-by-side charts comparing categories.

```json
{"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Label","text":"##### Comparison by Environment","options":{"format":"markdown"}},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/byEnv","label":"By Environment","options":{"widget":"bar-chart","categoryKey":"env","series":[{"dataKey":"successful","name":"Successful"},{"dataKey":"failed","name":"Failed"}],"xAxisLabel":"Environment","yAxisLabel":"Deployments","height":300,"stacked":true}},{"type":"Control","scope":"#/properties/byStatus","label":"By Status","options":{"widget":"pie-chart","labelKey":"status","valueKey":"count","height":300}}]}]}}
```

## Pattern 4: Reactive Dashboard with indexBy

Let the user select a dimension to filter charts.

```json
{"schema":{"type":"object","properties":{"environment":{"type":"string","enum":["production","staging","development"]},"metricsByEnv":{"type":"object","additionalProperties":{"type":"array"}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Control","scope":"#/properties/environment","label":"Select Environment"},{"type":"Control","scope":"#/properties/metricsByEnv","label":"Metrics","options":{"widget":"bar-chart","indexBy":"environment","categoryKey":"month","series":[{"dataKey":"count","name":"Deployments"}],"xAxisLabel":"Month","yAxisLabel":"Deployments"}}]},"data":{"environment":"production","metricsByEnv":{"production":[{"month":"Jan","count":42},{"month":"Feb","count":38}],"staging":[{"month":"Jan","count":15},{"month":"Feb","count":22}]}}}
```

## Pattern 5: Full Report Dashboard

Complete layout with KPIs, charts, and data table.

```json
{"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Label","text":"##### Executive Summary","options":{"format":"markdown"}},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/totalDeploys","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%"}},{"type":"Control","scope":"#/properties/avgDuration","options":{"widget":"kpi","showBackground":true,"unit":"min"}},{"type":"Control","scope":"#/properties/uniqueApps","options":{"widget":"kpi"}}]},{"type":"Label","text":"##### Trends","options":{"format":"markdown"}},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/dailyTrend","label":"Daily Trend","options":{"widget":"area-chart","categoryKey":"date","series":[{"dataKey":"successful","name":"Successful"},{"dataKey":"failed","name":"Failed"}],"xAxisLabel":"Date","yAxisLabel":"Deployments","height":300,"fillOpacity":0.3}},{"type":"Control","scope":"#/properties/byStatus","label":"By Status","options":{"widget":"donut-chart","labelKey":"status","valueKey":"count","height":300,"showTotal":true}}]},{"type":"Label","text":"##### Detail by Application","options":{"format":"markdown"}},{"type":"Control","scope":"#/properties/topApps","label":"Top Applications","options":{"widget":"data-table","features":["sorting","pagination"],"columns":[{"id":"name","header":"Application","accessor":"name"},{"id":"deploys","header":"Deploys","accessor":"deploys"},{"id":"successRate","header":"Success Rate","accessor":"successRate","formatter":"percentage"},{"id":"avgDuration","header":"Avg Duration","accessor":"avgDuration"}]}}]}}
```

## Pattern 6: Dashboard with Global Filters

Filters at the top that affect all queries. Each query references the filters via `params`.

```json
{"schema":{"type":"object","properties":{"environment":{"type":"string","enum":["","production","staging","development"],"default":""},"dateRange":{"type":"string","enum":["7","30","90"],"default":"30"},"total":{"type":"number","title":"Total"},"trend":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"count":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/environment","label":"Environment"},{"type":"Control","scope":"#/properties/dateRange","label":"Period"}]},{"type":"Control","scope":"#/properties/total","options":{"widget":"kpi"}},{"type":"Control","scope":"#/properties/trend","label":"Trend","options":{"widget":"line-chart","categoryKey":"date","series":[{"dataKey":"count"}],"xAxisLabel":"Date","yAxisLabel":"Count","height":300}}]},"queries":{"total-count":{"source":"SELECT count() as total FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY AND ({environment:String} = '' OR sd.value_slug = {environment:String}) FORMAT JSON","params":{"environment":{"scope":"#/properties/environment"},"days":{"scope":"#/properties/dateRange"}},"target":"#/properties/total"},"daily-trend":{"source":"SELECT toDate(d.created_at) as date, count() as count FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY AND ({environment:String} = '' OR sd.value_slug = {environment:String}) GROUP BY date ORDER BY date FORMAT JSON","params":{"environment":{"scope":"#/properties/environment"},"days":{"scope":"#/properties/dateRange"}},"target":"#/properties/trend"}}}
```

## Pattern 7: Cascade Filters (namespace → application)

Dynamic enum filters where one depends on another.

```json
{"schema":{"type":"object","properties":{"namespaceId":{"type":"string","default":""},"applicationId":{"type":"string","default":""},"deploys":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"count":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/namespaceId","label":"Namespace"},{"type":"Control","scope":"#/properties/applicationId","label":"Application"}]},{"type":"Control","scope":"#/properties/deploys","label":"Deployments","options":{"widget":"bar-chart","categoryKey":"name","series":[{"dataKey":"count"}],"xAxisLabel":"Application","yAxisLabel":"Deployments"}}]},"queries":{"available-namespaces":{"source":"SELECT DISTINCT namespace_id as id, namespace_name as name FROM core_entities_namespace FINAL WHERE _deleted = 0 FORMAT JSON","target":"#/properties/namespaceId","mapping":"enum"},"available-applications":{"source":"SELECT DISTINCT a.app_id as id, a.app_name as name FROM core_entities_application AS a FINAL JOIN core_entities_namespace AS n FINAL ON a.namespace_id = n.namespace_id AND n._deleted = 0 WHERE a._deleted = 0 AND ({namespace_id:String} = '' OR a.namespace_id = {namespace_id:String}) FORMAT JSON","params":{"namespace_id":{"scope":"#/properties/namespaceId"}},"target":"#/properties/applicationId","mapping":"enum"},"deploys-by-app":{"source":"SELECT a.app_name as name, count() as count FROM core_entities_deployment AS d FINAL JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id AND s._deleted = 0 JOIN core_entities_application AS a FINAL ON a.app_id = s.application_id AND a._deleted = 0 WHERE d._deleted = 0 AND ({namespace_id:String} = '' OR a.namespace_id = {namespace_id:String}) AND ({application_id:String} = '' OR a.app_id = {application_id:String}) GROUP BY a.app_name ORDER BY count DESC LIMIT 20 FORMAT JSON","params":{"namespace_id":{"scope":"#/properties/namespaceId"},"application_id":{"scope":"#/properties/applicationId"}},"target":"#/properties/deploys"}}}
```

## Pattern 8: Multi-Select Filter

Filter with multiple selectable values using `Array(String)`.

```json
{"schema":{"type":"object","properties":{"statuses":{"type":"array","items":{"type":"string","enum":["finalized","failed","in_progress","pending"]},"default":[]},"deploysByStatus":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"count":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Control","scope":"#/properties/statuses","label":"Statuses"},{"type":"Control","scope":"#/properties/deploysByStatus","label":"Deployments by Date","options":{"widget":"line-chart","categoryKey":"date","series":[{"dataKey":"count"}],"xAxisLabel":"Date","yAxisLabel":"Count","height":300}}]},"queries":{"deploys-filtered":{"source":"SELECT toDate(created_at) as date, count() as count FROM core_entities_deployment FINAL WHERE _deleted = 0 AND (length({statuses:Array(String)}) = 0 OR status IN {statuses:Array(String)}) GROUP BY date ORDER BY date FORMAT JSON","params":{"statuses":{"scope":"#/properties/statuses"}},"target":"#/properties/deploysByStatus"}}}
```

## Pattern 9: Dashboard with Date Range Picker

Precise date range selection with environment filter, KPIs, and trend chart.

```json
{"schema":{"type":"object","properties":{"environment":{"type":"string","enum":["","production","staging","development"],"default":""},"startDate":{"type":"string","format":"date-time","default":""},"endDate":{"type":"string","format":"date-time","default":""},"total":{"type":"number","title":"Total Deployments"},"successRate":{"type":"number","title":"Success Rate"},"trend":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"count":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/environment","label":"Environment"},{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last7Days","allowedRanges":["today","last7Days","thisWeek","thisMonth"],"disableFuture":true}}]},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/total","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%"}}]},{"type":"Control","scope":"#/properties/trend","label":"Trend","options":{"widget":"area-chart","categoryKey":"date","series":[{"dataKey":"count","name":"Deployments"}],"xAxisLabel":"Date","yAxisLabel":"Deployments","height":300}}]},"queries":{"total-count":{"source":"SELECT count() as total FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND ({environment:String} = '' OR sd.value_slug = {environment:String}) AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String})) FORMAT JSON","target":"#/properties/total"},"success-rate":{"source":"SELECT round(countIf(status = 'finalized') * 100.0 / count(), 1) as successRate FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND ({environment:String} = '' OR sd.value_slug = {environment:String}) AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String})) FORMAT JSON","target":"#/properties/successRate"},"daily-trend":{"source":"SELECT toDate(d.created_at) as date, count() as count FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND ({environment:String} = '' OR sd.value_slug = {environment:String}) AND d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String})) GROUP BY date ORDER BY date FORMAT JSON","target":"#/properties/trend"}}}
```

## Pattern 10: Rich Dashboard (fully enriched)

Complete dashboard applying all enrichment rules: widget backgrounds, KPI thresholds, axis labels, chip formatters, fixed columns, section subtitles, donut totals, semantic colors, and layout proportions.

```json
{"schema":{"type":"object","properties":{"startDate":{"type":"string","format":"date-time","default":""},"endDate":{"type":"string","format":"date-time","default":""},"totalDeploys":{"type":"number","title":"Total Deployments"},"successRate":{"type":"number","title":"Success Rate"},"avgDuration":{"type":"number","title":"Avg Duration"},"failedCount":{"type":"number","title":"Failed"},"dailyTrend":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"successful":{"type":"number"},"failed":{"type":"number"}}}},"byStatus":{"type":"array","items":{"type":"object","properties":{"status":{"type":"string"},"count":{"type":"number"}}}},"recentDeploys":{"type":"array","items":{"type":"object","properties":{"appName":{"type":"string"},"environment":{"type":"string"},"status":{"type":"string"},"duration":{"type":"number"},"createdAt":{"type":"string"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last30Days","allowedRanges":["today","last7Days","thisWeek","last30Days","thisMonth"],"disableFuture":true}}]},{"type":"Label","text":"##### Impact Summary","options":{"format":"markdown"}},{"type":"HorizontalLayout","options":{"columns":[3,3,3,3]},"elements":[{"type":"Control","scope":"#/properties/totalDeploys","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%","thresholds":[{"value":90,"color":"success"},{"value":70,"color":"warning"},{"value":0,"color":"error"}]}},{"type":"Control","scope":"#/properties/avgDuration","options":{"widget":"kpi","showBackground":true,"unit":"min","thresholds":[{"value":0,"color":"success"},{"value":10,"color":"warning"},{"value":30,"color":"error"}]}},{"type":"Control","scope":"#/properties/failedCount","options":{"widget":"kpi","showBackground":true,"thresholds":[{"value":0,"color":"success"},{"value":5,"color":"warning"},{"value":20,"color":"error"}]}}]},{"type":"Label","text":"##### Deployment Trend\nDaily activity broken down by result over the selected period.","options":{"format":"markdown"}},{"type":"HorizontalLayout","options":{"columns":[8,4]},"elements":[{"type":"Control","scope":"#/properties/dailyTrend","label":"Daily Activity","options":{"widget":"area-chart","showBackground":true,"categoryKey":"date","series":[{"dataKey":"successful","name":"Successful"},{"dataKey":"failed","name":"Failed"}],"xAxisLabel":"Date","yAxisLabel":"Deployments","height":320,"fillOpacity":0.3,"showLegend":true,"colors":["#22c55e","#ef4444"]}},{"type":"Control","scope":"#/properties/byStatus","label":"By Status","options":{"widget":"donut-chart","showBackground":true,"labelKey":"status","valueKey":"count","height":320,"showTotal":true,"totalLabel":"Total","colors":["#22c55e","#ef4444","#f59e0b","#3b82f6"]}}]},{"type":"Label","text":"##### Recent Deployments\nLatest deployments sorted by date.","options":{"format":"markdown"}},{"type":"Control","scope":"#/properties/recentDeploys","label":"Detail","options":{"widget":"data-table","features":["sorting","pagination"],"columns":[{"id":"appName","header":"Application","accessor":"appName","fixed":{"position":"left"}},{"id":"environment","header":"Environment","accessor":"environment","formatter":{"type":"chip","config":{"mapping":{"production":{"label":"Production","color":"error"},"staging":{"label":"Staging","color":"warning"},"development":{"label":"Development","color":"info"}}}}},{"id":"status","header":"Status","accessor":"status","formatter":{"type":"chip","config":{"mapping":{"finalized":{"label":"Successful","color":"success","variant":"tonal"},"failed":{"label":"Failed","color":"error","variant":"tonal"},"in_progress":{"label":"In Progress","color":"warning","variant":"tonal"}}}}},{"id":"duration","header":"Duration","accessor":"duration"},{"id":"createdAt","header":"Date","accessor":"createdAt","formatter":{"type":"date","format":"relative","config":{"tooltip":{"enabled":true,"format":"absolute","placement":"top"}}}}]}}]}}
```

## Pattern 11: Date Range Picker with Custom Ranges

Custom date presets (90 days, 6 months) alongside built-in ranges. The `initialPreset` references a custom range key — it MUST exist in `customRanges`. The SQL `coalesce` default MUST match the `initialPreset` duration (90 days here).

```json
{"schema":{"type":"object","properties":{"startDate":{"type":"string","format":"date-time","default":""},"endDate":{"type":"string","format":"date-time","default":""},"avgLeadTimeHours":{"type":"number","title":"Avg Lead Time"},"medianLeadTimeHours":{"type":"number","title":"Median Lead Time"},"leadTimeTrend":{"type":"array","items":{"type":"object","properties":{"day":{"type":"string"},"avgLeadTimeHours":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last90Days","allowedRanges":["last7Days","last30Days"],"customRanges":[{"key":"last90Days","label":"Last 90 days","diffDays":90},{"key":"last6Months","label":"Last 6 months","diffDays":180}],"disableFuture":true}}]},{"type":"Label","text":"##### Summary","options":{"format":"markdown"}},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/avgLeadTimeHours","options":{"widget":"kpi","suffix":"hours"}},{"type":"Control","scope":"#/properties/medianLeadTimeHours","options":{"widget":"kpi","suffix":"hours"}}]},{"type":"Control","scope":"#/properties/leadTimeTrend","label":"Lead Time Trend","options":{"widget":"line-chart","categoryKey":"day","series":[{"dataKey":"avgLeadTimeHours","name":"Lead Time (hrs)"}],"xAxisLabel":"Date","yAxisLabel":"Hours","height":300}}]},"queries":{"avg-lead-time":{"source":"SELECT round(avg(dateDiff('second',b.created_at,d.created_at))/3600,2) AS avgLeadTimeHours,round(median(dateDiff('second',b.created_at,d.created_at))/3600,2) AS medianLeadTimeHours FROM core_entities_deployment AS d FINAL JOIN core_entities_release AS r FINAL ON d.release_id=r.id AND r._deleted=0 JOIN core_entities_build AS b FINAL ON r.build_id=b.id AND b._deleted=0 WHERE d._deleted=0 AND d.status='finalized' AND d.created_at>=coalesce(parseDateTimeBestEffortOrNull({startDate:String}),now()-INTERVAL 90 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at<=parseDateTimeBestEffortOrNull({endDate:String})) FORMAT JSON","target":"#/properties/avgLeadTimeHours"},"lead-time-trend":{"source":"SELECT toDate(d.created_at) AS day,round(avg(dateDiff('second',b.created_at,d.created_at))/3600,2) AS avgLeadTimeHours FROM core_entities_deployment AS d FINAL JOIN core_entities_release AS r FINAL ON d.release_id=r.id AND r._deleted=0 JOIN core_entities_build AS b FINAL ON r.build_id=b.id AND b._deleted=0 WHERE d._deleted=0 AND d.status='finalized' AND d.created_at>=coalesce(parseDateTimeBestEffortOrNull({startDate:String}),now()-INTERVAL 90 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at<=parseDateTimeBestEffortOrNull({endDate:String})) GROUP BY day ORDER BY day FORMAT JSON","target":"#/properties/leadTimeTrend"}}}
```

## Pattern: Clickable links

The FE `LinkFormatterCell` renders the anchor from **static** `config.targetUrl` / `config.displayText`. The row's own value is never used as the `href`. There is no templating in the JSON UI schema path today.

### A. Static link column (same URL every row) — WORKS

Only useful when every row genuinely points to the same URL (e.g., a "Docs" column linking to the same runbook). Every row will render the same `displayText` with the same `href`:

```json
{"id":"docs","header":"Runbook","accessor":"docs","formatter":{"type":"link","config":{"targetUrl":"https://docs.nullplatform.com/runbooks/migration","displayText":"View runbook","target":"_blank","underline":"hover"}}}
```

The data query still needs to return *something* for the `docs` accessor per row — any non-null value will do; the cell ignores it for the href.

### B. Static link in a Label (documentation / context) — WORKS

Use a `Label` with `format: "markdown"` when you want a single link outside the table (e.g. a "Full migration report" link below the KPIs):

```json
{"type":"Label","text":"##### Lambda Migration\nProject details in [Confluence](https://nullplatform.atlassian.net/wiki/.../migration) · Tracking board in [Jira](https://nullplatform.atlassian.net/.../JIRA-123).","options":{"format":"markdown"}}
```

`Label.text` is static — it does NOT read from any schema property and cannot render SQL output.

### C. Per-row URLs — NOT SUPPORTED (today)

The common ask — "one row per action item with a clickable link to that item" — does not have a working JSON pattern. The FE `LinkFormatterCell` cannot resolve `targetUrl` from row data via JSON config; that requires a function formatter, which is not JSON-serialisable.

**Workaround**: emit the URL as a plain text column and inform the user:

```json
{"id":"url","header":"URL","accessor":"url","formatter":{"type":"text","typography":{"maxLines":1}}}
```

```sql
SELECT
  action_item_id,
  nrn,
  concat('https://nullplatform.app.nullplatform.io/account/', account_id,
         '/namespace/', namespace_id, '/action-item/', action_item_id) AS url
FROM governance_action_items_action_items
```

When the user asks for a clickable link column, explain the limitation explicitly: the `link` formatter currently only accepts static URL/text — per-row URLs are not supported. Keep the URL as a text column; making it clickable per row requires a frontend fix (`frontend-packages/react-material-renderers/DataTableControl.utils.ts` → resolve templates like `${row.<accessor>}` before passing `config` to the cell). Reply to the user in the language they are writing to you (see the Language rule in `SKILL.md`).

## Dashboard Enrichment Rules

Apply these rules to every dashboard to produce polished, production-quality output. Do NOT generate flat/plain dashboards — always enrich.

### Widget Backgrounds

Always set `showBackground: true` in the options of ALL widgets **except `data-table`**. This adds a subtle tinted background that gives each widget visual separation and a polished look.

- **KPI**: `"options": { "widget": "kpi", "showBackground": true }`
- **Charts** (line-chart, area-chart, bar-chart, pie-chart, donut-chart, radial-bar-chart): `"options": { "widget": "line-chart", "showBackground": true, ... }`
- **Data tables**: do NOT set `showBackground` — tables have their own visual structure

### Axis Labels (cartesian charts)

Always set `xAxisLabel` and `yAxisLabel` on line, area, and bar charts. Use short, descriptive names (e.g. `"Date"`, `"Count"`, `"Deployments"`) in the dashboard's confirmed language (default English). Some legacy examples show Spanish strings — they illustrate JSON shape, not the output language.

### KPI Thresholds

Always add `thresholds` to KPI widgets when the metric has a natural good/bad scale. Use semantic colors:

```json
{"thresholds":[{"value":90,"color":"success"},{"value":70,"color":"warning"},{"value":0,"color":"error"}]}
```

For metrics where lower is better (error count, failure rate), invert the order.

### KPI Precision

**ALWAYS set `precision` on KPI widgets.** Use `precision: 0` only for pure counts (total deploys, number of apps). For everything else:

- Rates and percentages (success rate, error rate): `precision: 1` (e.g., 92.5%)
- Averages and durations: `precision: 2` (e.g., 3.14 min)
- Ratios: `precision: 2`

Omitting `precision` defaults to 2 decimal places. Always set it explicitly for clarity.

### Table Column Types

**CRITICAL: Always use `"type": "datetime"` for date/timestamp columns** in the `columns` array (e.g., `createdAt`, `date`, `updatedAt`, `day`, `eventDate`). This generates `format: "date-time"` in the JSON Schema, which auto-applies relative date formatting with absolute tooltip on hover. Using `"type": "string"` for date columns causes raw date strings to display as-is (garbled output).

### Table Column Formatters

When defining explicit `tableColumns` on a data-table, apply formatters based on the data type:

| Data pattern                                                                                                                             | Formatter                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status/state values (`finalized`, `failed`, `pending`, `active`)                                                                         | `{"type": "chip", "config": {"mapping": {"finalized": {"label": "Successful", "color": "success"}, "failed": {"label": "Failed", "color": "error"}, "pending": {"label": "Pending", "color": "warning"}}}}` |
| URLs or links (see "Clickable links" above — per-row URLs in tables are NOT supported via JSON UI schema today)                          | `{"type": "link", "config": {"targetUrl": "<static url>", "displayText": "<static text>", "target": "_blank"}}`                                                                                             |
| Date/day columns (any column containing dates, days, timestamps — including columns named `day`, `date`, `createdAt`, `eventDate`, etc.) | `{"type": "date", "format": "relative", "config": {"tooltip": {"enabled": true, "format": "absolute", "placement": "top"}}}`                                                                                |
| Percentage/rate columns (success rate, error rate, etc.)                                                                                 | `{"type": "text", "config": {"suffix": "%"}}` combined with `"typography": {"color": "success.main"}` for high values or use chip with thresholds                                                           |
| Long text                                                                                                                                | Add `"typography": {"maxLines": 2}` to truncate                                                                                                                                                             |

### Fixed Columns in Tables

Pin identifying columns (name, entity, application) to the left so they stay visible when scrolling:

```json
{"id":"appName","header":"Application","accessor":"appName","fixed":{"position":"left"}}
```

### Donut/Pie Charts

Always set `showTotal: true` and a meaningful `totalLabel` on donut charts so the center shows the aggregate, and always specify `donutSize` for a consistent appearance:

```json
{"widget":"donut-chart","labelKey":"status","valueKey":"count","donutSize":"55%","showTotal":true,"totalLabel":"Total"}
```

### Chart Colors

Use explicit `colors` arrays when series have semantic meaning:

- Success/failure: `["#22c55e", "#ef4444"]`
- Multi-status: `["#22c55e", "#ef4444", "#f59e0b", "#3b82f6"]` (success, error, warning, info)
- Single series: use a theme-appropriate color like `["#6366f1"]` or `["#3b82f6"]`

### Chart Styling Defaults

- **Bar charts**: always set `borderRadius: 4` for rounded corners
- **Area/Line charts**: use `curve: "smooth"` for time-series trends, `"straight"` for discrete/categorical data
- **Area charts**: set `fillOpacity: 0.3` when multiple series overlap

### Section Headers (Markdown Labels)

Labels with `format: "markdown"` render full Markdown via MUI-styled components. Use them for more than just titles — the renderer supports headings, bold, italic, lists, blockquotes, dividers, links, inline code, and tables.

Label `text` is static (hand-written in the ui_schema) — it is not bound to a schema property and therefore cannot render SQL-produced rows. Use Labels for documentation links, references to runbooks, or section headers with a clickable source link. For per-row URLs, see "Clickable links" above — there is no data-bound markdown widget today.

**Section headers with context** — add a subtitle line when the section benefits from it:

```json
{"type":"Label","text":"##### Deployment Trend\nDaily activity broken down by result over the selected period.","options":{"format":"markdown"}}
```

**Bullet lists** — summarize what a section shows or provide interpretation hints:

```json
{"type":"Label","text":"##### Summary\n- **Successful**: deployments that reached `finalized`\n- **Failed**: includes `failed` and `cancelled`\n- **Rollbacks**: manually reverted","options":{"format":"markdown"}}
```

**Blockquotes** — for disclaimers, data freshness notes, or caveats:

```json
{"type":"Label","text":"> Data refreshes every 15 minutes. The selected period applies to every metric.","options":{"format":"markdown"}}
```

**Dividers** — use `---` as a visual separator between major dashboard sections:

```json
{"type":"Label","text":"---","options":{"format":"markdown"}}
```

Guidelines:

- Use `#####` (h5) for section titles — it renders as `subtitle2` with bold weight
- Add subtitles on trend charts and distribution breakdowns, skip on self-explanatory sections (KPI rows)
- Use bold (`**text**`) to highlight key terms in descriptions
- Use bullet lists sparingly — only when the section needs a legend or interpretation guide
- Use blockquotes for notes about data scope, freshness, or methodology
- Use dividers to separate major dashboard areas (e.g. between overview and detail sections)

### Layout Proportions

Use `columns` on `HorizontalLayout` to give more space to the primary visualization:

- Chart + donut: `{"columns": [8, 4]}`
- Chart + chart: `{"columns": [6, 6]}`
- 4 KPIs: `{"columns": [3, 3, 3, 3]}`

### Layout Structure

Never wrap a single widget in a `VerticalLayout` — place it directly as an element of the parent layout. When there are 2 charts that complement each other (e.g. trend + distribution, by-time + by-category), place them side-by-side in a `HorizontalLayout` with appropriate `columns` proportions instead of stacking them vertically. Full-width charts can go directly as elements of the root `VerticalLayout`.

### Sparkline Cells in Tables

When a table has a time-series column per row (e.g. trend data, daily counts), use a chart cell to render a sparkline:

```json
{"id":"trend","header":"Trend","accessor":"trend","cell":{"widget":"area-chart","categoryKey":"date","series":[{"dataKey":"count"}],"height":40,"colors":["#3b82f6"]}}
```

Use this sparingly — only when the table represents entities that each have their own time-series data.

### Table Text Handling

For columns with potentially long text (names, descriptions, URLs), add typography truncation so the table stays clean:

```json
{"id":"desc","header":"Description","accessor":"desc","formatter":{"type":"text","typography":{"maxLines":2}}}
```

For columns that benefit from case normalization (environments, HTTP methods), use `transform`:

```json
{"formatter":{"type":"text","typography":{"transform":"uppercase"}}}
```

### DataTable Empty State

Always configure `emptyState` with a descriptive message so empty tables don't show a blank area:

```json
{"widget":"data-table","emptyState":{"title":"No data available","description":"Try adjusting the filters or date range."}}
```

### DataTable Pagination

When enabling `pagination` in features, always set explicit page size options:

```json
{"features":["sorting","pagination"],"pagination":{"pageSize":10,"pageSizeOptions":[10,25,50]}}
```

## Layout Tips

- **Filter row first**: Always put filters in a `HorizontalLayout` at the top
- **KPI row**: Use `HorizontalLayout` with 3-4 KPI controls below filters
- **Section headers**: Use `Label` with `format: "markdown"` and `#####` for h5 headers
- **Chart pairs**: Put 2 charts in a `HorizontalLayout` for side-by-side comparison
- **Data table**: Always at the bottom for detailed drill-down data
- **Vertical stacking**: Wrap everything in a top-level `VerticalLayout`
- **Max 50 items** in chart arrays for readability — aggregate larger datasets
- **Date range picker**: Only add a Control for the start date field — the end date is managed automatically via `endDateScope`. Do NOT add a separate Control for `endDate`.
- **Global filters**: Reference the same `params` in all data queries for consistent filtering
- **Axis labels**: Always set `xAxisLabel` and `yAxisLabel` on cartesian charts (line, area, bar) so readers know what each axis represents. Use short, descriptive names (e.g. `"Date"`, `"Count"`, `"Seconds"`) in the dashboard's confirmed language (default English). Some examples in this cookbook show legacy Spanish strings — those illustrate JSON shape, not the output language
- **Always apply the Dashboard Enrichment Rules above** — never generate flat/plain dashboards. See Pattern 10 for a fully enriched example.
