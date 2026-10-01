---
name: np-report
description: Generate, modify, and persist nullplatform dynamic reports (dashboards) to the Reports API. Use whenever the user asks to create, update, list, publish, or delete a report/dashboard/visualization/metrics view backed by the nullplatform Customer Lake. Generates the full report definition JSON (JSON Schema + ui_schema + SQL queries) itself — no MCP — validates queries best-effort against the Lake, and saves a draft via the Reports API.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/*.sh), Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/*.sh), Write, Read, Edit, AskUserQuestion
---

# np-report

Generate nullplatform dynamic reports and persist them to the Reports API. The frontend renders
them natively with `DynamicForm`; this skill produces the definition and saves it — it does not render.

## STOP — READ FIRST

1. **You write the JSON yourself.** No widget builders, no `validate_report`, no
   temporary merge operations, no MCP. Write one report definition file and persist it via
   `fetch_np_api_url.sh` (see Step 5).
2. **The API key is `ui_schema`** (snake_case only).
3. **Queries** are `{ source, params?, target, mapping? }`; `params.<ph> = { "scope": "#/properties/<filter>" }`;
   SQL uses `{name:Type}` placeholders and ends with `FORMAT JSON`.
4. **Every filter has a `default`.** Visualizations use `options.widget`, never `options.format`.
5. **Default save is a draft.** Publishing is a separate explicit command.
6. **Always confirm before you persist.** Never create, update, or publish a report without first
   showing the user the plan and getting an explicit "yes" (see Workflow Step 3). Anything ambiguous
   is a question, not a guess.
7. **A persisted `source` MUST be a single executable read statement** — one `SELECT` or `WITH … SELECT`
   that ends in `FORMAT JSON`. NEVER store `EXPLAIN`, a trailing `;`, SQL comments, or more than one
   statement. The Lake rejects those at render time with `DB::Exception: SQL statement is not allowed`,
   which is what the user sees in the dashboard. `EXPLAIN` is for the validation step ONLY — it is
   never written into the report.

## Language

This SKILL.md and all skill docs are written in English. The **dashboard's** language is the user's
choice: **ask** whether they want the dashboard in **English or Spanish** as part of the plan
confirmation (Step 3). Default to **English** when unspecified or unclear. Render the entire dashboard
in the single chosen language — every label, title, axis, header, chip label, empty state — never
mixed. Narrate to the user in the language they are writing to you.

## SQL rules (essentials)

- Table prefixes: `core_entities_deployment`, `core_entities_build`, `core_entities_scope`, …
- Always `FINAL` and `_deleted = 0` (except `audit_events`, `scm_code_commits`, `scm_code_repositories`).
- **`audit_events` REQUIRES a `date` filter.** It is partitioned by day (233M rows, 42.8 GiB) — without a bound the engine opens all ~870 daily partitions. A shipped report had an unfiltered CTE over it and took **312 s per widget**; the same read bounded to 7 days is 43 parts / 6.5M rows instead of 1640 / 233M. Bind it to the dashboard's own date-range filter, and never widen it past what the widget shows.
- **Never read `audit_events` to resolve a user's email — join `auth_user` instead.** `auth_user` has `id` and `email` directly (43K rows): `LEFT JOIN auth_user FINAL AS u ON toString(u.id) = toString(d.created_by) AND u._deleted = 0`. Its `email` is `Nullable(String)`, so filter with `notEmpty(coalesce(u.email, ''))`. Building a `user_id → email` map out of `audit_events` is what cost that report its 312 s; `auth_user` returned **identical rows in 0.2 s**. It also carries `user_type`, which is how you exclude `machine` accounts (API keys) from anything ranking people.
- Deployment success = `status = 'finalized'`; build success = `status = 'successful'`.
- Environment lives in `core_entities_scope_dimension` (`dimension_slug = 'environment'`, column `value_slug`).
- Time: `now() - INTERVAL N DAY` (or HOUR).
- **Default a time-period filter to a date-range picker (From/To)** — `format: "date-range"` with the `parseDateTimeBestEffortOrNull` + `coalesce` SQL pattern (see `docs/filters-reference.md` § Date Range Picker Filter). It lets the client pick arbitrary from/to dates, matching the rest of the product. Use a fixed numeric-days enum (7/14/30) ONLY when the client explicitly asks for preset buttons.
- **Numeric filters arrive as possibly-empty strings — NEVER type a filter placeholder as `{x:UInt32}`/`{x:Int32}`.** The frontend sends the raw value and an unset filter arrives as `""`, which cannot cast to a numeric type → the Lake rejects the statement with `SQL statement is not allowed` (403) at render. Read it as `String` and cast defensively with a fallback: `INTERVAL if(toUInt32OrZero({days:String}) = 0, 7, toUInt32OrZero({days:String})) DAY` (fallback = the filter's `default`); free-form numbers use `toInt32OrZero`/`toFloat64OrZero`. Details: `docs/filters-reference.md` § Numeric filters.
- Deployment has no `application_id` — join via `core_entities_scope.application_id = core_entities_application.app_id`.
- Full recipes: `docs/lake-query-recipes.md`. Column/table reference: the sibling `np-lake` skill's `docs/SCHEMA.md`.
- Post-persist, verify the dashboard actually renders — see `docs/verification.md`.

## Authentication

The report is stored per-organization, resolved from your token. Before any API call, verify auth:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh
```

If it fails, tell the user to `export NP_API_KEY='...'` (Platform Settings → API Keys) or
`export NP_TOKEN='...'` and re-run. Never ask for a token in chat.

## Workflow

### 1. Understand / classify (Adaptive content discovery)
Restate what you understood, then classify the request:

- **specific** — names a subject AND at least one of {a named metric, a grouping ("by X"), a time
  range}. Example: "deployments last week by environment".
- **vague** — subject only. Example: "a deployments dashboard".

The classification decides how Step 3 gathers content. If anything about *what* to build is still
ambiguous after classifying, ask before going further — it is always cheaper to ask one question
than to build the wrong dashboard.

### 2. Check auth
Run `check_auth.sh`. Stop if it fails and tell the user how to set `NP_API_KEY`/`NP_TOKEN`.

### 3. Propose the plan and GET EXPLICIT CONFIRMATION (mandatory gate)
Gather the dashboard's content according to the Step 1 classification, then present a short plan and
**wait for the user's "yes"**:

- **specific request →** propose a complete default dashboard (KPIs + charts + a detail table)
  inferred from the subject, list its widgets and filters, and ask the user to confirm or tweak
  ("drop the donut", "add top apps"). A single round is expected when it is already right.
- **vague request →** first use `AskUserQuestion` (`multiSelect: true`) to offer a menu of candidate
  widgets/metrics grouped as KPIs / trend / breakdowns / detail table; let the user assemble the
  set; THEN present the assembled plan for confirmation.

The plan (either path) states, in the user's language:

- **Title** and a one-line description.
- **Widgets** you will build (e.g. "Total deployments KPI, success-rate KPI, deploys-per-day area
  chart, top-failing-apps table").
- **Filters** and their defaults (e.g. "environment — all; period — last 30 days").
- **Dashboard language:** ask **English or Spanish** (default English).
- **Visibility:** ask **user** (only you) or **organization** (whole org). Default `user` unless they say otherwise.

Example: *"I'll build a Deployments dashboard: 2 KPIs (total, success rate), a deploys-per-day area
chart, and a top-failing-apps table. Filters: environment (all) + period (30d). Language: English.
Visibility: user or organization? — confirm and I'll build it."*

Do NOT proceed to Step 4 until the user confirms. If they change something, update the plan and
re-confirm. This gate applies to create, update, and publish alike.

### 4. Design the definition
Write the definition to a temp file, e.g. `${TMPDIR:-/tmp}/np-report-<slug>.json`, using the `Write`
tool, in the confirmed language and visibility. Shape (see `docs/json-schema-reference.md` for the full contract):

```json
{"name":"...","slug":"...","description":"...","schema":{"type":"object","properties":{}},"ui_schema":{"type":"VerticalLayout","elements":[]},"queries":{},"visibility":"user","category_id":null,"nrn_level":"organization"}
```

**Every `queries[*].target` MUST name a property that exists in `schema.properties`** — charts and
data-tables as `type: "array"` with `items.properties` (numeric columns typed `number`/`integer`),
KPIs as `type: "number"`. An undeclared target does not error: the result collapses to the first cell
of the first row and the widget renders blank. See `docs/json-schema-reference.md` § "The binding
contract", which also covers matching SQL aliases to the keys each widget reads.

Use `docs/widget-cookbook.md` for widget shapes and enrichment rules, `docs/filters-reference.md` for
filters, `docs/lake-query-recipes.md` for SQL. A dashboard that covers several independently-read
views belongs in tabs (`Categorization` + `Category`) rather than one long scroll — see
`docs/widget-cookbook.md` § "Pattern 12: Tabbed sections" for the shape and its four silent traps. Apply the enrichment rules (backgrounds, thresholds,
axis labels, chip formatters, section headers). To assign a category, run
`${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh "/report_category"` and pick a
matching `id`.

### 4.5 Idempotent pre-create check (new reports only)
Before creating a NEW report, list existing reports and look for a **same-slug** match — the slug
is derived deterministically from the title, so re-running the same request yields the same slug:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh "/report?visibility=user&limit=100"
```

If a report with the same `slug` already exists, show it and ask the user: **update it in place
(`PATCH /report/<id>`)** or **create a distinct new report** (change the title so the slug differs).
Default to updating. Use only exact slug matching — never fuzzy subject matching, which collides.
This gate does not apply to an explicit `/np-report update <id>` (the id is already known).

### 5. Validate queries and show a checklist
Every query MUST be validated before it is persisted. **Run the binding check first** — it is static
(no Lake, no token) and catches what no amount of query running can: every `target` resolves to a
declared property of the right shape, and every data widget is targeted by some query. See
`docs/verification.md` § "Step 0". A binding failure caught here costs nothing; caught after `POST`
it costs a `PATCH`.

Then show the user a per-query checklist as you go, e.g.:

```
Queries:
  [✓] total-deploys   — created, validated
  [✓] success-rate    — created, validated
  [✗] deploys-per-day — validation failed (fixing…)
```

For each query, run an EXPLAIN via the sibling np-lake script. **Validate the EXACT statement you will
persist, minus its trailing `FORMAT JSON`** — never add anything the persisted query won't have. Run it
**twice**: once with every `{name:Type}` placeholder set to the filter's `default`, and **once with every
filter placeholder EMPTY (`--param x=`)**. The empty run is mandatory: on first render the frontend
sends unset filters as `""`, and a numeric placeholder typed as `{x:UInt32}` passes the default run but
fails the empty run with `SQL statement is not allowed` — exactly the class of bug the empty run exists
to catch. If the empty run fails, fix the SQL (read numeric params as `String` + `toUInt32OrZero`/
`toInt32OrZero` with a fallback — see `docs/filters-reference.md` § Numeric filters), never the default.

```bash
# default run
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --param days=30 --param environment='' \
  "EXPLAIN SELECT count() AS total FROM core_entities_deployment FINAL WHERE _deleted = 0 AND created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY"
# empty run (what the FE actually sends on first render) — MUST also pass
${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh --param days= --param environment= \
  "EXPLAIN SELECT count() AS total FROM core_entities_deployment FINAL WHERE _deleted = 0 AND created_at > now() - INTERVAL if(toUInt32OrZero({days:String}) = 0, 30, toUInt32OrZero({days:String})) DAY"
```

- **On failure** → fix the SQL and retry (max 2 rounds per query); if it still fails, **drop that
  widget**, mark it `[✗] removed` in the checklist, and note it in the final summary. Never persist a
  query that did not validate — an unvalidated query becomes a raw `SQL statement is not allowed` error
  in the user's dashboard.
- **If the Lake is unreachable / no auth / `NO_TOKEN`** → tell the user validation was skipped and that
  queries are unverified; ask whether to persist anyway (do not silently save unverified queries).
- Persisted `source` is the plain `SELECT`/`WITH` (WITH the `FORMAT JSON`) — never the `EXPLAIN` form.

### 6. Persist (draft)
Transport is the sibling np-api script: `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh`.
Write the report definition to a temp file, e.g. `${TMPDIR:-/tmp}/np-report-<slug>.json` (see Step 3),
and pass it with `--data @<file>`.

- **New report:**
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @<file> "/report"
  ```
  → captures the returned `id`.
- **Modify existing (id known):**
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh "/report/<id>"
  ```
  → merge the changes into the definition file →
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method PATCH --data @<file> "/report/<id>"
  ```
- Listing:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh "/report?visibility=<v>&category_id=<c>&limit=<n>&offset=<o>"
  ```

### 7. Post-persist render verification (mandatory before Confirm)
"Saved" is not "renders". Re-fetch the saved report and run the verification in
`docs/verification.md`: first the static **binding check** (every `target` resolves and its shape
matches its widget), then each query twice — once with every filter placeholder EMPTY (what the FE
sends on first load) and once with the defaults. Report the per-widget status table
(binding / ✓ renders / ⚠ empty / ✗ error) and the real KPI values the user will see.

- Any **✗ binding** means the widget renders blank however well the query runs — fix the schema and
  `PATCH`, then re-verify. A returning query is not evidence that its widget renders.
- Any **✗ error** means the dashboard is broken in the UI — fix the SQL and `PATCH` the report, then
  re-verify. Never declare a report done while a query errors.
- Apply the **empty / anomalous data guards** from `docs/verification.md`: explain 0-row widgets and
  extreme rates so a genuine result is never mistaken for a broken report.
- If the Lake is unreachable / token expired, say the render check was skipped and the report is
  unverified.

### 8. Confirm
Report the `id`, name, what it contains (filters, KPIs, charts, tables), any dropped widgets, and that
it is saved as a **draft** — publishing is:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data '{}' "/report/<id>/publish"
```

## Commands

- `/np-report <description>` — create a new report (draft).
- `/np-report list [--visibility <v>] [--category <id>]` — list reports.
- `/np-report show <id>` — read a report.
- `/np-report update <id> <change>` — modify an existing report.
- `/np-report delete <id>` — soft-delete a report.
- `/np-report publish <id>` — publish the current draft.
- `/np-report versions <id>` — list published versions.
- `/np-report categories` — list categories.

All commands run through the np-api `fetch_np_api_url.sh` script. See `docs/api-reference.md` for the
exact invocations.
