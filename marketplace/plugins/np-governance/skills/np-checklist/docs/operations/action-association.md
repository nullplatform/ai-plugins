# Action ↔ Specification Association

How to wire a `ChecklistSpecification` to an `ApprovalAction`.

## Set (associate)

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_specification.sh \
  --action-id 1842 \
  --specification-id spec_a1b2c3d4e5f6g7h8
```

The wire call is `POST /approval/action/:action_id/checklist_specification`
with body `{"checklist_specification_id": "..."}`. Response (on success,
`200 OK`):

```jsonc
{
  "id": "1842",
  "nrn": "organization=1::account=2::namespace=3",
  "entity": "scope",
  "action": "scope:deploy",
  "checklist_specification_id": "spec_a1b2c3d4e5f6g7h8"
}
```

(During the rename transition the response also mirrors the legacy
`checklist_template_id` key — same value.)

### What happens server-side

1. Loads the action by id (404 if not found).
2. Counts live (`deleted_at IS NULL`) `approval_action_policy` rows linked
   to it. **If any exist, fails with `409` (`APPROVAL_ACTION_HAS_POLICIES_XOR`).**
3. Loads the specification (404 if not found or `deleted`).
4. Sets `approval_action.checklist_specification_id = specificationId` and
   returns the updated action.

### Common failure modes

| HTTP | Code | Meaning | Fix |
|---|---|---|---|
| `400` | `APPROVAL_ACTION.INVALID_ID` | `action-id` missing or malformed | check the action id |
| `400` | `CHECKLIST_SPECIFICATION.INVALID_ID` | `specification-id` not a valid id | check the specification id (`spec_…`, or `tmpl_…` for pre-rename ones) |
| `404` | `APPROVAL_ACTION.NOT_FOUND` | no action with that id | confirm id with `/action/:id` |
| `404` | `CHECKLIST_SPECIFICATION.NOT_FOUND` | specification missing or soft-deleted | confirm with `get_specification.sh` |
| `409` | `APPROVAL_ACTION_HAS_POLICIES_XOR` | action has live policies | use `migrate_action.sh` instead |

## Remove (dissociate)

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/remove_action_specification.sh --action-id 1842
```

Idempotent: returns the action unchanged if no specification was set.

Use cases:
- Turning off checklist mode on an action without restoring policies (the
  action becomes "unguarded" — typically not what you want, but useful
  during testing).
- Preparing to associate a different specification (call `remove` then `set`).

If you're switching back to policy mode and want the previous policies
restored, use `rollback_migration.sh` instead — `remove` only undoes the
association, not the policy archive from a previous migration.

## Switching specifications on a running action

`set_action_specification` overwrites the existing association silently —
including replacing one specification with another. This is safe because:

- **In-flight runs are unaffected** — they hold `specification_snapshot`
  and evaluate against that.
- **New runs use the new specification** from this point on.

If you need a clean cutover (e.g. "starting Monday, use specification B"),
just `set_action_specification` ahead of time and the next triggered
request picks it up.

## Listing actions that use a given specification

The approval-api does not currently expose a "list actions by
specification id" endpoint. Two workarounds:

- Query the lake with `np-lake`. During the rename transition
  `approval_action` carries both columns and the **legacy one is
  authoritative** — the API's read path follows `checklist_template_id`
  unconditionally, even when it is NULL. Don't `COALESCE` to the
  canonical column: an action unlinked by pre-rename code has
  `checklist_template_id = NULL` with a stale
  `checklist_specification_id` left behind, so the fallback would
  resurrect a dead association. After Phase 4 drops the legacy column,
  switch the filter to `checklist_specification_id`:
  ```sql
  SELECT id, nrn, entity, action
  FROM approval_action
  WHERE checklist_template_id = 'spec_xxx';
  ```
- List actions and filter client-side with `jq`:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh \
    "/approval/action?nrn=organization=1" \
    | jq '.results[] | select(.checklist_specification_id == "spec_xxx")'
  ```
