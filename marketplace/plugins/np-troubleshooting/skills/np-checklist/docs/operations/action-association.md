# Action ↔ Template Association

How to wire a `ChecklistTemplate` to an `ApprovalAction`.

## Set (associate)

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/set_action_template.sh \
  --action-id 1842 \
  --template-id tmpl_abc123def456ghi789jk
```

Response (on success, `200 OK`):

```jsonc
{
  "id": "1842",
  "nrn": "organization=1::account=2::namespace=3",
  "entity": "scope",
  "action": "scope:deploy",
  "checklist_template_id": "tmpl_abc123def456ghi789jk"
}
```

### What happens server-side

1. Loads the action by id (404 if not found).
2. Counts live (`deleted_at IS NULL`) `approval_action_policy` rows linked
   to it. **If any exist, fails with `409` (`APPROVAL_ACTION_HAS_POLICIES_XOR`).**
3. Loads the template (404 if not found or `deleted`).
4. Sets `approval_action.checklist_template_id = templateId` and returns
   the updated action.

### Common failure modes

| HTTP | Code | Meaning | Fix |
|---|---|---|---|
| `400` | `APPROVAL_ACTION.INVALID_ID` | `action-id` missing or malformed | check the action id |
| `400` | `CHECKLIST_TEMPLATE.INVALID_ID` | `template-id` not a `tmpl_…` string | check the template id |
| `404` | `APPROVAL_ACTION.NOT_FOUND` | no action with that id | confirm id with `/action/:id` |
| `404` | `CHECKLIST_TEMPLATE.NOT_FOUND` | template missing or soft-deleted | confirm with `get_template.sh` |
| `409` | `APPROVAL_ACTION_HAS_POLICIES_XOR` | action has live policies | use `migrate_action.sh` instead |

## Remove (dissociate)

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/remove_action_template.sh --action-id 1842
```

Idempotent: returns the action unchanged if no template was set.

Use cases:
- Turning off checklist mode on an action without restoring policies (the
  action becomes "unguarded" — typically not what you want, but useful
  during testing).
- Preparing to associate a different template (call `remove` then `set`).

If you're switching back to policy mode and want the previous policies
restored, use `rollback_migration.sh` instead — `remove` only undoes the
association, not the policy archive from a previous migration.

## Switching templates on a running action

`set_action_template` overwrites the existing association silently —
including replacing one template with another. This is safe because:

- **In-flight runs are unaffected** — they hold `template_snapshot` and
  evaluate against that.
- **New runs use the new template** from this point on.

If you need a clean cutover (e.g. "starting Monday, use template B"),
just `set_action_template` ahead of time and the next triggered
request picks it up.

## Listing actions that use a given template

The approval-api does not currently expose a "list actions by template_id"
endpoint. Two workarounds:

- Query the lake with `np-lake`:
  ```sql
  SELECT id, nrn, entity, action
  FROM approval_action
  WHERE checklist_template_id = 'tmpl_xxx';
  ```
- List actions and filter client-side with `jq`:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh \
    "/approval/action?nrn=organization=1" \
    | jq '.results[] | select(.checklist_template_id == "tmpl_xxx")'
  ```
