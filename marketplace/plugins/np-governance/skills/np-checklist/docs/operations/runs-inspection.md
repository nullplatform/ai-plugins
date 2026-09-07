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
    "aggregate_status": "pending_items",
    "items_total": 5,
    "items_passed": 3,
    "items_failed": 0,
    "items_pending": 2,
    "first_pending_actionable_by_me": "security_signoff"
  }
}
```

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
  "resolved_at": null
}
```

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
      items: (.item_states | to_entries | map({id: .key, status: .value.status, message: .value.message}))
    }'
```

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
