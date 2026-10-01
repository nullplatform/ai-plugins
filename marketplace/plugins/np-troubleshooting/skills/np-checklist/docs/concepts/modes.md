# Policy Mode vs Checklist Mode

The approval-api supports two evaluation modes for an `ApprovalAction`:

| Mode | Configured via | Evaluated by | UI |
|---|---|---|---|
| **Policy** (legacy, default) | `approval_action_policy` rows linking to one or more `policy` records | The policy engine on each `ApprovalRequest`, against `policy_context` | Classic approve/deny modal |
| **Checklist** | `approval_action.checklist_specification_id` pointing to a `checklist_specification` | The checklist run engine — items evaluated, aggregated into a final outcome | Runner UI (per-item status, manual approvals, events) |

The two modes differ in orchestration, not in how a condition is written:
a checklist `condition` item and a policy predicate use the same
mongo-like query language over the same context catalog, **addressed the
same way** (`build.metadata.coverage` in both — no `context.` prefix in
either). That is what lets `migrate_action.sh` carry a predicate across
verbatim.

## XOR rule

An action is **either policy-driven OR checklist-driven, never both**.

- `POST /action/:id/checklist_specification` fails with `409
  APPROVAL_ACTION_HAS_POLICIES_XOR` if any live (`deleted_at IS NULL`)
  policy is still associated with the action.
- The recommended path to switch an existing policy-action to checklist is
  the migrate_from_policy flow (`POST /checklist/migrate_from_policy/preview`
  then `…/apply`, wrapped by `migrate_action.sh`), which performs the swap
  (soft-delete policies + associate specification + create derived
  expression) inside a single transaction.
- `POST /checklist/migrate_from_policy/rollback` reverses the swap.
- The hyphenated `migrate-from-policy` paths remain in the API as deprecated
  aliases — you may still see them in older logs.

## How the backend decides which path to take

When an `ApprovalRequest` is created, the backend looks at the resolved
`ApprovalAction`:

```
if approvalAction.checklistSpecificationId is set:
    → create a ChecklistRun (snapshots specification + context)
    → mode = 'checklist'
else:
    → evaluate policies as before
    → mode = 'policy'  (or NULL for legacy rows)
```

The `mode` column on `approval_request` records the path taken so list /
read endpoints can route the response shape.

## Feature flag (frontend-only)

The OpenFeature flag `approvals.checklist-mode-enabled` (key:
`FEATURE_FLAGS.CHECKLIST_MODE_ENABLED`, default `false`) lives **only in
the admin-dashboard frontend**. It gates:

- The "Checklist Specifications" admin pages (list, new, edit, detail).
- The "Migrate to checklist" wizard.

When `false`, the admin UI for specifications is hidden; users do not see
checklist-mode workflows in the UI. However:

- **The backend is agnostic to the flag.** Endpoints in this skill work
  regardless of the flag's state — useful for platform teams who want to
  prepare specifications ahead of a rollout, or for API consumers (BFFs,
  CLIs, external tools) that bypass the UI.
- **Existing checklist runs continue to evaluate** even if the flag is
  switched off after they were created. Turning the flag off does **not**
  fall existing requests back to policy mode (`mode` on the request is
  fixed at creation time).

In other words, the flag controls **who can author and trigger** new
checklist flows from the UI, not the runtime behavior of existing ones.

## When to choose which

Use **checklist mode** when:
- The gate has a mix of conditions you want to evaluate automatically and
  steps that require humans (or external systems) to act.
- You want a granular audit trail of every item's evaluation.
- You want to allow humans to override a failed gate in well-defined
  circumstances (CAB emergency overrides, etc.).
- You want to dry-run the gate against arbitrary contexts before deploying.

Use **policy mode** when:
- The existing policies cover your needs and the team has a runbook for
  classic approve/deny.
- You don't need item-level breakdown or external item callbacks.

For new gates, the team's direction is checklist mode. Policy mode stays
fully supported for backward compatibility.

## Fail path: `on_checklist_fail` in checklist mode

The action's `on_checklist_fail` (surfaced on the run read as
`action_config.on_checklist_fail`; default `pending`) decides what a
resolved-`fail` run does to the approval request. It is the only field
checklist mode reads for this — `on_policy_fail` / `on_policy_success` are
policy-mode only and have no effect here:

| `on_checklist_fail` | Effect of a failed run |
|---|---|
| `deny` | Request lands `auto_denied` — terminal. `POST …/checklist/ask-for-manual` is rejected with `NO_MANUAL_FALLBACK`. |
| `pending` (default) | Request stays `pending` in a **resumable fail**. No notification fires. The requester (human or agent) picks the next move: fix the failed gates and redeploy (cancel + retry — the cheap, intended path), cancel, or `POST …/checklist/ask-for-manual` to hand it to classic review — which relabels `outcome_reason` to `requested_manual_review`, flips the front to the classic boolean approval, and notifies reviewers. |
| `manual` | A failed run skips the resumable step and goes STRAIGHT to classic review — `outcome_reason` is relabeled `requested_manual_review` and reviewers are notified immediately. |

Set with `POST/PATCH /approval/action` body `{"on_checklist_fail": "deny"|"pending"|"manual"}`.
Choose `manual` for gates where the requester can never self-serve the fix
(e.g. "deploys only from the CI api key"); keep the `pending` default for
educational gates an agent can satisfy by fixing the code and redeploying;
reserve `deny` for checklists that should never involve a human at all.

Success is NOT symmetric: a clean pass always lands `auto_approved`
regardless of `on_policy_success` (the human-in-the-loop is modeled as
manual checklist items; there is no reply flow to lift a pending checklist
approval). Deployments still require the explicit execute ("Start
deployment") after approval.

Design intent for the resumable fail: checklists are also *educational*
gates. An agent that deployed can read each failed gate's `query` (the
expected condition), compare it against `context_snapshot`, fix the code
or metadata, and redeploy — auto-escalating to humans on every fail would
turn a teaching gate into a tollbooth.
