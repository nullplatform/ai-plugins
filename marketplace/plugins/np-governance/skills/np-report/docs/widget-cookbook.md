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
The status/environment chips carry no `mapping`: a table chip renders the CELL VALUE, so per-value
labels come from the query (`multiIf(...) AS estado`). See "Chips in tables" below.

```json
{"schema":{"type":"object","properties":{"startDate":{"type":"string","format":"date-time","default":""},"endDate":{"type":"string","format":"date-time","default":""},"totalDeploys":{"type":"number","title":"Total Deployments"},"successRate":{"type":"number","title":"Success Rate"},"avgDuration":{"type":"number","title":"Avg Duration"},"failedCount":{"type":"number","title":"Failed"},"dailyTrend":{"type":"array","items":{"type":"object","properties":{"date":{"type":"string"},"successful":{"type":"number"},"failed":{"type":"number"}}}},"byStatus":{"type":"array","items":{"type":"object","properties":{"status":{"type":"string"},"count":{"type":"number"}}}},"recentDeploys":{"type":"array","items":{"type":"object","properties":{"appName":{"type":"string"},"environment":{"type":"string"},"status":{"type":"string"},"duration":{"type":"number"},"createdAt":{"type":"string"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last30Days","allowedRanges":["today","last7Days","thisWeek","last30Days","thisMonth"],"disableFuture":true}}]},{"type":"Label","text":"##### Impact Summary","options":{"format":"markdown"}},{"type":"HorizontalLayout","options":{"columns":[3,3,3,3]},"elements":[{"type":"Control","scope":"#/properties/totalDeploys","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%","thresholds":[{"value":90,"color":"success"},{"value":70,"color":"warning"},{"value":0,"color":"error"}]}},{"type":"Control","scope":"#/properties/avgDuration","options":{"widget":"kpi","showBackground":true,"unit":"min","thresholds":[{"value":0,"color":"success"},{"value":10,"color":"warning"},{"value":30,"color":"error"}]}},{"type":"Control","scope":"#/properties/failedCount","options":{"widget":"kpi","showBackground":true,"thresholds":[{"value":0,"color":"success"},{"value":5,"color":"warning"},{"value":20,"color":"error"}]}}]},{"type":"Label","text":"##### Deployment Trend\nDaily activity broken down by result over the selected period.","options":{"format":"markdown"}},{"type":"HorizontalLayout","options":{"columns":[8,4]},"elements":[{"type":"Control","scope":"#/properties/dailyTrend","label":"Daily Activity","options":{"widget":"area-chart","showBackground":true,"categoryKey":"date","series":[{"dataKey":"successful","name":"Successful"},{"dataKey":"failed","name":"Failed"}],"xAxisLabel":"Date","yAxisLabel":"Deployments","height":320,"fillOpacity":0.3,"showLegend":true,"colors":["#22c55e","#ef4444"]}},{"type":"Control","scope":"#/properties/byStatus","label":"By Status","options":{"widget":"donut-chart","showBackground":true,"labelKey":"status","valueKey":"count","height":320,"showTotal":true,"totalLabel":"Total","colors":["#22c55e","#ef4444","#f59e0b","#3b82f6"]}}]},{"type":"Label","text":"##### Recent Deployments\nLatest deployments sorted by date.","options":{"format":"markdown"}},{"type":"Control","scope":"#/properties/recentDeploys","label":"Detail","options":{"widget":"data-table","features":["sorting","pagination"],"columns":[{"id":"appName","header":"Application","accessor":"appName","fixed":{"position":"left"}},{"id":"environment","header":"Environment","accessor":"environment","formatter":{"type":"chip","config":{"size":"small"}}},{"id":"status","header":"Status","accessor":"status","formatter":{"type":"chip","config":{"size":"small"}}},{"id":"duration","header":"Duration","accessor":"duration"},{"id":"createdAt","header":"Date","accessor":"createdAt","formatter":{"type":"date","format":"relative","config":{"tooltip":{"enabled":true,"format":"absolute","placement":"top"}}}}]}}]}}
```

## Pattern 11: Date Range Picker with Custom Ranges

Custom date presets (90 days, 6 months) alongside built-in ranges. Note the two KPI queries: one `SELECT`
computing both metrics cannot fill both tiles, so each KPI gets its own entry with the same `source`
and a different `target` — identical source+params coalesce into a single Lake call. A KPI with no
query of its own renders a tile reading `--`, which reads as a real zero rather than as a
misconfiguration — it never gets a `queryStates` entry, so no skeleton and no error is shown.
Use `unit`, never `suffix`: a `suffix` in a KPI's `options` is not read — only `unit`, `precision`
and `thresholds` reach the tile — so the unit silently never appears. The `initialPreset` references a custom range key — it MUST exist in `customRanges`. The SQL `coalesce` default MUST match the `initialPreset` duration (90 days here).

```json
{"schema":{"type":"object","properties":{"startDate":{"type":"string","format":"date-time","default":""},"endDate":{"type":"string","format":"date-time","default":""},"avgLeadTimeHours":{"type":"number","title":"Avg Lead Time"},"medianLeadTimeHours":{"type":"number","title":"Median Lead Time"},"leadTimeTrend":{"type":"array","items":{"type":"object","properties":{"day":{"type":"string"},"avgLeadTimeHours":{"type":"number"}}}}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last90Days","allowedRanges":["last7Days","last30Days"],"customRanges":[{"key":"last90Days","label":"Last 90 days","diffDays":90},{"key":"last6Months","label":"Last 6 months","diffDays":180}],"disableFuture":true}}]},{"type":"Label","text":"##### Summary","options":{"format":"markdown"}},{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/avgLeadTimeHours","options":{"widget":"kpi","unit":"hours"}},{"type":"Control","scope":"#/properties/medianLeadTimeHours","options":{"widget":"kpi","unit":"hours"}}]},{"type":"Control","scope":"#/properties/leadTimeTrend","label":"Lead Time Trend","options":{"widget":"line-chart","categoryKey":"day","series":[{"dataKey":"avgLeadTimeHours","name":"Lead Time (hrs)"}],"xAxisLabel":"Date","yAxisLabel":"Hours","height":300}}]},"queries":{"avg-lead-time":{"source":"SELECT round(avg(dateDiff('second',b.created_at,d.created_at))/3600,2) AS avgLeadTimeHours,round(median(dateDiff('second',b.created_at,d.created_at))/3600,2) AS medianLeadTimeHours FROM core_entities_deployment AS d FINAL JOIN core_entities_release AS r FINAL ON d.release_id=r.id AND r._deleted=0 JOIN core_entities_build AS b FINAL ON r.build_id=b.id AND b._deleted=0 WHERE d._deleted=0 AND d.status='finalized' AND d.created_at>=coalesce(parseDateTimeBestEffortOrNull({startDate:String}),now()-INTERVAL 90 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at<=parseDateTimeBestEffortOrNull({endDate:String})) FORMAT JSON","target":"#/properties/avgLeadTimeHours"},"median-lead-time":{"source":"SELECT round(avg(dateDiff('second',b.created_at,d.created_at))/3600,2) AS avgLeadTimeHours,round(median(dateDiff('second',b.created_at,d.created_at))/3600,2) AS medianLeadTimeHours FROM core_entities_deployment AS d FINAL JOIN core_entities_release AS r FINAL ON d.release_id=r.id AND r._deleted=0 JOIN core_entities_build AS b FINAL ON r.build_id=b.id AND b._deleted=0 WHERE d._deleted=0 AND d.status='finalized' AND d.created_at>=coalesce(parseDateTimeBestEffortOrNull({startDate:String}),now()-INTERVAL 90 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at<=parseDateTimeBestEffortOrNull({endDate:String})) FORMAT JSON","target":"#/properties/medianLeadTimeHours"},"lead-time-trend":{"source":"SELECT toDate(d.created_at) AS day,round(avg(dateDiff('second',b.created_at,d.created_at))/3600,2) AS avgLeadTimeHours FROM core_entities_deployment AS d FINAL JOIN core_entities_release AS r FINAL ON d.release_id=r.id AND r._deleted=0 JOIN core_entities_build AS b FINAL ON r.build_id=b.id AND b._deleted=0 WHERE d._deleted=0 AND d.status='finalized' AND d.created_at>=coalesce(parseDateTimeBestEffortOrNull({startDate:String}),now()-INTERVAL 90 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at<=parseDateTimeBestEffortOrNull({endDate:String})) GROUP BY day ORDER BY day FORMAT JSON","target":"#/properties/leadTimeTrend"}}}
```

## Pattern 12: Tabbed sections

Split one dashboard into tabs with `Categorization` + `Category`. This is the platform's own tabs
element — it lives in the closed UI vocabulary and ships a renderer, so it needs no workaround. Use it
when a single dashboard covers several distinct views (overview / detail / per-team) that share the
same filters. Tabs are the default rendering; `Categorization.options.variant: "stepper"` turns the
same element into a step-by-step wizard instead.

**Filters stay global — that is the point.** A filter is derived from the queries that reference it in
`params`, not from where its Control sits in the layout, so ONE filter row declared above the
`Categorization` drives every query in every tab. Never repeat a filter per tab.

**Tabs do NOT defer queries.** Every entry in `queries` runs on load regardless of which tab is active
— the orchestrator reads the flat `queries` map and never looks at the ui_schema. Tabs organise a
dashboard; they do not make it cheaper. A 3-tab dashboard costs all 3 tabs on every open, so keep the
total query count in view and do not reach for tabs to "lazy-load" anything.

Four rules, each of which fails quietly when broken:

- **The `Categorization` is a CHILD of the root `VerticalLayout`, never the root itself.** As the root
  it renders, but the dashboard editor has no layout to anchor to and cannot add anything around it.
- **Every `Category` needs a `label`** — it is the tab's text, and it is required. Omitting it fails
  validation, but the message never names the missing label and changes with the tab's content:
  `expected "Category"` for a bare Control, `expected "Control"` for an empty `Category`, and an
  `Unsupported property … "widget"` on an option further down for the widget shape used below. Read
  any of those on a `Categorization` as a missing `label` first.
- **Wrap each `Category`'s content in a `VerticalLayout`.** Widgets placed directly under a `Category`
  render fine but are not selectable or movable in the dashboard's drag-and-drop editor.
- **Keep it single level.** A `Categorization` placed DIRECTLY inside another passes schema validation
  but does NOT render: the tabs renderer requires every direct child to be a `Category`, so the whole
  block falls through to `No applicable renderer found.`. One nested inside a `Category`'s own
  `VerticalLayout` does render as sub-tabs — but it hides content behind two clicks that the single
  filter row above cannot signpost, so split the dashboard instead.

Optional extras: `Category.options.icon` (any Iconify name, drawn before the tab label — the platform's
own dashboards use `material-symbols:*`), `Categorization.options.collapsable` to fold the entire tab
block, and a `rule` on a `Category` to show or hide a tab conditionally. `collapsable` is an OBJECT —
`{"collapsed": true}`, `{"label": "Deployments"}`, `{"i18n": "key"}` — and the bare `collapsable: true`
a reader reaches for first fails validation with `must be object`.

```json
{"ui_schema":{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","elements":[{"type":"Control","scope":"#/properties/environment","label":"Environment"}]},{"type":"Categorization","elements":[{"type":"Category","label":"Overview","options":{"icon":"material-symbols:speed-outline"},"elements":[{"type":"VerticalLayout","elements":[{"type":"HorizontalLayout","options":{"columns":[6,6]},"elements":[{"type":"Control","scope":"#/properties/totalDeploys","options":{"widget":"kpi","showBackground":true}},{"type":"Control","scope":"#/properties/successRate","options":{"widget":"kpi","showBackground":true,"unit":"%"}}]},{"type":"Control","scope":"#/properties/dailyTrend","label":"Daily Trend","options":{"widget":"area-chart","categoryKey":"date","series":[{"dataKey":"count","name":"Deployments"}],"xAxisLabel":"Date","yAxisLabel":"Deployments","height":300}}]}]},{"type":"Category","label":"Detail","options":{"icon":"material-symbols:table-rows-outline"},"elements":[{"type":"VerticalLayout","elements":[{"type":"Control","scope":"#/properties/recentDeploys","label":"Recent Deployments","options":{"widget":"data-table","features":["sorting","pagination"],"pagination":{"pageSize":10,"pageSizeOptions":[10,25,50]},"emptyState":{"title":"No deployments","description":"Try adjusting the filters."}}}]}]}]}]}}
```

## Pattern: Clickable links

The FE `LinkFormatterCell` uses `config.targetUrl` / `config.displayText` when given, and **falls back
to the row's own cell value** for both the `href` and the visible text when they are omitted. So per-row
links DO work — whenever the cell value itself is the URL. What is not supported is templating
(`targetUrl: "https://.../${row.id}"` renders literally) or taking the `href` from a *different* column
than the one being rendered. Compose the full URL in SQL instead.

**Contract — the only keys a link formatter's `config` accepts:**

| Key | Type | Notes |
| --- | --- | --- |
| `targetUrl` | string | Optional static `href`, shared by every row. **Omit for per-row links** so the cell value is used. |
| `displayText` | string | Optional static anchor text, shared by every row. Omit to show the cell value. |
| `target` | `"_blank"` \| `"_self"` | Defaults to `_self`. |
| `underline` | `"always"` \| `"hover"` \| `"none"` | Defaults to `hover`. |
| `color` | `"primary"` \| `"secondary"` \| `"error"` \| `"info"` \| `"success"` \| `"warning"` | Defaults to `primary`. |

**Do NOT emit** `href_accessor`, `hrefAccessor`, `href`, `url`, `text`, or `label` inside `config` — none
are recognised. They are silently ignored, and the cell then falls back to its own value as the `href`,
which turns a title column into a link pointing at the title text.

### A. Per-row URLs (one link per row) — WORKS

The common ask: "one row per action item, with a clickable link to that item". Build the whole URL in
SQL, expose it as its own column, and declare a link formatter with no `targetUrl`/`displayText`:

```sql
SELECT
  action_item_id,
  title,
  concat('https://nullplatform.app.nullplatform.io/account/', toString(account_id),
         '/namespace/', toString(namespace_id), '/action-item/', toString(action_item_id)) AS url
FROM governance_action_items_action_items FINAL
WHERE _deleted = 0
FORMAT JSON
```

```json
{"id":"url","header":"Action Item","accessor":"url","formatter":{"type":"link","config":{"target":"_blank"}}}
```

Also declare `"format": "uri"` on that property in the JSON Schema. It states intent, and the frontend
applies the link formatter from it on its own: for auto-detected columns (no explicit `columns` on the
table) and, in react-material-renderers 0.0.56, as a backfill for a declared column that carries no
`formatter` of its own. Declare both anyway — the explicit formatter is what makes the link work
regardless of which renderer version is deployed.

```json
{"url":{"type":"string","format":"uri"}}
```

The value must be a whole `http(s)` URL. Anything else renders as plain text instead of an anchor, by
design: dangerous schemes (`javascript:`, `data:`) are dropped, and so is an **empty string** (an
`href=""` would reload the app). Neither `''` nor `NULL` produces a link, so a `concat(...)` wrapped in an
`if(<ids resolvable>, ..., '')` guard silently yields unlinked rows wherever that guard fires. Make the
URL derivable for every row if you can; otherwise verify how many rows come back with a non-empty URL and
tell the user that the rest will show no link.

### B. Static link column (same URL every row) — WORKS

Only useful when every row genuinely points to the same URL (e.g. a "Docs" column linking to one runbook):

```json
{"id":"docs","header":"Runbook","accessor":"docs","formatter":{"type":"link","config":{"targetUrl":"https://docs.nullplatform.com/runbooks/migration","displayText":"View runbook","target":"_blank","underline":"hover"}}}
```

The query still needs to return *something* for the `docs` accessor per row — any non-null value will do;
the cell ignores it for the href.

### C. Static link in a Label (documentation / context) — WORKS

Use a `Label` with `format: "markdown"` for a single link outside the table:

```json
{"type":"Label","text":"##### Lambda Migration\nProject details in [Confluence](https://nullplatform.atlassian.net/wiki/.../migration) - Tracking board in [Jira](https://nullplatform.atlassian.net/.../JIRA-123).","options":{"format":"markdown"}}
```

`Label.text` is static — it does NOT read from any schema property and cannot render SQL output.

### D. Link text from one column, href from another — NOT SUPPORTED

Rendering the `title` column as an anchor pointing at a separate `url` column has no JSON pattern: the
`href` always comes from the rendered cell's own value (or from static `targetUrl`). Per-row anchor text
is unavailable for the same reason — `displayText` is static.

**What to do instead:** keep the title as its own text column and add a dedicated link column (pattern A).
If the user specifically wants the title itself clickable, say so plainly — it needs a frontend change in
`react-ui-components` (`LinkFormatterCell` would have to accept a per-row href accessor) — and offer the
separate link column meanwhile. Reply in the language the user is writing to you (see the Language rule
in `SKILL.md`).

## Pattern: Chips in tables

`mapping` is **not** a key the data-table chip formatter accepts. In `@nullplatform/react-ui-components`
both `ChipFormatterCell` implementations (new design and legacy) read only `content`, `color`, `size`
and `clickable` from `config`, and render `config.content ?? value`. A `config.mapping` is passed
through and silently ignored, so the column shows the **raw database value in a single grey chip** —
`pending_deferral` instead of "Pend. diferir", every row the same colour.

**Contract — the only keys a table chip formatter's `config` accepts:**

| Key | Type | Notes |
| --- | --- | --- |
| `color` | `default` \| `primary` \| `secondary` \| `error` \| `info` \| `success` \| `warning` | One colour for the whole column. Defaults to `default`. |
| `size` | `small` \| `medium` | Defaults to `small`. |
| `clickable` | boolean | Renders the chip as clickable. The click handler (`onChipClick`) is a function, so it is not reachable from JSON — the chip looks clickable and does nothing. Leave it off unless you only want the affordance. |
| `content` | string | Static label for every row. Rarely what you want. |

### A. Human labels in a table column — do the mapping in SQL

Since the chip renders the cell value, translate the value in the query and the chip is correct:

```sql
SELECT multiIf(priority = 'critical', 'Crítica',
               priority = 'high',     'Alta',
               priority = 'medium',   'Media',
               priority = 'low',      'Baja', 'Otra') AS prioridad
FROM governance_action_items_action_items FINAL WHERE _deleted = 0 FORMAT JSON
```

```json
{"id":"prioridad","header":"Prioridad","accessor":"prioridad","formatter":{"type":"chip","config":{"size":"small"}}}
```

**Per-value colours in a table are NOT supported** — `color` is one static value for the column. Pick
the colour that fits the column's meaning, or leave it `default`. If the user asks for red criticals
and amber highs in the same column, say it needs a frontend change and offer the SQL-label version.

### B. Per-value labels AND colours — only on a scalar Control

`mapping` works on a standalone `Control` bound to a **scalar** property (string/number/integer/
boolean), declared with `options.format: "chip"` — not `formatter`. It maps one value, so it suits a
status field, never a table column:

```json
{"type":"Control","scope":"#/properties/estadoActual","options":{"format":"chip","mapping":{"open":{"label":"Abierto","color":"warning"},"resolved":{"label":"Resuelto","color":"success"}}}}
```

Each mapping entry accepts `label`, `color`, `variant`, `size`, `icon` and `style`; an unmapped value
falls back to the raw value. `variant` is only `filled` or `outlined` — anything else (`tonal`) reaches
MUI's Chip as an unsupported value.

### C. On route B, never key a mapping on a snake_case value

This caveat is specific to the scalar-Control route above. In a table it does not arise at all —
`mapping` is ignored there whatever its keys look like, so no casing makes route A work.

On route B, mapping keys are **data values sitting where field names normally sit**, so the response
key-casing transform rewrites them in the published view: `pending_deferral` becomes
`pendingDeferral` while the value from the Lake stays `pending_deferral`, and the entry never matches.
The editor preserves the key, so the same control can look correct while editing and lose its chip
once published. Single-word values (`open`, `failed`, `resolved`) are unaffected.

For multi-word statuses, map them in SQL (pattern A) — that keeps them out of a key position
entirely, and works the same in both surfaces.

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

For URL columns, declare `"format": "uri"` on the schema property and give the column a
`{"type": "link", "config": {"target": "_blank"}}` formatter — see "Pattern: Clickable links".

### Table Column Formatters

When defining explicit `tableColumns` on a data-table, apply formatters based on the data type:

| Data pattern                                                                                                                             | Formatter                                                                                                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status/state values (`finalized`, `failed`, `pending`, `active`)                                                                         | `{"type": "chip", "config": {"color": "info", "size": "small"}}` — the chip label is the CELL VALUE. Per-value labels/colors via `config.mapping` do NOT work in tables; see "Pattern: Chips in tables" below.                                              |
| URLs or links — the cell value IS the URL (per-row links, see "Clickable links" above)                                      | `{"type": "link", "config": {"target": "_blank"}}` — omit `targetUrl`/`displayText` so each row's value becomes both the `href` and the visible text. Use `targetUrl`/`displayText` only for a link that is identical on every row.                    |
| Date/day columns (any column containing dates, days, timestamps — including columns named `day`, `date`, `createdAt`, `eventDate`, etc.) | `{"type": "date", "format": "relative", "config": {"tooltip": {"enabled": true, "format": "absolute", "placement": "top"}}}`                                                                                |
| Percentage/rate columns (success rate, error rate, etc.)                                                                                 | Keep the value NUMERIC and put the unit in the `header` (`"Success rate (%)"`). `config.suffix` is **not read** — `TextFormatterCell` ignores `config` entirely and renders `String(value)`. Appending `'%'` in SQL works but makes the column a string, so sorting goes lexical (`"9%"` after `"10%"`). |
| Value-dependent colour in a table cell                                                                                                  | **Not supported.** `typography.color` is applied, but as ONE static colour for the whole column; table chips have no `thresholds` (that is a `kpi` option). Say so and offer a SQL-derived label column instead. |
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

Never wrap a single widget in a `VerticalLayout` — place it directly as an element of the parent layout. When there are 2 charts that complement each other (e.g. trend + distribution, by-time + by-category), place them side-by-side in a `HorizontalLayout` with appropriate `columns` proportions instead of stacking them vertically. Full-width charts can go directly as elements of the root `VerticalLayout`. When a dashboard grows past two or three sections that are read independently, split it into tabs instead of one long scroll — see **Pattern 12: Tabbed sections**.

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
- **Tabs**: Use `Categorization` + `Category` for independently-read sections; declare the filters once above it (Pattern 12)
- **Max 50 items** in chart arrays for readability — aggregate larger datasets
- **Date range picker**: Only add a Control for the start date field — the end date is managed automatically via `endDateScope`. Do NOT add a separate Control for `endDate`.
- **Global filters**: Reference the same `params` in all data queries for consistent filtering
- **Axis labels**: Always set `xAxisLabel` and `yAxisLabel` on cartesian charts (line, area, bar) so readers know what each axis represents. Use short, descriptive names (e.g. `"Date"`, `"Count"`, `"Seconds"`) in the dashboard's confirmed language (default English). Some examples in this cookbook show legacy Spanish strings — those illustrate JSON shape, not the output language
- **Always apply the Dashboard Enrichment Rules above** — never generate flat/plain dashboards. See Pattern 10 for a fully enriched example.
