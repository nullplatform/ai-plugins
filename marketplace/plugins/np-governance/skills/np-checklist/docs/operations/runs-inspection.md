# Inspecting Checklist Runs

How to find and read the state of an approval-request running in
checklist mode.

## Listing runs

```bash
# Recent runs across a namespace
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_runs.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --limit 50

# Only failed runs
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_runs.sh \
  --nrn "organization=1" \
  --final-outcome fail

# Only pending runs (still waiting on items)
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_runs.sh \
  --status pending
```

Returns an enriched approval-request list (`mode=checklist` rows only).
Each row carries a small `checklist` summary in addition to the
approval-request fields:

```jsonc
{
  "id": 99421,
  "nrn": "organization=1::account=2::namespace=3",
  "entity_name": "scope",
  "entity_action": "scope:deploy",
  "status": "pending",
  "execution_status": null,
  "mode": "checklist",
  "checklist_run_id": "crun_xxx",
  "checklist": {
    "run_id": "crun_xxx",
    "aggregate_status": "pending_items",
    "final_outcome": null,
    "outcome_reason": null,
    "items_summary": {
      "total": 5,
      "passed": 3,
      "failed": 0,
      "pending": 2,
      "skipped": 0,
      "undetermined": 0,
      "hidden": 0,
      "first_pending_actionable_by_me": "security_signoff"
    },
    "action_config": { "on_checklist_fail": "pending" }
  }
}
```

`items_summary` is the same summary the run read carries. Items hidden
from the runner count only in `hidden` (see "Hidden items" below).

Tip: for cross-cutting analyses (e.g. "all checklist runs that took >24h
to resolve"), use `np-lake` rather than this endpoint — much faster.

## Full state of a single run

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421
```

Returns:

```jsonc
{
  "id": "crun_xxx",
  "approval_request_id": 99421,
  "specification_id": "spec_xxx",
  "aggregate_status": "pending_override",
  "final_outcome": null,
  "outcome_reason": "Coverage gate failed; awaiting CAB override.",
  "item_states": {
    "coverage_gate": {
      "status": "failed",
      "behavior": "gate",
      "severity": "high",
      "type": "condition",
      "message": "condition_not_met",
      "details": {
        "query": { "build.metadata.coverage": { "$gt": 80 } },
        "passed": false
      }
    },
    "cab_override": {
      "status": "pending",
      "behavior": "override",
      "type": "manual"
    },
    ...
  },
  "specification_snapshot": { /* full specification as of run creation */ },
  "context_snapshot": { /* full evaluated context */ },
  "started_at": "...",
  "resolved_at": null,
  "execution": {
    "trigger": "explicit",
    "automatic_run": false,
    "on_approval": "wait"
  }
}
```

`execution` says what an approval of this run does with the action behind
it: `trigger` is the snapshot's `definition.execution_trigger` (`explicit`
when the specification does not set it), `automatic_run` whether no person
or external system took part (always `false` while the run is
`pending_override`, as here), and `on_approval` is `execute` (the approval
starts the action on its own) or `wait` (someone has to start it with
`POST /approval/{id}/execute`).
Before the run resolves it tells what will happen; after, read it next to
the approval's `execution_status` (`GET /approval/{id}`) to tell what did:
`execute` goes with `executing` / `success` / `failed`, `wait` with
`pending` until someone starts it. The rule behind the three fields is in
`docs/concepts/modes.md` ("Success path").

(During the rename transition the read also mirrors the legacy
`template_id` / `template_snapshot` keys — same values.)

The `context_snapshot` and `specification_snapshot` are usually large —
pipe through `jq` to project the parts you need:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
  | jq '{
      aggregate_status,
      final_outcome,
      outcome_reason,
      execution,
      items: [.items[] | {id, status, message}]
    }'
```

### Hidden items

A specification can declare `visibility: hidden` on an item or a group
(`docs/concepts/item-types.md`, "Visibility"). The run read resolves it
for this run, so an agent reads the result instead of re-deriving it:

- Every entry of `items[]`, groups included, carries the effective
  `visibility`: `visible`, or `hidden` while the item neither decides nor
  holds the run. A hidden gate that failed, or that the open run waits on,
  arrives `visible`, and so do its ancestor groups. Under a hidden `any`
  group the group decides: once it passed, a child that failed or is
  still open arrives `hidden`.
- `items_summary` leaves effectively hidden items out of `total`, every
  bucket and `first_pending_actionable_by_me`, and counts them in
  `hidden`. A run waiting on a tech lead approval, with one hidden gate
  waiting on it too:

  ```jsonc
  {
    "total": 3,
    "passed": 2,
    "failed": 0,
    "pending": 1,
    "skipped": 0,
    "undetermined": 0,
    "hidden": 1,
    "first_pending_actionable_by_me": "tech_lead_approval"
  }
  ```
- `specification_snapshot` still carries every item as declared: nothing
  is pruned.

To see what the runner leaves out, and why:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
  | jq '[.items[] | select(.visibility == "hidden")
         | {id, type, behavior, status, sub_status, depends_on}]'
```

A hidden item is still evaluated, aggregated and audited: its events and
logs read the same as any other item's.

## Audit trail (events)

```bash
# Last 100 events
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_events.sh --approval-id 99421 --limit 100

# Only status-change events
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_events.sh \
  --approval-id 99421 \
  --types item.status_changed,aggregation.computed
```

Each event has `sequence_number` (monotonic per run) — the response is
sorted by it. `actor` is `null` for system-derived events, an
`email@org` for human actions, or the executor id for external callbacks.

## Per-item logs

For diagnosing item-level issues (especially `external` items):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_item_logs.sh \
  --approval-id 99421 \
  --item-id snyk_high_severity \
  --level error \
  --limit 50
```

Useful patterns:

- **An `external` item stuck pending**: check its logs for the dispatch
  HTTP status code (`info` level), then check `checklist_event` for any
  `item.callback_received` (or its absence).
- **A `condition` item with `evaluation_error`**: the `details` blob on
  the item state already explains why (missing context key, type
  mismatch, invalid query operator). Logs add timestamps and any
  retries.

## Finding the run for a known approval-request

If you have the approval-request id (`approval_request_id`, integer),
just use that as `--approval-id`. If you have the run id (`crun_xxx`),
list runs filtered by NRN and find the matching `checklist_run_id` —
the API does not currently expose a "lookup approval-request by
checklist-run id" endpoint.

For that case, `np-lake` is the right tool:

```sql
SELECT approval_request_id
FROM checklist_run
WHERE id = 'crun_xxx';
```
