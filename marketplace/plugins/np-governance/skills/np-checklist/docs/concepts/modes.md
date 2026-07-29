# Policy Mode vs Checklist Mode

The approval-api supports two evaluation modes for an `ApprovalAction`:

| Mode | Configured via | Evaluated by | UI |
|---|---|---|---|
| **Policy** (legacy, default) | `approval_action_policy` rows linking to one or more `policy` records | The policy engine on each `ApprovalRequest`, against `policy_context` | Classic approve/deny modal |
| **Checklist** | `approval_action.checklist_template_id` pointing to a `checklist_template` | The checklist run engine — items evaluated, aggregated into a final outcome | Runner UI (per-item status, manual approvals, events) |

The two modes differ in orchestration, not in how a condition is written:
a checklist `condition` item and a policy predicate use the same
mongo-like query language over the same context catalog, **addressed the
same way** (`build.metadata.coverage` in both — no `context.` prefix in
either). That is what lets `migrate_action.sh` carry a predicate across
verbatim.

## XOR rule

An action is **either policy-driven OR checklist-driven, never both**.

- `POST /action/:id/checklist_template` fails with `409
  APPROVAL_ACTION_HAS_POLICIES_XOR` if any live (`deleted_at IS NULL`)
  policy is still associated with the action.
- The recommended path to switch an existing policy-action to checklist is
  `POST /migration/:action_id`, which performs the swap (soft-delete
  policies + associate template + create derived expression) inside a
  single transaction.
- `POST /migration/:action_id/rollback` reverses the swap.

## How the backend decides which path to take

When an `ApprovalRequest` is created, the backend looks at the resolved
`ApprovalAction`:

```
if approvalAction.checklistTemplateId is set:
    → create a ChecklistRun (snapshots template + context)
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

- The "Checklist Templates" admin pages (list, new, edit, detail).
- The "Migrate to checklist" wizard.

When `false`, the admin UI for templates is hidden; users do not see
checklist-mode workflows in the UI. However:

- **The backend is agnostic to the flag.** Endpoints in this skill work
  regardless of the flag's state — useful for platform teams who want to
  prepare templates ahead of a rollout, or for API consumers (BFFs, CLIs,
  external tools) that bypass the UI.
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
