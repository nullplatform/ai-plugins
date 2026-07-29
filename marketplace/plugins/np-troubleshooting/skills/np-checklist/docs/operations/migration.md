# Migration: Policy Mode → Checklist Mode

Switching an existing policy-driven approval action to a checklist-driven
one. This is a transactional operation that:

1. Generates a derived `ChecklistTemplate` from the action's current
   policies (one `condition` item per policy predicate — the policy's
   mongo condition is copied 1:1 into the item's `query`).
   **The copy is verbatim: no path rewriting.** Checklist conditions
   address the context catalog exactly the way policies do, so the
   predicate that worked as a policy works unchanged as a condition. (This
   was not always true — conditions used to be evaluated under a
   `{ context: … }` wrapper the converter knew nothing about, so every
   migrated query resolved nothing and every gate failed. If you are
   reading a migrated template written before that was fixed, its queries
   are fine; it was the evaluation root that was wrong.)
2. Soft-deletes the existing `approval_action_policy` rows (sets
   `deleted_at = NOW()` — preserved for rollback).
3. Sets `approval_action.checklist_template_id` to the new template.

Everything in step 2-3 runs in a single DB transaction.

## Dry-run first

Always preview the generated template before applying:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --dry-run
```

Response:

```jsonc
{
  "dry_run": true,
  "action_id": 1842,
  "current_policies": [
    {
      "id": 5511,
      "policy_id": 84,
      "name": "Coverage > 80",
      "predicate": { "build.metadata.coverage": { "$gt": 80 } },
      "would_become_item": "coverage_gate_80"
    },
    ...
  ],
  "generated_template": {
    "name": "migrated-from-action-1842",
    "version": 1,
    "definition": {
      "items": [
        {
          "id": "coverage_gate_80",
          "type": "condition",
          "behavior": "gate",
          "query": { "build.metadata.coverage": { "$gt": 80 } }
        },
        ...
      ]
    },
    "derived_expression": "coverage_gate_80.passed AND snyk_zero_high.passed AND ..."
  },
  "warnings": [
    "policy 'manual approver' has no automatic equivalent; will be emitted as a `manual` item",
    "policy 'webhook hook' will be emitted as an `external` item but the webhook URL must be reviewed"
  ]
}
```

**Read the warnings carefully.** Policies that don't translate cleanly
(human approval policies, webhook policies) become items that need
review — typically:

- `manual` items get a generated `title` from the policy name; edit
  later via `update_template.sh` to refine.
- `external` items get the policy's `webhook` URL but **no inputs / no
  timeout** — author needs to fill them in. Until then the item will
  fire as-is on the first run.

**Generated item ids** are slugified from the policy's top-level condition
key. Keys the aggregation grammar reserves (`and`, `or`, `not`, `true`,
`false`) get an `item_` prefix — a policy shaped `{"$or": [...]}` becomes
the item `item_or`, not `or`, because `or.passed` could never be parsed.
Long paths are truncated at 40 characters and collisions get a `_2`, `_3`
suffix, so read `diff.items_added` in the preview response — the generated
ids, in order — before applying.

## Apply

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --created-by "platform-team@acme.com"
```

Response (success):

```jsonc
{
  "action_id": 1842,
  "template_id": "tmpl_xxx",
  "template_version": 1,
  "policies_archived": 4,
  "warnings": [ ... ]
}
```

Post-conditions:
- The action is now in checklist mode (next `ApprovalRequest` against it
  creates a `ChecklistRun`).
- The previous policies are still in the DB with `deleted_at` set —
  recoverable.
- The new template is `active` and `version: 1` — bump via
  `update_template.sh` once you refine `manual` / `external` items.

## What happens to in-flight requests

`ApprovalRequest` rows created **before** the migration:
- Already have `mode = 'policy'` (or `NULL` for legacy) set at creation
  time.
- Continue to evaluate against policies (which the service reads using
  `withDeleted` scope when the request was created before the cutover).
- The classic UI keeps showing them.

Requests created **after** the migration:
- Have `mode = 'checklist'`.
- Get a `ChecklistRun`.
- Show the new runner UI.

There is no in-flight migration — only new requests after the cutover
take the new path.

## Rollback

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/rollback_migration.sh --action-id 1842
```

What it does:
1. Restores the soft-deleted `approval_action_policy` rows (`deleted_at = NULL`).
2. Clears `approval_action.checklist_template_id`.
3. Leaves the migrated template alive but `status = inactive` (you can
   delete it manually if you don't want to keep it around).

**Refused** (`409`) if any `ChecklistRun` for this action is still
in-progress (not in a `resolved` / terminal state). Either wait for the
runs to resolve, cancel them upstream, or `rollback` after they're done.

## Bulk migration

Not currently supported in a single call. Loop the script:

```bash
for id in 1842 1843 1844; do
  ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
    --action-id $id --dry-run > /tmp/migrate-$id.json
done
# Review all dry-runs together, then:
for id in 1842 1843 1844; do
  ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
    --action-id $id --created-by "platform-team@acme.com"
done
```

For large fleets (many actions across many NRNs), prefer a controlled
rollout: pick a sample namespace first, watch the first checklist runs,
then expand.

## Pitfalls

- **Don't migrate during a critical deploy window**. The cutover is
  atomic, but the *new* requests will behave differently (checklist UI,
  different audit shape). Communicate with the team that consumes the
  action.
- **Review the dry-run's `warnings`** — every warning is a generated
  item that probably needs human-authored detail.
- **Schedule rollback windows narrow**. Once the team starts using the
  checklist features (manual approvals, overrides, history), rolling
  back loses that audit trail and surprises users.
