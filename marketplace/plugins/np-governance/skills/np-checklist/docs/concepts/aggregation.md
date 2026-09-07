# Aggregation Engine

How a `ChecklistRun` derives `aggregate_status` and `final_outcome` from the
per-item states.

## Two-stage flow

```
1. Pre-evaluate (at run creation, in a single DB transaction)
   ├─ condition items   → evaluated against context_snapshot, status = passed | failed
   ├─ external items
   │    ├─ trigger=auto      → status = pending, dispatch queued
   │    └─ trigger=on_demand → status = latent
   ├─ manual items      → status = pending
   └─ group items       → status = pending (walked into via children)

   aggregate_status = pending_items  (unless every item resolved on creation)

2. Re-aggregate (after every state change: callback, manual decision, expiry)
   ├─ Walk all items, collecting their status + behavior
   ├─ Compute derived_expression  (specification's stored expression OR auto-derived)
   ├─ If all items resolved:
   │    ├─ All gate=passed    → final_outcome = approve, status = resolved
   │    ├─ Any gate=failed:
   │    │     ├─ Has override items not yet resolved → status = pending_override
   │    │     ├─ Has override=approved              → final_outcome = approve_with_override, status = resolved
   │    │     └─ Otherwise                          → final_outcome = fail, status = resolved
   │    └─ informational items never block
   └─ Else                          → status = pending_items
```

## Derived expression

By default, the server auto-derives a boolean expression from item
behaviors. For each `gate` item the expression includes a `passed`
predicate; the overall expression is the AND of all gate predicates,
OR'ed with each override item's `passed` predicate.

Terms are `<item_id>.<accessor>`, where the accessor is one of `passed`,
`failed`, `in_progress`, `skipped`, `cancelled`, `timed_out`. Operators
are `AND`, `OR`, `NOT` and parentheses. So the default looks roughly like:

```
( coverage_gate.passed
  AND snyk_high_severity.passed
  AND security_signoff.passed )
OR cab_override.passed
```

Because item ids sit at the head of every term, **`and`, `or`, `not`,
`true` and `false` cannot be used as item ids** — the tokenizer reads them
as operators/literals and then chokes on the `.accessor` that follows, so
the whole expression fails to parse and the run resolves to `fail` with
`aggregation_parse_error`. The validator rejects those ids up front
(`item.id.reserved`). `nor` is not reserved.

Authors can override this by setting a custom `aggregation.expression` in
the specification's `definition` (and `derived_expression` is set explicitly
rather than computed). Use the override sparingly — it's an escape hatch
for combinations the auto-derivation doesn't express.

## Behavior matrix

For a fully resolved run:

| Has gate-failed? | Has override-approved? | `aggregate_status` | `final_outcome` |
|---|---|---|---|
| No (all gates passed) | n/a | `resolved` | `approve` |
| Yes | Yes | `resolved` | `approve_with_override` |
| Yes | No (no override items defined) | `resolved` | `fail` |
| Yes | No (override items defined, none approved yet) | `pending_override` | n/a |
| Some still pending | n/a | `pending_items` | n/a |

Plus the terminal "operator" outcomes that bypass aggregation:
- `cancelled` — run cancelled externally (e.g. the upstream request was cancelled).
- `expired` — the action's `allowed_time_to_execute` window passed before resolution.

## Re-aggregation triggers

Each of these causes a re-aggregation pass within the same transaction:

- A `manual` item approve/reject (`POST .../approve`).
- An `external` item callback (signed token → `POST .../callback`).
- A periodic expiration scan (background job — see `scan_expirations.js`).
- An override application.

Each transition writes a `checklist_event` row with the previous + new
`aggregate_status` to keep a clean audit trail.

## Tips for authoring

- **Order doesn't matter** for evaluation purposes; the engine evaluates
  conditions in parallel and waits for asynchronous items (manual,
  external) independently. Use group items for UI organization, not as
  sequencing primitives.
- **Pick a sensible severity** on each item (`low | medium | high |
  critical`). It does not affect aggregation but drives the UI severity
  badges and helps audit reports.
- **`informational` is your friend** — surface diagnostics (Snyk reports,
  coverage trends, etc.) without blocking releases.
- **Override items should be rare and clearly labeled** — a high-friction
  manual step with strong audit (`description` should reference the
  policy under which an override is acceptable).
