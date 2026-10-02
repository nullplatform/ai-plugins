---
name: np-checklist
description: Operate on Nullplatform Approval Checklists — create and manage checklist specifications (formerly "checklist templates"), associate them with approval actions, inspect checklist runs (state, items, events, logs), apply manual approvals and overrides, and migrate existing policy-based actions to checklist mode. Use when the user asks to "create a checklist specification", "create a checklist template", "associate a checklist with an action", "view checklist run state", "approve a manual checklist item", "migrate from policies to checklist", or anything about checklist-mode approvals on the approval-api.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/*.sh)
---

# np-checklist

Operational skill for the **Checklist Approvals** domain of the approval-api. A checklist is the alternative to policy-based approvals: each `ApprovalAction` is associated with a `ChecklistSpecification` (XOR with policies) that defines items (`condition`, `manual`, `external`, `group`) with behaviors (`gate`, `informational`, `override`). When an approval-request is triggered, a `ChecklistRun` is created, items are evaluated, and a final outcome is derived.

> **Naming note**: `ChecklistSpecification` was called `ChecklistTemplate` until mid-2026. The API still serves the legacy `/checklist/template` routes and `*_template_*` payload keys as deprecated aliases; this skill uses only the canonical `specification` contract.

Public endpoints (gateway):
- `https://api.nullplatform.com/approval/checklist/specification`
- `https://api.nullplatform.com/approval/action/:id/checklist_specification`
- `https://api.nullplatform.com/approval/:id/checklist`
- `https://api.nullplatform.com/approval/:id/checklist/events`
- `https://api.nullplatform.com/approval/:id/checklist/items/:itemId/logs`
- `https://api.nullplatform.com/approval/checklist/migrate_from_policy/apply` (and `/rollback`)
- `https://api.nullplatform.com/approval/dry-run`

## Critical Rules

1. **NEVER use `curl` directly** against `api.nullplatform.com`. All scripts delegate to `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh` for auth + retries.
2. **XOR specification ↔ policies**: an `ApprovalAction` cannot have both a specification and policies at the same time. `set_action_specification.sh` returns `409` if the action has live (non-soft-deleted) policies. To switch an existing policy-action to checklist, use `migrate_action.sh`, which archives the policies inside a single transaction.
3. **The feature flag is frontend-only**: `approvals.checklist-mode-enabled` (OpenFeature, default `false`) gates the admin UI for specifications. **The backend is agnostic** — these endpoints work regardless of the flag. Useful for platform teams to prepare specifications before flipping the flag.
4. **Snapshots are immutable**: when a `ChecklistRun` is created, the specification (`specification_snapshot`) and the evaluation context (`context_snapshot`) are snapshotted into the run. Later edits to the specification do **not** affect live runs. To inspect what was actually evaluated, read `specification_snapshot` from the run, not the current specification. (During the rename transition the run read also mirrors the legacy `template_snapshot` key — same value.)
5. **IDs are `<prefix>_<nanoid>`**, non-enumerable, no auto-increment: specifications are `spec_<nanoid16>` (created before the rename: `tmpl_<nanoid16>` — both coexist, IDs are opaque, never rewrite one); runs/events/logs are `crun_…`, `cevt_…`, `clog_…` (nanoid21). The scripts handle id generation server-side; do not pass an `id` field to create calls.
6. **`behavior` is mandatory on every item**: `gate` (blocks on failure), `informational` (reports only, never blocks), `override` (when every `gate` item fails, an approved `override` item allows the run to resolve as `approve_with_override`). Validated server-side; missing `behavior` returns `422`.
7. **`mode` filter on list-runs**: `GET /approval` accepts `?mode=policy|checklist`. Legacy rows have `mode = NULL` — to find them, use no `mode` filter and inspect the response field.
8. **Condition paths carry NO `context.` prefix**: `query` and `applies_when` are the same mongo-like language *and the same addressing* as approval policies — write `build.metadata.coverage`, not `context.build.metadata.coverage`. A `context.`-rooted path is rejected at save time (`condition.query.context_rooted_path` / `item.applies_when.context_rooted_path`). The one exception is `external.inputs` mustache placeholders, which keep `{{ context.* }}` — that is the dispatch payload, not the query language.
9. **Never name an item `and`, `or`, `not`, `true` or `false`**: the aggregation grammar reserves those words, so `or.passed` can't be parsed and the run resolves to `fail` / `aggregation_parse_error`. Rejected by the validator with `item.id.reserved`. (`nor` is fine.)
10. **Manual items can declare `inputs` (JSON Schema + optional JSONForms `ui_schema`) and `validations` (same mongo-style query language as policies)** — feature branch, see `docs/concepts/inputs-and-validations.md`. Two traps: `ui_schema` is a JSONForms UISchema (layouts + `Control` scopes), NOT RJSF `"ui:*"` keys; and validations gate ONLY `status: passed` submits — a Reject always applies without running rules (uniform state machine, by design).
11. **External validations dispatch with action `checklist:item:validation_dispatched`** (not `checklist:item:dispatched`) and resolve with `POST …/validations/{validationId}` body `{passed: boolean}` — a different contract from external items. Workflow-side, subscribe via `np-checklist-trigger` with that `action` and close with `np-checklist-validation-resolve`.
12. **`severity` enum is `critical | major | minor | info`** — `high`/`medium`/`low` are rejected at save time (`item.severity.invalid`).
13. **Fail semantics come from the action's `on_checklist_fail`** (`deny` | `pending` | `manual`, surfaced on the run read as `action_config.on_checklist_fail`; default `pending`). `deny` → a failed run auto-denies the request (`auto_denied`) and `ask_for_manual.sh` is rejected with `NO_MANUAL_FALLBACK`. `pending` → the request stays `pending` in a **resumable fail**: nobody is notified, the requester chooses between (a) fixing the cause and redeploying (cancel + retry — the cheap path, designed for agents that can read the failed gates and fix the code), (b) cancelling, or (c) explicitly requesting classic review with `ask_for_manual.sh`, which terminates the run with `outcome_reason=requested_manual_review`, flips the front to the classic boolean approval, and is the moment reviewers get notified. `manual` → a failed run skips the resumable step and goes STRAIGHT to classic review — `outcome_reason` is relabeled `requested_manual_review` and reviewers are notified immediately. Set with `np approval action create/patch --body '{"on_checklist_fail": "deny"|"pending"|"manual"}'`. On `approve`, requests land `auto_approved` regardless of `on_policy_success`; whether the approved action then starts on its own is decided by `definition.execution_trigger` (rule 16).
14. **`update_specification.sh` mints a NEW specification id on EVERY update** (any field — the API creates a new version row; there is no in-place mutation, and a `status` field in the body is ignored) — the action keeps pointing at the old id. Always re-run `set_action_specification.sh` with the returned id after updating.
15. **API keys are NOT `user.id` = key id in conditions**: an api key acts as its own principal user (email `apikey+<org>+<keyId>@nullplatform.io`). To gate on "deploy iniciado por la key X", find that principal id — exchange the key for a token and read `cognito:groups` (`@nullplatform/user=<id>`), or check `created_by` on an entity created with the key — and write `user.id == <principal_id>` (not the key id).
16. **`definition.execution_trigger` decides what starts the approved action** (a key next to `items`): `explicit` (the default; absent and `null` read `explicit`) → someone starts it (Start deployment / Create scope / Apply changes, or `POST /approval/{id}/execute`); `automatic_approval` → it starts on its own when no person or external system took part in the run (conditions, manual items pruned at creation by a static `applies_when`, informational items and unused overrides count as neither); `any_approval` → it starts on its own on any approval, a reviewer approving the manual review included. Any other value → `422 VALIDATION_FAILED`, `rule: execution_trigger.invalid`. It is read from the run's `specification_snapshot`: changing it means a new specification version re-associated with the action (rule 14), and only runs created afterwards see it. Whatever the trigger, `action_item:defer` / `reject` / `resolve` run on approval, and nothing starts on its own for a deployment that belongs to a deployment group (the group's approval starts it) or for an approval with no registered callback (`parameter:read-secrets`). The run read carries `execution: { trigger, automatic_run, on_approval }`: read `on_approval` (`execute` | `wait`) instead of re-deriving the rule. Full rule: `docs/concepts/modes.md`.

## Available Scripts

### Specifications CRUD (5)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `list_specifications.sh` | `GET /approval/checklist/specification` | List specifications (`--nrn` REQUIRED — the API 400s without it; filters: `--status`, `--name` substring match) |
| `get_specification.sh` | `GET /approval/checklist/specification/:id` | Specification detail |
| `create_specification.sh` | `POST /approval/checklist/specification` | Create specification (accepts `--definition-file` with YAML or JSON) |
| `update_specification.sh` | `PATCH /approval/checklist/specification/:id` | Partial update — creates a NEW version row with a NEW id (no `--status`; use delete for that) |
| `delete_specification.sh` | `DELETE /approval/checklist/specification/:id` | Soft delete (status → `deleted`) |

### Action ↔ Specification (2)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `set_action_specification.sh` | `POST /approval/action/:id/checklist_specification` | Associate specification with action (body `checklist_specification_id`). Fails with XOR violation if the action has policies |
| `remove_action_specification.sh` | `DELETE /approval/action/:id/checklist_specification` | Dissociate. Idempotent |

### Runs Inspection (4)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `list_runs.sh` | `GET /approval?mode=checklist` | List approval-requests running in checklist mode (filters: `--status`, `--nrn`, `--final-outcome`, `--limit`) |
| `get_run.sh` | `GET /approval/:id/checklist` | Full run state: items + aggregate + outcome |
| `list_events.sh` | `GET /approval/:id/checklist/events` | Paginated audit trail (filters: `--types`, `--limit`, `--cursor`) |
| `list_item_logs.sh` | `GET /approval/:id/checklist/items/:itemId/logs` | Per-item logs (filters: `--level`, `--limit`) |

### Manual / Override / Escalation (2)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `manual_approve_item.sh` | `PATCH /approval/:id/checklist/items/:itemId` | Approve (`status=passed`) / reject (`status=failed`) a manual item or apply an override. Actor comes from the caller's JWT |
| `ask_for_manual.sh` | `POST /approval/:id/checklist/ask-for-manual` | Requester-only: hand the run to classic manual review (works mid-run or on a resumable fail). This is what notifies reviewers |

### Migration (3)

| Script | Endpoint | Purpose |
|--------|----------|---------|
| `migrate_action.sh` | `POST /approval/checklist/migrate_from_policy/apply` | Migrate an action from policy mode to checklist (soft-deletes policies, associates a derived specification) |
| `rollback_migration.sh` | `POST /approval/checklist/migrate_from_policy/rollback` | Revert a migration (restores policies, removes specification association) |
| `dry_run_specification.sh` | `POST /approval/dry-run` | Pre-evaluate the checklist of an action against a supplied context (preview of item outcomes without creating a run) |

## Documentation (progressive disclosure)

### Conceptual (load on demand when the model is needed)

@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/model.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/modes.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/item-types.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/aggregation.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/inputs-and-validations.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/concepts/persistence.md

### Operational (how to use the scripts)

@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/specifications-crud.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/action-association.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/runs-inspection.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/manual-approvals.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/migration.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/docs/operations/troubleshooting.md

## Examples

### 1. Author a specification from a YAML file

A specification is a versioned JSON `definition` field. The script accepts YAML or JSON via `--definition-file` and converts to JSON before posting.

```bash
cat > /tmp/prod-deploy-gate.yaml <<'EOF'
items:
  - id: coverage_gate
    type: condition
    behavior: gate
    severity: major
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
    severity: major

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

${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_specification.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "prod-deploy-gate" \
  --definition-file /tmp/prod-deploy-gate.yaml \
  --created-by "platform-team@acme.com" \
  --description "Production deploy gate: coverage + Snyk + security sign-off, with CAB override."
```

The returned object includes the generated `id` (`spec_…`; specifications created before the rename keep `tmpl_…`) and the server-derived `derived_expression` (the boolean expression that combines all `gate` items, used by the aggregation engine).

### 2. Associate a specification with an action

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_specification.sh \
  --action-id 1842 \
  --specification-id spec_a1b2c3d4e5f6g7h8
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

The wire call is `PATCH /approval/:id/checklist/items/:itemId` with
`{status: passed|failed}` — the decision is attributed to the **caller's JWT**
(there is no `--actor` in the body; the flag is accepted and ignored for
backward compatibility).

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision approve \
  --message "Threat model reviewed, no changes to auth surface."
```

To reject instead of approve:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision reject \
  --message "Auth changes need a full pentest first."
```

If the item declares `inputs`, pass the values as JSON — validations (e.g.
four-eyes) run only on approve; a reject always applies:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 --item-id cab_approval --decision approve \
  --inputs '{"cab_ticket": "CAB-2026-0042", "risk_level": "low"}'
```

For an emergency override (item with `behavior: override`), the call shape is identical — the aggregation engine routes it correctly based on the item's declared behavior.

### 4b. The resumable fail → fix-and-redeploy (or escalate)

With `on_checklist_fail: "pending"` (the default), a failed run leaves the request `pending` and
**nobody is notified**: the requester (human or agent) owns the next move.
The intended loop for an agent:

```bash
# 1. Read WHY it failed: each failed gate carries its query (the expected
#    condition) — compare against context_snapshot to know what to fix.
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
  | jq '{reason: .outcome_reason,
         failed_gates: [.items[] | select(.status=="failed" and .behavior=="gate")
                        | {id, title, query: .state.details.query}]}'

# 2a. CHEAP PATH: fix the cause (code, metadata, coverage…), cancel this
#     request and redeploy — the new deployment re-evaluates the checklist.
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh \
  --method POST --data '{}' "/approval/99421/cancel"

# 2b. LAST RESORT: the gate genuinely needs a human exception — hand it to
#     classic review (this is what notifies reviewers).
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/ask_for_manual.sh \
  --approval-id 99421 \
  --reason "No puedo cumplir el gate de cobertura: repo legacy sin tests."
```

### 5. Dry-run a checklist against a real context

Useful when editing a specification — preview which items would pass/fail without creating a run.

There is no by-id dry-run: `POST /approval/dry-run` resolves the approval action from `(nrn, action)` and evaluates **that action's** associated specification. Associate the specification first (`set_action_specification.sh`), then dry-run the action.

The context file is the **bare catalog**, addressed exactly as the specification's `query` paths address it: `build.metadata.coverage` in a query reads `.build.metadata.coverage` from this file. (The script wraps it in a `context` request-body field on the way out; that wrapper is transport, not addressing. Supplying a context also makes the server skip `buildContext`, so the preview is deterministic.)

```bash
cat > /tmp/sample-context.json <<'EOF'
{
  "build": { "metadata": { "coverage": 76, "snyk": { "high": 0, "critical": 1 } } },
  "release": { "id": "rel_abc" },
  "application": { "slug": "billing-api" }
}
EOF

${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/dry_run_specification.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --action "deployment:create" \
  --context-file /tmp/sample-context.json
# → returns preview.items[] with each item's predicted status + aggregate_prediction.
#   The resolved specification is echoed under `specification_snapshot` (the
#   response also mirrors the deprecated `template_snapshot` alias — same value).
```

### 6. Migrate an existing policy-action to checklist mode

```bash
# First, see what the equivalent specification would look like (no writes)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --dry-run

# If it looks right, apply (previews again and sends the generated
# specification as expected_specification — 409 if policies drifted):
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh --action-id 1842
# → soft-deletes policies, creates a derived specification, associates it.
#   created_by is credited to the caller's JWT. The action now resolves
#   checklist runs instead of evaluating policies.

# If something looks off, rollback (restores policies, removes specification):
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/rollback_migration.sh --action-id 1842
```

### 7. End-to-end: from specification to first run

```bash
# 1. Create the specification
SPECIFICATION=$(${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_specification.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "staging-smoke" \
  --definition-file /tmp/staging-smoke.yaml \
  --created-by "alice@acme.com")
SPECIFICATION_ID=$(echo "$SPECIFICATION" | jq -r '.id')

# 2. Associate with a NEW action (no existing policies)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_specification.sh \
  --action-id 4711 --specification-id "$SPECIFICATION_ID"

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

- **`secops`, `ops`, `admin`** — full lifecycle: author specifications, link them to actions, run migrations, approve items.
- **`developer`** — read specifications, dry-run, see your runs, approve manual items / retry external items on runs scoped to your NRN.
- **`member`, `troubleshooting`** — read-only on specifications and runs.

If you hit a `403`, you're either missing the right role on the target NRN, or the role catalog hasn't been rolled out yet for checklist capabilities on your account. See `docs/concepts/permissions.md` for the full mapping and the diagnostic flow.

## Related Skills

- **`np-api`**: auth + fetch wrapper for `api.nullplatform.com`. Every script in this skill goes through it.
- **`np-lake`**: analytical queries over `approval_request` / `approval_action` / `checklist_run` (joins, aggregations). Prefer over many sequential API calls for reporting.
- **`np-investigation-diagnostic`**: for diagnosing approval-requests that are stuck (covers classic mode too, not just checklist).
- **`np-developer-actions`**: deploy / scope / parameter operations — the upstream events that trigger an `ApprovalRequest`, which a `ChecklistRun` then evaluates.
