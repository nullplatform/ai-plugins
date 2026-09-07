# Migration: Policy Mode → Checklist Mode

Switching an existing policy-driven approval action to a checklist-driven
one. This is a transactional operation that:

1. Generates a derived `ChecklistSpecification` from the action's current
   policies (one `condition` item per policy predicate — the policy's
   mongo condition is copied 1:1 into the item's `query`).
   **The copy is verbatim: no path rewriting.** Checklist conditions
   address the context catalog exactly the way policies do, so the
   predicate that worked as a policy works unchanged as a condition. (This
   was not always true — conditions used to be evaluated under a
   `{ context: … }` wrapper the converter knew nothing about, so every
   migrated query resolved nothing and every gate failed. If you are
   reading a migrated specification written before that was fixed, its
   queries are fine; it was the evaluation root that was wrong.)
2. Soft-deletes the existing `approval_action_policy` rows (sets
   `deleted_at = NOW()` — preserved for rollback).
3. Sets `approval_action.checklist_specification_id` to the new
   specification.

Everything in step 2-3 runs in a single DB transaction.

The wire flow is `POST /approval/checklist/migrate_from_policy/preview`
followed by `…/apply` (body `expected_specification`) — `migrate_action.sh`
wraps both. (The hyphenated `migrate-from-policy` path remains in the API
as a deprecated alias — you may still see it in older logs.)

## Dry-run first

Always preview the generated specification before applying:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
  --action-id 1842 \
  --dry-run
```

This calls `POST /approval/checklist/migrate_from_policy/preview` with
body `{"approval_action_id": 1842}`. Response:

```jsonc
{
  "policies": [ /* the action's current live policies, verbatim */ ],
  "generated_specification": {
    "name": "Auto-migrated: scope:deploy",
    "description": "...",
    "definition": {
      "items": [
        {
          "id": "build_metadata_coverage",
          "type": "condition",
          "behavior": "gate",
          "query": { "build.metadata.coverage": { "$gt": 80 } }
        },
        ...
      ]
    },
    "metadata": { /* migration provenance: action, policies, fingerprint */ }
  },
  "diff": {
    "items_added": ["build_metadata_coverage", "build_metadata_snyk_high", ...],
    "warnings": [
      "Item id derived from path 'build.metadata.security.scans.dependency_audit.critical' was truncated because the path exceeds 40 characters; review the generated id.",
      "Policy 3 (Webhook gate) has empty conditions — no items generated for this policy."
    ]
  }
}
```

(`derived_expression` is not part of the preview — the server computes it
at apply time, when the specification row is created. During the rename
transition the preview also mirrors the legacy `generated_template` key —
same value.)

**Read `diff.warnings` carefully, and know what the converter does NOT
do.** Every generated item is a `condition` with `behavior: gate` — the
converter only carries mongo predicates; it never emits `manual` or
`external` items. A policy that encoded human review or a webhook does
not survive as an equivalent step: re-author it as a `manual` /
`external` item via `update_specification.sh` after applying, or that
step silently disappears from the gate.

Warnings flag: an action with no policies (the specification would
vacuously approve — review before applying), policies with empty
conditions (no item generated), item ids truncated at 40 characters,
nested `$or`/`$and`/`$nor` operators translated as-is, and multiple
policies declaring the same key (each gets its own suffixed item).

**Generated item ids** are slugified from the policy's top-level condition
key. Keys the aggregation grammar reserves (`and`, `or`, `not`, `true`,
`false`) get an `item_` prefix — a policy shaped `{"$or": [...]}` becomes
the item `item_or`, not `or`, because `or.passed` could never be parsed.
Long paths are truncated at 40 characters and collisions get a `_2`, `_3`
suffix, so read `diff.items_added` in the preview response — the generated
ids, in order — before applying.

## Apply

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh --action-id 1842
```

The script previews again and POSTs `…/migrate_from_policy/apply` with
`{"approval_action_id": 1842, "expected_specification": <the generated
specification>}` — the API's optimistic-concurrency check: if the
action's policies changed between preview and apply, the server rejects
with `409` instead of migrating something you never reviewed. The new
specification's `created_by` is credited to the caller's JWT.

Response (success):

```jsonc
{
  "approval_action_id": 1842,
  "checklist_specification_id": "spec_xxx",
  "applied_at": "2026-08-07T15:04:05.000Z"
}
```

Post-conditions:
- The action is now in checklist mode (next `ApprovalRequest` against it
  creates a `ChecklistRun`).
- The previous policies are still in the DB with `deleted_at` set —
  recoverable.
- The new specification is `active` and `version: 1` — bump via
  `update_specification.sh` once you add the `manual` / `external` items
  the policies couldn't express (the converter emits condition gates
  only).

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

Calls `POST /approval/checklist/migrate_from_policy/rollback` with
`{"approval_action_id": 1842, "force": false}`. What it does:
1. Restores the soft-deleted `approval_action_policy` rows (`deleted_at = NULL`).
2. Clears `approval_action.checklist_specification_id`.
3. Soft-deletes the auto-migrated specification (`status = deleted`).

Response: `{approval_action_id, rolled_back_at, forced}`.

**Refused** (`409`) when: the action has no migrated specification to
roll back (`NOTHING_TO_ROLLBACK`), the current specification was not
created by a migration (`NOT_AUTO_MIGRATED`), or the specification was
edited after the migration (`FINGERPRINT_MISMATCH` — pass `--force` to
override, discarding the hand edits).

The server does **not** check for in-progress checklist runs before
rolling back. Runs already in flight keep evaluating their
`specification_snapshot`, but the action flips back to policy mode for
new requests immediately — check `list_runs.sh` and time the rollback
yourself.

## Bulk migration

Not currently supported in a single call. Loop the script:

```bash
for id in 1842 1843 1844; do
  ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh \
    --action-id $id --dry-run > /tmp/migrate-$id.json
done
# Review all dry-runs together, then:
for id in 1842 1843 1844; do
  ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/migrate_action.sh --action-id $id
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
- **Review the preview's `diff.warnings`** — and remember the converter
  emits condition gates only: policies that encoded human review or
  webhooks must be re-authored as `manual`/`external` items after
  applying, or those steps are silently lost.
- **Schedule rollback windows narrow**. Once the team starts using the
  checklist features (manual approvals, overrides, history), rolling
  back loses that audit trail and surprises users.
