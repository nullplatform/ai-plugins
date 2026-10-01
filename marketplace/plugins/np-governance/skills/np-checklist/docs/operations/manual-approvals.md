# Manual Approvals & Overrides

Operations on items that require a human decision: `type: manual` items
(any behavior) and any item with `behavior: override`.

Wire contract: `PATCH /approval/:id/checklist/items/:itemId` with body
`{status: "passed" | "failed", message?, inputs?}` — `approve` maps to
`passed`, `reject` to `failed`. The decision is attributed to the
**caller's JWT** (no actor in the body). There is no `…/items/:id/approve`
endpoint.

## Approve a manual item

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision approve \
  --message "Threat model reviewed, no auth surface changes."
```

What happens server-side:

1. Loads the run by `approval_request_id` (404 if missing or not in
   checklist mode).
2. Validates the item exists in `specification_snapshot` and is `type: manual`
   (or `behavior: override` for the override flow).
3. Validates the caller's authz allows acting on this item's NRN.
4. Updates `item_states[itemId]` to:
   - `status: passed`
   - `details: { approver, decided_at, decision_message }`
5. Triggers a re-aggregation pass (which may resolve the run).
6. Writes a `checklist_event` row (`event_type: item.status_changed`,
   `actor: alice@acme.com`, payload with `from/to/message`).

## Reject a manual item

Same call shape, `--decision reject`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id security_signoff \
  --decision reject \
  --message "Auth changes require a full pentest first."
```

A `reject` on a `gate` manual item moves the run toward `pending_override`
(if there are override items) or `final_outcome = fail`. A `reject` on
an `informational` item is recorded but doesn't change the outcome.

## Override flow

An `override` item is just a `type: manual` item with `behavior:
override`. Approving it has special semantics:

- **Pre-condition**: the run must be in `aggregate_status =
  pending_override` (i.e. at least one `gate` item failed and not all
  `gate` items have resolved otherwise). The server validates this.
- **Effect**: the run resolves with `final_outcome = approve_with_override`,
  and `override_metadata` is set to `{ approver, decided_at, message,
  failed_gates: [...] }`.

The script call is identical:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/manual_approve_item.sh \
  --approval-id 99421 \
  --item-id cab_override \
  --decision approve \
  --message "P0 incident — hotfix needed by EOD, security re-review queued."
```

The aggregation engine routes the decision based on the item's
behavior declared in `specification_snapshot`, not on a special endpoint —
hence the same script handles both manual approvals and overrides.

## Common failure modes

| HTTP | Code | Meaning |
|---|---|---|
| `400` | `CHECKLIST_ITEM.INVALID_DECISION` | `decision` not `approve`/`reject` |
| `403` | (authz) | Caller not allowed to act on this NRN |
| `404` | `APPROVAL_REQUEST.NOT_FOUND` | No request with that id |
| `404` | `CHECKLIST_RUN.NOT_FOUND` | The request exists but is not in checklist mode |
| `404` | `CHECKLIST_ITEM.NOT_FOUND` | No item with that id in the run's specification snapshot |
| `409` | `CHECKLIST_ITEM.NOT_ACTIONABLE` | Item is not `type: manual` or is already resolved |
| `409` | `CHECKLIST_RUN.ALREADY_RESOLVED` | Run is already in a terminal `aggregate_status` |
| `409` | `CHECKLIST_RUN.NOT_AWAITING_OVERRIDE` | Override approve attempted but `aggregate_status != pending_override` |

## Listing items that need a human

There's no dedicated "actionable items for me" endpoint, but the enriched
list response includes `checklist.first_pending_actionable_by_me`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_runs.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --status pending \
  | jq '.results[] | select(.checklist.first_pending_actionable_by_me) | {
      approval_request_id: .id,
      item: .checklist.first_pending_actionable_by_me,
      entity: .entity_name,
      action: .entity_action
    }'
```

This requires the caller's authz info — the server computes
`actionable_by_me` based on the JWT/key used to call the endpoint.

## Audit trail

After any approval / reject, the call also produces:
- A `checklist_event` row capturing the transition (visible via
  `list_events.sh`).
- Updates to `item_states[itemId].details` capturing approver + message.
- `override_metadata` on the run (for override applications).

Use `list_events.sh --types item.status_changed` to get just the
human-driven transitions.

## Escalation: ask for manual review (`ask_for_manual.sh`)

`POST /approval/:id/checklist/ask-for-manual` (body `{reason?}`) hands the
run to the CLASSIC boolean review. Requester-only (`ONLY_REQUESTER`) and
only for actions whose `on_checklist_fail` is not `deny` (`NO_MANUAL_FALLBACK`
otherwise). It works in two windows:

- **Mid-run**: the checklist is still evaluating (e.g. stuck external
  item). Pending items are cancelled with `subStatus:
  early_routed_to_manual`.
- **Resumable fail**: the run already resolved `fail` and the review was
  not requested yet. Nothing is actionable in the checklist, but the
  request is still `pending` — the requester chooses between fixing the
  failed gates and redeploying (cancel + retry), cancelling, or this
  escalation. On this path the run's original `resolved_at` is preserved.

Effect: `outcome_reason` becomes `requested_manual_review`, the front
switches the approval to the classic review view (waiting room), and
**this call is what notifies reviewers** — a resumable fail sits silent
until someone asks.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/ask_for_manual.sh \
  --approval-id 99421 \
  --reason "Gate de cobertura imposible en este repo legacy."
```

Additional failure modes: `409 ALREADY_REPLIED` when the run resolved with
any outcome other than a not-yet-escalated `fail` (approve, cancelled,
expired, or review already requested).
