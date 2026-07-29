<!-- JSON code blocks are intentionally minified to reduce token usage when this file is loaded into the model context. Do NOT reformat/prettify. -->

# Filter Examples Reference

Detailed JSON examples for each filter type used in schema-based reports. Filters are schema
properties that the user interacts with (dropdowns, inputs). Queries reference them via `params`
to reactively filter data. **Every filter field MUST have a `default`** — queries execute on mount
with defaults; no default means a broken dashboard on load.

## Static Enum Filter (fixed options)

Options are known in advance. Use `enum` in the schema.
**NOTE:** Do NOT use static enums for date filtering — use the Date Range Picker instead (see below).

**Schema:**

```json
"status": {
  "type": "string",
  "enum": ["finalized", "failed", "in_progress"],
  "default": "finalized"
}
```

**ui_schema:** Standard Control — the select renders automatically from `enum`.

```json
{"type":"Control","scope":"#/properties/status","label":"Status"}
```

## Dynamic Enum Filter (query-populated)

Options come from the database. Do NOT include `enum` in schema — add a query with `mapping: "enum"`.

**Schema (no enum):**

```json
"namespaceId": {
  "type": "string",
  "default": ""
}
```

**Query:**

```json
"available-namespaces": {
  "source": "SELECT DISTINCT namespace_id as id, namespace_name as name FROM core_entities_namespace FINAL WHERE _deleted = 0 FORMAT JSON",
  "target": "#/properties/namespaceId",
  "mapping": "enum"
}
```

## Dimension Filter (scope dimensions: environment, country, etc.)

Platform dimensions live in three tables:

- `core_entities_runtime_configuration_dimension` — catalog of dimension definitions (`id`, `name`, `slug`, `status`, `order`). Defines WHICH dimensions exist for the customer (e.g., `environment`, `country`).
- `core_entities_runtime_configuration_dimension_value` — catalog of allowed values per dimension (`id`, `name`, `slug`, `status`, `dimension_id`).
- `core_entities_scope_dimension` — per-scope assignments. Each row has `dimension_slug` and `value_slug`, plus `scope_id`. **Columns are `dimension_slug` and `value_slug` — NOT `dimension`/`value`.**

**The rule: one filter per dimension.** When the user asks to "filter by dimensions" and names several (e.g., environment and country), create **one independent dynamic-enum filter per dimension**. NEVER build a single combined filter where one Control picks the dimension name and a second Control picks the value — that pattern produces two coupled components for what should be N independent filters. The dimension set is small and known at design time; bake each one in as its own filter.

**Source of enum values:** Use the **catalog** tables (`runtime_configuration_dimension_value` joined to `runtime_configuration_dimension`) — that lists every configured value, including ones no scope is using yet. Avoid sourcing from `scope_dimension` for the dropdown because it would hide valid values that simply haven't been assigned.

**Schema (one field per dimension):**

```json
"environment": { "type": "string", "default": "" },
"country":     { "type": "string", "default": "" }
```

**Queries (one enum query per dimension, sourced from the catalog):**

```json
"available-environments": {
  "source": "SELECT dv.slug as id, coalesce(dv.name, dv.slug) as name FROM core_entities_runtime_configuration_dimension_value AS dv FINAL JOIN core_entities_runtime_configuration_dimension AS d FINAL ON dv.dimension_id = d.id AND d._deleted = 0 AND d.status = 'active' WHERE dv._deleted = 0 AND dv.status = 'active' AND d.slug = 'environment' ORDER BY name FORMAT JSON",
  "target": "#/properties/environment",
  "mapping": "enum"
},
"available-countries": {
  "source": "SELECT dv.slug as id, coalesce(dv.name, dv.slug) as name FROM core_entities_runtime_configuration_dimension_value AS dv FINAL JOIN core_entities_runtime_configuration_dimension AS d FINAL ON dv.dimension_id = d.id AND d._deleted = 0 AND d.status = 'active' WHERE dv._deleted = 0 AND dv.status = 'active' AND d.slug = 'country' ORDER BY name FORMAT JSON",
  "target": "#/properties/country",
  "mapping": "enum"
}
```

**ui_schema (one Control per dimension, all in the filter row):**

```json
{ "type": "Control", "scope": "#/properties/environment", "label": "Environment" },
{ "type": "Control", "scope": "#/properties/country",     "label": "Country" }
```

**SQL pattern in data queries — one JOIN per dimension referenced:**

```sql
FROM core_entities_deployment AS d FINAL
LEFT JOIN core_entities_scope_dimension AS sd_env FINAL
  ON sd_env.scope_id = d.scope_id AND sd_env._deleted = 0 AND sd_env.dimension_slug = 'environment'
LEFT JOIN core_entities_scope_dimension AS sd_country FINAL
  ON sd_country.scope_id = d.scope_id AND sd_country._deleted = 0 AND sd_country.dimension_slug = 'country'
WHERE d._deleted = 0
  AND ({environment:String} = '' OR sd_env.value_slug = {environment:String})
  AND ({country:String}     = '' OR sd_country.value_slug = {country:String})
```

Each filter uses the standard optional pattern (`{param:String} = '' OR field = {param:String}`) so empty default behaves as "all".

CRITICAL:

- **One filter per dimension.** If the user names environment + country, that is two filters and two Controls — never one combined dimension+value picker.
- **Columns are `dimension_slug` and `value_slug`** in `core_entities_scope_dimension`. There is no `dimension` or `value` column — using those will fail validation.
- **Alias each JOIN distinctly** (`sd_env`, `sd_country`, …) when filtering by more than one dimension in the same query — a single `sd` alias cannot match two different dimension rows for the same scope.
- **Enum queries should hit the catalog** (`runtime_configuration_dimension_value` JOIN `runtime_configuration_dimension`), not `scope_dimension`, so configured-but-unused values still appear in the dropdown.
- Default the filter value to `""` and pair it with the optional SQL pattern, so the dashboard renders with no dimension preselected.

## Cascade Filter (dependent on another filter)

A filter whose options depend on another filter's value. Uses `params` in the enum query.

**Schema:**

```json
"namespaceId": { "type": "string", "default": "" },
"applicationId": { "type": "string", "default": "" }
```

**Query — applications filtered by namespace:**

```json
"available-applications": {
  "source": "SELECT DISTINCT a.app_id as id, a.app_name as name FROM core_entities_application AS a FINAL WHERE a._deleted = 0 AND ({namespace_id:String} = '' OR a.namespace_id = {namespace_id:String}) FORMAT JSON",
  "params": {
    "namespace_id": { "scope": "#/properties/namespaceId" }
  },
  "target": "#/properties/applicationId",
  "mapping": "enum"
}
```

When `namespaceId` changes, the query re-executes and application options update. If the current value is not in the new options, it resets.

## Multi-Select Filter

Allow selecting multiple values. Schema uses `type: "array"`.

**Schema:**

```json
"statuses": {
  "type": "array",
  "items": { "type": "string", "enum": ["finalized", "failed", "in_progress"] },
  "default": []
}
```

**SQL pattern (uses ClickHouse `Array(String)`):**

```sql
WHERE (length({statuses:Array(String)}) = 0 OR d.status IN {statuses:Array(String)})
```

## Numeric Enum Filter (dropdown with numeric values)

> **Not the default for time periods.** For a "period" filter prefer the **Date Range Picker** below
> (From/To) — it matches the rest of the product and lets the client pick arbitrary ranges. Use this
> fixed numeric-days dropdown only when the client explicitly wants preset buttons (7/14/30).

When options are numeric (e.g., days: 7, 14, 30), you MUST still use `type: "string"` with string enum values. JSON Forms only renders a select/dropdown for `type: "string"` — using `type: "integer"` with `enum` renders a number input instead.

**Schema (correct):**

```json
"days": {
  "type": "string",
  "title": "Days",
  "enum": ["7", "14", "30"],
  "default": "7"
}
```

Enum values must be bare integers like `"7"`, never unit-suffixed strings like `"7d"` — `toUInt32OrZero` returns `0` for any string that isn't wholly numeric, which silently collapses the filter to its fallback on every selection.

**Schema (WRONG — renders as number input, not dropdown):**

```json
"days": {
  "type": "integer",
  "enum": [7, 14, 30],
  "default": 7
}
```

**SQL — read as `String` and cast defensively. NEVER type it as `{days:UInt32}`.**

Although the enum values look numeric, the frontend sends the raw filter value, and on first render an
unset filter arrives as the **empty string `""`**. `""` cannot be cast to a ClickHouse numeric type, so
`{days:UInt32}` makes the Lake reject the entire statement at render time with
`DB::Exception: SQL statement is not allowed` (a 403 in the dashboard). Read the value as `String` and
convert it with `toUInt32OrZero`, falling back to the filter's own `default` when it is empty or
non-numeric:

```sql
WHERE d.created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 7, toUInt32OrZero({days:String})) DAY
```

The fallback (`7` here) MUST match this filter's `default`. This is the numeric analog of the
date-range picker's `parseDateTimeBestEffortOrNull` rule below — the frontend does not guarantee the
schema `default` reaches the query, so every numeric bound has to be self-defending in SQL.

> **Gotcha:** an `EXPLAIN` with a concrete value (`--param days=7`) passes, but the real render sends
> `days=""` and still fails. Always validate numeric queries with the placeholder **empty** too — see
> `SKILL.md` → Workflow Step 5.

## Date Range Picker Filter

A calendar-based date range selector with preset buttons (today, last 7 days, etc.). Uses two `date-time` string fields for start and end dates. Only the start date field needs a Control element — the end date is managed automatically via `endDateScope`.

**When to use:** This is the **default** for any time-period filter. Prefer it over a numeric-days enum unless the client explicitly wants fixed preset buttons — it lets them pick arbitrary from/to dates and matches the rest of the product. Set `initialPreset` (e.g. `last7Days`) so it loads with a sensible default range.

**Schema (two sibling date-time fields):**

```json
"startDate": {
  "type": "string",
  "format": "date-time",
  "default": ""
},
"endDate": {
  "type": "string",
  "format": "date-time",
  "default": ""
}
```

**ui_schema — ONLY startDate gets a Control. NEVER add a separate Control for endDate** (it is managed automatically via `endDateScope`). Adding a second Control for endDate creates a duplicate date picker.

```json
{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last7Days","allowedRanges":["today","yesterday","last7Days","thisWeek","last30Days","thisMonth"],"disableFuture":true}}
```

**Options:**

| Option               | Type       | Default | Description                                                                                                       |
| -------------------- | ---------- | ------- | ----------------------------------------------------------------------------------------------------------------- |
| `format`             | `string`   | —       | Must be `"date-range"` to trigger the date range renderer                                                         |
| `endDateScope`       | `string`   | —       | JSON Pointer to the end date field (e.g., `"#/properties/endDate"`)                                               |
| `initialPreset`      | `string`   | —       | Pre-selected range on load. Must match a key from `allowedRanges` or `customRanges` (e.g., `"last7Days"`)         |
| `allowedRanges`      | `string[]` | `[]`    | Preset buttons: `today`, `yesterday`, `last7Days`, `thisWeek`, `lastWeek`, `last30Days`, `thisMonth`, `lastMonth` |
| `customRanges`       | `array`    | `[]`    | Custom preset ranges: `[{ key: string, label: string, diffDays?: number, diffMinutes?: number }]`                 |
| `disableFuture`      | `boolean`  | `false` | Block selection of future dates                                                                                   |
| `disableInputRanges` | `boolean`  | `false` | Hide manual date input fields (only allow preset buttons)                                                         |
| `maxDate`            | `string`   | —       | Absolute max selectable date (ISO 8601)                                                                           |

**Custom ranges:** Use `customRanges` when the built-in presets don't cover the needed intervals. Each entry needs a unique `key`, a display `label`, and either `diffDays` or `diffMinutes` to define the duration (computed backwards from now). The `initialPreset` can reference a custom range key.

```json
{"type":"Control","scope":"#/properties/startDate","label":"Period","options":{"format":"date-range","endDateScope":"#/properties/endDate","initialPreset":"last90Days","allowedRanges":["last7Days","last30Days"],"customRanges":[{"key":"last90Days","label":"Last 90 days","diffDays":90},{"key":"last6Months","label":"Last 6 months","diffDays":180},{"key":"last2Hours","label":"Last 2 hours","diffMinutes":120}],"disableFuture":true}}
```

Built-in + custom ranges are merged and sorted by duration (shortest first) in the picker sidebar. When using `diffMinutes`, the range is relative to the current time (useful for real-time monitoring). When using `diffDays`, the range spans full calendar days back from now.

**SQL pattern (safe — uses OrNull + coalesce for bounded default):**

```sql
WHERE d.created_at >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY)
  AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR d.created_at <= parseDateTimeBestEffortOrNull({endDate:String}))
```

CRITICAL:

- **NEVER add a Control for endDate** — only startDate gets a Control. The endDate is managed via `endDateScope`
- **ALWAYS set `initialPreset`** in options to pre-select a range (e.g., `"last7Days"`). Without it, the picker loads empty
- Use `parseDateTimeBestEffortOrNull` (NOT `parseDateTimeBestEffort`) — the non-OrNull variant throws on empty string `""`
- ALWAYS provide a default range via `coalesce(..., now() - INTERVAL N DAY)` — never return all history when no date is selected
- NEVER use `{param} = '' OR ...` or `if({param} = '', ...)` patterns for dates — ClickHouse may evaluate both branches and throw
- Default: 28 days. Adjust per report context (7 days for real-time, 90 days for historical)
- Both `startDate` and `endDate` are ordinary properties in `schema` — the SQL param names are resolved by name against the corresponding filter fields, exactly like any other filter (see `params.<placeholder> = { "scope": "#/properties/<field>" }` in `docs/json-schema-reference.md`)

## Numeric Filter (free-form input)

A numeric input for integer or number values where the user types a number. Default `0` acts as bypass in SQL. Only use this when the user needs to enter an arbitrary number (not choose from predefined options).

**Schema:**

```json
"minDeploys": {
  "type": "integer",
  "title": "Minimum Deploys",
  "default": 0
}
```

**ui_schema:** Standard Control — renders as a number input automatically.

```json
{"type":"Control","scope":"#/properties/minDeploys","label":"Minimum Deploys"}
```

Like the numeric enum filter, read the value as `String` and cast with `toInt32OrZero` /
`toFloat64OrZero` — an empty input (`""`) sent on first render cannot be cast to `Int32`/`Float64` and
would make the Lake reject the statement (`SQL statement is not allowed`).

**SQL pattern (optional — 0 bypasses):**

```sql
WHERE (toInt32OrZero({minDeploys:String}) = 0 OR count >= toInt32OrZero({minDeploys:String}))
```

**SQL pattern (required — always filters):**

```sql
WHERE count >= toInt32OrZero({minDeploys:String})
```

**ClickHouse type mapping (always read the param as `String`, then cast):**

| Schema type | Cast function            | Example                          |
| ----------- | ------------------------ | -------------------------------- |
| `integer`   | `toInt32OrZero`          | `toInt32OrZero({minDeploys:String})` |
| `number`    | `toFloat64OrZero`        | `toFloat64OrZero({rate:String})`     |

## Filter SQL Patterns (summary)

Every filter must work when empty/unset. The SQL handles this inline:

| Filter type             | Default          | SQL pattern                                                                                                                                                                                                              |
| ------------------------ | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Single value (optional) | `""`             | `({param:String} = '' OR field = {param:String})`                                                                                                                                                                        |
| Single value (required) | First enum value | `field = {param:String}`                                                                                                                                                                                                 |
| Multi-select            | `[]`             | `(length({param:Array(String)}) = 0 OR field IN {param:Array(String)})`                                                                                                                                                  |
| Numeric enum (period)   | e.g. `"7"`       | `now() - INTERVAL if(toUInt32OrZero({param:String}) = 0, <default>, toUInt32OrZero({param:String})) DAY`                                                                                                                  |
| Numeric (optional)      | `0`              | `(toInt32OrZero({param:String}) = 0 OR field >= toInt32OrZero({param:String}))`                                                                                                                                          |
| Numeric (required)      | Sensible number  | `field >= toInt32OrZero({param:String})`                                                                                                                                                                                 |
| Date range picker       | `""` (both)      | `field >= coalesce(parseDateTimeBestEffortOrNull({startDate:String}), now() - INTERVAL 7 DAY) AND (parseDateTimeBestEffortOrNull({endDate:String}) IS NULL OR field <= parseDateTimeBestEffortOrNull({endDate:String}))` |

**Every filter field MUST have a `default`.** Queries execute on mount with the defaults in place — a
filter without a `default` produces a broken dashboard on first load.
