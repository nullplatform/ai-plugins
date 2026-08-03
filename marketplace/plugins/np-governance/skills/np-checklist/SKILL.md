---
name: np-checklist
description: Operate on Nullplatform Approval Checklists — create and manage checklist templates, associate them with approval actions, inspect checklist runs (state, items, events, logs), apply manual approvals and overrides, and migrate existing policy-based actions to checklist mode. Use when the user asks to "create a checklist template", "associate a checklist with an action", "view checklist run state", "approve a manual checklist item", "migrate from policies to checklist", or anything about checklist-mode approvals on the approval-api.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/*.sh)
---

# np-checklist

Operational skill for the **Checklist Approvals** domain of the approval-api. A checklist is the alternative to policy-based approvals: each `ApprovalAction` is associated with a `ChecklistTemplate` (XOR with policies) that defines items (`condition`, `manual`, `external`, `group`) with behaviors (`gate`, `informational`, `override`). When an approval-request is triggered, a `ChecklistRun` is created, items are evaluated, and a final outcome is derived.

Public endpoints (gateway):
- `https://api.nullplatform.com/approval/checklist/template`
- `https://api.nullplatform.com/approval/action/:id/checklist_template`
- `https://api.nullplatform.com/approval/:id/checklist`
- `https://api.nullplatform.com/approval/:id/checklist/events`
- `https://api.nullplatform.com/approval/:id/checklist/items/:itemId/logs`
- `https://api.nullplatform.com/approval/checklist/migrate-from-policy/apply` (and `/rollback`)

## Critical Rules

1. **NEVER use `curl` directly** against `api.nullplatform.com`. All scripts delegate to `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh` for auth + retries.
2. **XOR template ↔ policies**: an `ApprovalAction` cannot have both a template and policies at the same time. `set_action_template.sh` returns `409` if the action has live (non-soft-deleted) policies. To switch an existing policy-action to checklist, use `migrate_action.sh`, which archives the policies inside a single transaction.
3. **The feature flag is frontend-only**: `approvals.checklist-mode-enabled` (OpenFeature, default `false`) gates the admin UI for templates. **The backend is agnostic** — these endpoints work regardless of the flag. Useful for platform teams to prepare templates before flipping the flag.
4. **Snapshots are immutable**: when a `ChecklistRun` is created, the template (`template_snapshot`) and the evaluation context (`context_snapshot`) are snapshotted into the run. Later edits to the template do **not** affect live runs. To inspect what was actually evaluated, read `template_snapshot` from the run, not the current template.
5. **IDs are `<prefix>_<nanoid21>`** (VARCHAR(26)): `tmpl_…`, `crun_…`, `cevt_…`, `clog_…`. Non-enumerable, no auto-increment. The scripts handle id generation server-side; do not pass an `id` field to create calls.
6. **`behavior` is mandatory on every item**: `gate` (blocks on failure), `informational` (reports only, never blocks), `override` (when every `gate` item fails, an approved `override` item allows the run to resolve as `approve_with_override`). Validated server-side; missing `behavior` returns `422`.
7. **`mode` filter on list-runs**: `GET /approval` accepts `?mode=policy|checklist`. Legacy rows have `mode = NULL` — to find them, use no `mode` filter and inspect the response field.
8. **Condition paths carry NO `context.` prefix**: `query` and `applies_when` are the same mongo-like language *and the same addressing* as approval policies — write `build.metadata.coverage`, not `context.build.metadata.coverage`. A `context.`-rooted path is rejected at save time (`condition.query.context_rooted_path` / `item.applies_when.context_rooted_path`). The one exception is `external.inputs` mustache placeholders, which keep `{{ context.* }}` — that is the dispatch payload, not the query language.
9. **Never name an item `and`, `or`, `not`, `true` or `false`**: the aggregation grammar reserves those words, so `or.passed` can't be parsed and the run resolves to `fail` / `aggregation_parse_error`. Rejected by the validator with `item.id.reserved`. (`nor` is fine.)
10. **Manual items can declare `inputs` (JSON Schema + optional JSONForms `ui_schema`) and `validations` (same mongo-style query language as policies)** — feature branch, see `docs/concepts/inputs-and-validations.md`. Two traps: `ui_schema` is a JSONForms UISchema (layouts + `Control` scopes), NOT RJSF `"ui:*"` keys; and validations gate ONLY `status: passed` submits — a Reject always applies without running rules (uniform state machine, by design).
11. **External validations dispatch with action `checklist:item:validation_dispatched`** (not `checklist:item:dispatched`) and resolve with `POST …/validations/{validationId}` body `{passed: boolean}` — a different contract from external items. Workflow-side, subscribe via `np-checklist-trigger` with that `action` and close with `np-checklist-validation-resolve`.

## Available Scripts

### Templates CRUD (5)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `list_templates.sh` | `GET /approval/checklist/template` | List templates (filters: `--nrn`, `--status`, `--name`) |
| `get_template.sh` | `GET /approval/checklist/template/:id` | Template detail |
| `create_template.sh` | `POST /approval/checklist/template` | Create template (accepts `--definition-file` with YAML or JSON) |
| `update_template.sh` | `PATCH /approval/checklist/template/:id` | Partial update (typically bumps `version`) |
| `delete_template.sh` | `DELETE /approval/checklist/template/:id` | Soft delete (status → `deleted`) |

### Action ↔ Template (2)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `set_action_template.sh` | `POST /approval/action/:id/checklist_template` | Associate template with action. Fails with XOR violation if the action has policies |
| `remove_action_template.sh` | `DELETE /approval/action/:id/checklist_template` | Dissociate. Idempotent |

### Runs Inspection (4)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `list_runs.sh` | `GET /approval?mode=checklist` | List approval-requests running in checklist mode (filters: `--status`, `--nrn`, `--final-outcome`, `--limit`) |
| `get_run.sh` | `GET /approval/:id/checklist` | Full run state: items + aggregate + outcome |
| `list_events.sh` | `GET /approval/:id/checklist/events` | Paginated audit trail (filters: `--types`, `--limit`, `--cursor`) |
| `list_item_logs.sh` | `GET /approval/:id/checklist/items/:itemId/logs` | Per-item logs (filters: `--level`, `--limit`) |

### Manual / Override (1)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `manual_approve_item.sh` | `POST /approval/:id/checklist/items/:itemId/approve` | Approve / reject a manual item or apply an override |

### Migration (3)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `migrate_action.sh` | `POST /approval/checklist/migrate-from-policy/apply` | Migrate an action from policy mode to checklist (soft-deletes policies, associates a derived template) |
| `rollback_migration.sh` | `POST /approval/checklist/migrate-from-policy/rollback` | Revert a migration (restores policies, removes template association) |
| `dry_run_template.sh` | `POST /approval/checklist/template/:id/dry-run` | Pre-evaluate a template against a supplied context (preview of item outcomes without creating a run) |

## Documentation (progressive disclosure)

### Conceptual (load on demand when the model is needed)

@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/model.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/modes.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/item-types.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/aggregation.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/inputs-and-validations.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/persistence.md

### Operational (how to use the scripts)

@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/templates-crud.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/action-association.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/runs-inspection.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/manual-approvals.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/migration.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/troubleshooting.md

## Examples

### 1. Author a template from a YAML spec

A template is a versioned JSON `definition` field. The script accepts YAML or JSON via `--definition-file` and converts to JSON before posting.

```bash
cat > /tmp/prod-deploy-gate.yaml <<'EOF'
items:
  - id: coverage_gate
    type: condition
    behavior: gate
    severity: high
    query:
      "build.metadata.coverage": { "$gt": 80 }

  - id: snyk_high_severity
    type: condition
    behavior: gate
    severity: critical
    query:
      "build.metadata.snyk.high": { "$eq": 0 }

  - id: security_signoff
    type: manual
    behavior: gate
    title: "Security team sign-off"
    description: "Required for production releases touching auth or PII."
    severity: high

  - id: cab_override
    type: manual
    behavior: override
    title: "CAB emergency override"
    description: "Use only when blocking gates are misconfigured and a release must ship now."

  - id: notify_oncall
    type: external
    behavior: informational
    external:
      channel: http
      url: "https://hooks.acme.com/oncall/notify"
      method: POST
      trigger: auto
EOF

${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_template.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "prod-deploy-gate" \
  --definition-file /tmp/prod-deploy-gate.yaml \
  --created-by "platform-team@acme.com" \
  --description "Production deploy gate: coverage + Snyk + security sign-off, with CAB override."
```

The returned object includes the generated `id` (`tmpl_…`) and the server-derived `derived_expression` (the boolean expression that combines all `gate` items, used by the aggregation engine).

### 2. Associate a template with an action

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_template.sh \
  --action-id 1842 \
  --template-id tmpl_abc123def456ghi789jk
```

If the action still has live policies, this fails with `409 APPROVAL_ACTION_HAS_POLICIES_XOR`. Use `migrate_action.sh` (below) instead.

### 3. List runs for a namespace and inspect the one that failed

```bash
# Find recent failed checklist runs
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_runs.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --final-outcome fail \
  --limit 10

# Drill in
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421
# → returns aggregate_status, final_outcome, outcome_reason, and the full
#   item_states map (each item with status, message, details).

# See the full audit trail
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_events.sh \
  --approval-id 99421 --limit 100

# Drill into a specific item's logs
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_item_logs.sh \
  --approval-id 99421 \
  --item-id snyk_high_severity \
  --level error
```

### 4. Approve a manual item (humans-in-the-loop)

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision approve \
  --actor "alice@acme.com" \
  --message "Threat model reviewed, no changes to auth surface."
```

To reject instead of approve:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision reject \
  --actor "alice@acme.com" \
  --message "Auth changes need a full pentest first."
```

For an emergency override (item with `behavior: override`), the call shape is identical — the aggregation engine routes it correctly based on the item's declared behavior.

### 5. Dry-run a template against a real context

Useful when editing a template — preview which items would pass/fail without creating a run.

The context file is the **bare catalog**, addressed exactly as the template's `query` paths address it: `build.metadata.coverage` in a query reads `.build.metadata.coverage` from this file. (The script wraps it in a `context` request-body field on the way out; that wrapper is transport, not addressing.)

```bash
cat > /tmp/sample-context.json <<'EOF'
{
  "build": { "metadata": { "coverage": 76, "snyk": { "high": 0, "critical": 1 } } },
  "release": { "id": "rel_abc" },
  "application": { "slug": "billing-api" }
}
EOF

${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/dry_run_template.sh \
  --template-id tmpl_abc123def456ghi789jk \
  --context-file /tmp/sample-context.json
# → returns preview.items[] with each item's predicted status + aggregate_prediction
```

### 6. Migrate an existing policy-action to checklist mode

```bash
# First, see what the equivalent template would look like (no writes)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --dry-run

# If it looks right, apply:
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --created-by "platform-team@acme.com"
# → soft-deletes policies, creates a derived template, associates it.
#   The action now resolves checklist runs instead of evaluating policies.

# If something looks off, rollback (restores policies, removes template):
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/rollback_migration.sh --action-id 1842
```

### 7. End-to-end: from template to first run

```bash
# 1. Create the template
TEMPLATE=$(${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_template.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "staging-smoke" \
  --definition-file /tmp/staging-smoke.yaml \
  --created-by "alice@acme.com")
TEMPLATE_ID=$(echo "$TEMPLATE" | jq -r '.id')

# 2. Associate with a NEW action (no existing policies)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_template.sh \
  --action-id 4711 --template-id "$TEMPLATE_ID"

# 3. (User triggers a deploy → an approval_request is created → backend creates a checklist_run)
# 4. Poll the run state from outside (the admin UI does this every 5s)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id <approval_request_id>
```

## Authentication

All scripts inherit auth from `np-api`. Set one of:

```bash
# Recommended: API key (no expiry, token is cached)
export NP_API_KEY='sk-...'

# Alternative: bearer token (~24h expiry)
export NP_TOKEN='eyJ...'
```

Verify with: `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh`

## Roles Required

You don't grant capabilities one by one in Nullplatform — you get a **role** (scoped by NRN) and the role brings what you need:

- **`secops`, `ops`, `admin`** — full lifecycle: author templates, link them to actions, run migrations, approve items.
- **`developer`** — read templates, dry-run, see your runs, approve manual items / retry external items on runs scoped to your NRN.
- **`member`, `troubleshooting`** — read-only on templates and runs.

If you hit a `403`, you're either missing the right role on the target NRN, or the role catalog hasn't been rolled out yet for checklist capabilities on your account. See `docs/concepts/permissions.md` for the full mapping and the diagnostic flow.

## Related Skills

- **`np-api`**: auth + fetch wrapper for `api.nullplatform.com`. Every script in this skill goes through it.
- **`np-lake`**: analytical queries over `approval_request` / `approval_action` / `checklist_run` (joins, aggregations). Prefer over many sequential API calls for reporting.
- **`np-investigation-diagnostic`**: for diagnosing approval-requests that are stuck (covers classic mode too, not just checklist).
- **`np-developer-actions`**: deploy / scope / parameter operations — the upstream events that trigger an `ApprovalRequest`, which a `ChecklistRun` then evaluates.
