# What Is Persisted

A complete record per checklist run, intentionally more granular than the
classic policy mode. Useful for after-the-fact audits, debugging, and
compliance reporting.

## Per-run, immutable

Captured at run creation, never mutated:

| Field | Lives in | Purpose |
|---|---|---|
| `template_snapshot` | `checklist_run.template_snapshot` (JSONB) | The full template (`id`, `name`, `version`, `definition`, `derived_expression`) as of trigger time. Editing the live template afterwards does **not** affect this run. |
| `context_snapshot` | `checklist_run.context_snapshot` (JSONB) | The context that was evaluated: release, build, application, namespace, account, organization, user, deployment group, etc. — built once by `buildContext` and frozen. Condition paths address this object directly, so `build.metadata.coverage` in a query is `.build.metadata.coverage` here — no `context.` root. |
| `idempotency_key` | `checklist_run.idempotency_key` | Used by the trigger path to dedupe re-tries; UNIQUE in the schema. |

## Per-item state

Stored in `checklist_run.item_states` (JSONB), keyed by `item_id`. Updated
on each transition. For a `condition` item, an entry looks like:

```jsonc
{
  "status": "passed" | "failed",
  "behavior": "gate" | "informational" | "override",
  "severity": "low" | "medium" | "high" | "critical",
  "type": "condition",
  "message": "condition_met" | "condition_not_met" | "evaluation_error: ...",
  "details": {
    "query": { "build.metadata.coverage": { "$gt": 80 } },
    "passed": true
  }
}
```

For other item types the `details` shape varies:

- **`manual`**: `{ approver, decided_at, decision_message }`
- **`external`**: `{ callback_at, executor_id, http_status, response_body_excerpt, ... }`
- **`group`**: no `details`; the children carry their own state.

## Outcome

Set when the run resolves (or moves to a terminal state):

| Field | Type | Notes |
|---|---|---|
| `aggregate_status` | `pending_items | pending_aggregation | pending_override | resolved` | Drives polling — UI keeps polling while non-`resolved`. |
| `final_outcome` | `approve | approve_with_override | fail | cancelled | expired` | Only set once `aggregate_status = resolved` (or for terminal operator actions). |
| `outcome_reason` | TEXT | Human-readable explanation of the outcome. |
| `override_metadata` | JSONB | If `approve_with_override`: who, when, why. |
| `started_at`, `resolved_at` | TIMESTAMPTZ | Duration of the run. |

## Audit trail (`checklist_event`)

A monotonic, append-only sequence of state transitions per run.

```jsonc
{
  "id": "cevt_xxx",
  "checklist_run_id": "crun_xxx",
  "sequence_number": 7,
  "occurred_at": "2026-05-13T15:42:11Z",
  "event_type": "item.status_changed",
  "actor": "alice@acme.com",
  "payload": {
    "item_id": "security_signoff",
    "from": "pending",
    "to": "passed",
    "message": "Threat model reviewed."
  }
}
```

Common `event_type` values:

- `checklist.created` — run created, items pre-evaluated.
- `item.status_changed` — any item state transition.
- `item.dispatched` — `external` item HTTP dispatch sent.
- `item.callback_received` — `external` item callback applied.
- `item.log_appended` — a log row was added (cross-reference into `checklist_item_log`).
- `aggregation.computed` — re-aggregation pass ran.
- `checklist.resolved` — final outcome set.

## Per-item logs (`checklist_item_log`)

Structured log lines per item. Higher-volume than events, useful for
diagnostics:

```jsonc
{
  "id": "clog_xxx",
  "checklist_run_id": "crun_xxx",
  "item_id": "security_signoff",
  "occurred_at": "...",
  "level": "info" | "warn" | "error" | "debug",
  "message": "...",
  "details": { ... }
}
```

The same item often has many log rows over its lifetime (especially
external items waiting on a callback). Rate-limited server-side (100
rows / minute / run by default).

## Compared with policy mode

| | Policy mode | Checklist mode |
|---|---|---|
| Snapshot of evaluated context | `approval_request.policy_context` | `checklist_run.context_snapshot` |
| Snapshot of the gate config | not persisted — current policy is re-read | `checklist_run.template_snapshot` (NOT NULL) |
| Per-predicate / per-item outcome | not persisted | `item_states` (with `message` + `details`) |
| Outcome | `approval_request.status` (binary approve/deny) | `final_outcome` + `outcome_reason` (5 values + text) |
| Audit trail | none | `checklist_event` (with `sequence_number` and `actor`) |
| Per-item log | none | `checklist_item_log` (with `level` + `details`) |
