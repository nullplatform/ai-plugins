<!-- JSON code blocks are intentionally minified to reduce token usage when this file is loaded into the model context. Do NOT reformat/prettify. -->

# JSON Schema Reference

A report definition is a single object — there is only one format (no widget files, no separate
metadata file). The full envelope, persisted via `POST /report` / `PATCH /report/<id>` (see
`api-reference.md`):

```json
{"name":"Report Title","slug":"report-title","description":"Report description","schema":{"type":"object","properties":{}},"ui_schema":{"type":"VerticalLayout","elements":[]},"queries":{},"visibility":"user","category_id":null,"nrn_level":"organization"}
```

| Field | Type | Notes |
|---|---|---|
| `name` | string | **required** on create |
| `slug` | string | URL-friendly id |
| `description` | string | shown alongside the report |
| `schema` | object | JSON Schema (draft-07 + nullplatform extensions) — see below |
| `ui_schema` | object | DynamicForm layout — snake_case key |
| `queries` | object | query-id → `{ source, params?, target, mapping? }` — see **Queries** below |
| `visibility` | enum | `user` (default) \| `organization` \| `platform` |
| `category_id` | uuid\|null | from `fetch_np_api_url.sh "/report_category"` |
| `nrn_level` | enum | `organization` (default) \| `account` \| `namespace` \| `scope` |

The frontend's `DynamicForm` component receives `schema`, `ui_schema`, and `data` as props. An
orchestrator executes `queries`, maps results into `data` at each query's `target`, and re-executes
affected queries when a filter value (referenced via `params`) changes.

## Queries

Each entry in `queries` is keyed by an arbitrary query id and has the shape:

```
{ source, params?, target, mapping? }
```

- `source` — a SQL string ending in `FORMAT JSON`, with `{name:Type}` placeholders for every
  parameter (e.g. `{days:String}`, `{environment:String}`). Read numeric filters as `String` and
  cast defensively — see the note under **Queries** below.
- `params.<placeholder>` — one entry per SQL placeholder: `{ "scope": "#/properties/<field>" }`,
  a JSON Pointer into `schema` naming the filter field that supplies the value.
- `target` — a JSON Pointer (e.g. `#/properties/total`) naming where the query's result is written
  in the data object passed to `DynamicForm`.
- `mapping` (optional) — a hint for how to shape the result, e.g. `"enum"` for queries that populate
  a filter's dropdown options.

Canonical example:

```json
{"total-count":{"source":"SELECT count() AS total FROM core_entities_deployment AS d FINAL LEFT JOIN core_entities_scope_dimension AS sd FINAL ON sd.scope_id = d.scope_id AND sd._deleted = 0 AND sd.dimension_slug = 'environment' WHERE d._deleted = 0 AND d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY AND ({environment:String} = '' OR sd.value_slug = {environment:String}) FORMAT JSON","params":{"environment":{"scope":"#/properties/environment"},"days":{"scope":"#/properties/dateRange"}},"target":"#/properties/total"}}
```

Here the SQL placeholders `{days:String}` and `{environment:String}` are each resolved via `params`
from the `dateRange` and `environment` fields in `schema`, and the result is written to
`#/properties/total`.

> **Numeric params arrive as (possibly empty) strings — never type them as `{x:UInt32}`/`{x:Int32}`.**
> On first render the frontend sends the filter value as-is, and unset numeric filters arrive as the
> empty string `""`. An empty value cannot be cast to a ClickHouse numeric type, and the Lake rejects
> the whole statement at render time with `DB::Exception: SQL statement is not allowed` (surfaced as a
> 403 in the dashboard). Always read a numeric filter as `String` and cast defensively:
> `now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY`
> (use the filter's own `default` as the fallback). For free-form numbers use
> `toInt32OrZero({param:String})` / `toFloat64OrZero({param:String})`. Because an `EXPLAIN` with a
> concrete value passes but the empty-value render still fails, **validate every query with the
> placeholder empty too** — see `SKILL.md` → Workflow Step 5.

## Type System

Properties supported by DynamicForm (JSON Schema draft-07 + nullplatform extensions), used inside
`schema`.

| Property      | Type               | Description                                                                       |
| ------------- | ------------------ | --------------------------------------------------------------------------------- |
| `type`        | string \| string[] | `"string"`, `"number"`, `"integer"`, `"boolean"`, `"object"`, `"array"`, `"null"` |
| `format`      | string             | `"date"`, `"date-time"`, `"time"`, `"uri"`, `"email"`, etc.                       |
| `title`       | string             | Human-readable field label (shown as chart/KPI title)                             |
| `description` | string             | Help text displayed below the field                                               |
| `default`     | any                | Default value when field is empty                                                 |
| `enum`        | array              | Allowed values (renders as dropdown/radio)                                        |
| `readOnly`    | boolean            | Field cannot be edited                                                            |

## String Validation

| Property    | Type   | Description           |
| ----------- | ------ | --------------------- |
| `minLength` | number | Minimum string length |
| `maxLength` | number | Maximum string length |
| `pattern`   | string | Regex pattern         |

## Number/Integer Validation

| Property           | Type   | Description           |
| ------------------ | ------ | --------------------- |
| `minimum`          | number | Min value (inclusive) |
| `maximum`          | number | Max value (inclusive) |
| `exclusiveMinimum` | number | Min value (exclusive) |
| `exclusiveMaximum` | number | Max value (exclusive) |
| `multipleOf`       | number | Value divisibility    |

## Object Properties

| Property     | Type     | Description                        |
| ------------ | -------- | ----------------------------------- |
| `properties` | object   | Map of property name to sub-schema |
| `required`   | string[] | Required property names            |

## Array Properties

| Property      | Type    | Description               |
| ------------- | ------- | ------------------------- |
| `items`       | schema  | Schema for array elements |
| `minItems`    | number  | Minimum array length      |
| `maxItems`    | number  | Maximum array length      |
| `uniqueItems` | boolean | All items must be unique  |

## Composition

| Property | Type     | Description                          |
| -------- | -------- | ------------------------------------- |
| `oneOf`  | schema[] | Value must match exactly one schema  |
| `anyOf`  | schema[] | Value must match at least one schema |
| `allOf`  | schema[] | Value must match all schemas         |
| `$ref`   | string   | Reference: `"#/definitions/myType"`  |

## Custom Extensions

### Field Ordering

`"order": number` — Lower = first in the auto-generated `ui_schema`.

### Display Hints

| Property      | Type     | Description      |
| ------------- | -------- | ---------------- |
| `placeholder` | string   | Placeholder text |
| `examples`    | string[] | Example values   |

## Schema for Reports — Key Patterns

For reports, the most common `schema` patterns are:

### The binding contract — EVERY query target MUST be a declared property

**Non-negotiable invariant: for every entry in `queries`, its `target` must resolve to a property
that exists in `schema.properties`.** A widget whose `scope` points at an undeclared property does
not error — it renders blank, and the failure is invisible everywhere you would look for it.

The frontend decides what to do with a query result by looking the target property up in the schema:

| Declared as | Result handling |
| --- | --- |
| `type: "array"` | all rows are kept; fields typed `number`/`integer` in `items.properties` get cast from strings |
| `type: "number"` | the scalar is taken from the first row and cast |
| **absent** | falls into the scalar branch — **the whole result collapses to the first cell of the first row** |

So a chart query returning 12 rows becomes the single string `"Cost Optimization"`, and the chart
renders its empty state. The query itself succeeded, the Lake returned 200, and the query inspector
shows all 12 rows — nothing reports a problem. KPIs are the cruel exception: they *want* a scalar, so
they keep working, which makes a dashboard look "half broken" rather than misconfigured.

Checklist before persisting, for every `queries[*].target`:

- The property exists in `schema.properties`.
- Array widgets (every chart, every `data-table`) → `type: "array"` **with** `items.properties`
  declaring each column, and every numeric column typed `number` or `integer` (the Lake returns
  numbers as JSON **strings** — without the type there is no cast, and charts get strings).
- KPI widgets → `type: "number"`.
- URL columns → `type: "string"` with `format: "uri"`.
- Timestamp columns → `type: "string"` with `format: "date-time"`.

### Naming — three independent conventions, do not mix them

Schema property names drift out of alignment with their scopes because the definition legitimately
contains **both** casings, for different reasons. Keep them apart:

| What | Casing | Why |
| --- | --- | --- |
| schema property names, and the `#/properties/<name>` in every `scope` and `target` | **camelCase** | they are one identifier used in three places and must match character-for-character |
| `params` keys | **snake_case when the SQL placeholder is** | ClickHouse resolves `{namespace_id:String}` by exact name, so the key mirrors the placeholder |
| top-level API fields (`ui_schema`, `category_id`, `nrn_level`) | snake_case | the API contract |

So this is correct and NOT an inconsistency to "tidy up":

```json
{"params":{"namespace_id":{"scope":"#/properties/namespaceId"}}}
```

The param key is snake because the SQL says `{namespace_id:String}`; the property is camel because the
schema declares `namespaceId`. **Never let the param/SQL casing leak into property names** — writing
`"kpi_total"` in `schema.properties` while the scope says `#/properties/kpiTotal` leaves the target
unresolvable, and the widget renders blank with no error (see the binding contract above).

Prefer camelCase for property names even when the SQL column is snake_case: alias in the query
(`SELECT count() AS kpiTotal`) rather than renaming the property. Property names kept in camelCase
behave identically in the editor and the published view; snake_case property names only work in
whichever surface happens to translate them.

This applies to **property names only** — do NOT extend it to `params` keys or the top-level API
fields. Those follow the two rules above and are not inconsistencies to normalise away.

### Result keys MUST match what the widget reads

The schema says what SHAPE arrives; the SQL column aliases must match the KEYS each widget reads.
A mismatch is **never** an error, and only sometimes a blank widget. Two widgets fall back silently
instead, which is worse than blank: they render something plausible off the wrong column.

| Widget | Keys it reads | What a mismatch does |
| --- | --- | --- |
| `donut-chart` / `pie-chart` | `labelKey`, `valueKey` (default `label`, `value`) | **silently auto-detects** — first non-numeric field becomes the label, first numeric the value. Renders fine off a column you did not choose. |
| cartesian (`bar`, `line`, `area`) | `categoryKey`, `series[].dataKey` | blank — categories become `''`, data points `null`. (Omitting `series` altogether auto-detects every numeric field instead.) |
| `data-table` | each column's `accessor` | that cell renders empty |
| `kpi` | the target property name | **silently positional** — with no matching key the FIRST column is used, so a multi-column KPI query shows the wrong metric under the right label |

Because the fallbacks are silent, matching the alias is the only way to know *which* column a widget is
showing. Keep the aliases, the `items.properties` keys and the widget keys spelled identically —
`SELECT categoria_nombre AS label, count() AS value` for a donut declaring
`"labelKey": "label", "valueKey": "value"`, and `SELECT count() AS kpiTotal` for a KPI on
`#/properties/kpiTotal`.

### One target per query

A `query` writes to exactly one `target`. A `SELECT` computing two metrics does **not** populate two
KPIs — the second is never written, and a widget that is never written renders a **loading skeleton
forever** (not a blank, not a zero), because the orchestrator cannot distinguish "no query" from
"query still running".

Give each metric its own `queries` entry. Reusing the identical `source` and `params` is free: the
orchestrator strips `queryKey`/`scope`/`target`/`mapping` before building its coalescing key, so two
entries differing only in `target` collapse into a **single** Lake call and each extracts its own
column from the shared result.

### KPI Value

```json
{"totalDeploys":{"type":"number","title":"Total Deployments"}}
```

### Chart Data (array of objects)

```json
{"byEnvironment":{"type":"array","items":{"type":"object","properties":{"environment":{"type":"string"},"count":{"type":"number"}}}}}
```

### Indexed Data (object of arrays, used with `indexBy`)

```json
{"metricsByEnv":{"type":"object","additionalProperties":{"type":"array","items":{"type":"object","properties":{"month":{"type":"string"},"value":{"type":"number"}}}}}}
```
