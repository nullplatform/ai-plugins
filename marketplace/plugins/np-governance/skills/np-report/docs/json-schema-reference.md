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
