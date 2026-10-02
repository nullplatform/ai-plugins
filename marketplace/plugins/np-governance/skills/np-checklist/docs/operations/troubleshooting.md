# Troubleshooting

Common failure modes and how to diagnose them.

## Roles each script needs

| Script | Roles that cover it |
|---|---|
| `list_specifications.sh`, `get_specification.sh` | `secops`, `ops`, `admin`, `developer`, `member`, `troubleshooting` |
| `dry_run_specification.sh` | `secops`, `ops`, `admin`, `developer` |
| `create_specification.sh`, `update_specification.sh`, `delete_specification.sh` | `secops`, `ops`, `admin` |
| `set_action_specification.sh`, `remove_action_specification.sh` | `secops`, `ops`, `admin` |
| `list_runs.sh`, `get_run.sh`, `list_events.sh`, `list_item_logs.sh` | `secops`, `ops`, `admin`, `developer`, `member`, `troubleshooting` |
| `manual_approve_item.sh` | the team that owns the run's NRN — typically `developer`, `ops`, `secops` |
| `migrate_action.sh`, `rollback_migration.sh` | `secops`, `ops`, `admin` |

If a script returns `403`, the caller doesn't have the right role on the
target NRN. See `docs/concepts/permissions.md` for the full mapping and
the diagnostic flow. Verify the effective role with
`${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh`.

## Failure decoder

| What you see | Likely cause | Where to look |
|---|---|---|
| `Error: <METHOD> method is only allowed for endpoints matching: ...` on any write script (`create_specification.sh`, `set_action_specification.sh`, `manual_approve_item.sh`, ...) | The installed copy of the `np-api` skill is outdated — its `ALLOWED_MODIFY` allowlist in `fetch_np_api_url.sh` predates the `approval/checklist/specification` paths, the snake_case `approval/checklist/migrate_from_policy/*` paths (`migrate_action.sh` / `rollback_migration.sh` fail even when the specification paths are present), or the older `approval/*` checklist paths entirely — so the wrapper rejects the request before any network call | Update/reinstall the `np-api` skill (version ≥ the one that allowlists the `approval/checklist/specification`, `approval/dry-run` and `approval/checklist/migrate_from_policy/*` paths). Read scripts (GET) are unaffected |
| `409 APPROVAL_ACTION_HAS_POLICIES_XOR` on `set_action_specification` | Action still has live policies | Use `migrate_action.sh --dry-run` to preview the safe path |
| `404 CHECKLIST_SPECIFICATION.NOT_FOUND` after creation | Specification was soft-deleted or id typo | `list_specifications.sh --nrn <nrn> --status deleted` to confirm |
| `400 CHECKLIST_SPECIFICATION.INVALID_ID` on `list_specifications.sh` ("The checklist specification ID is not valid") | Misleading error: the list route requires the `nrn` query param and reuses this error code when it's missing — no specification id is involved | Pass `--nrn` |
| Run stuck in `pending_items` for too long | An `external` item never received its callback | `list_item_logs.sh --item-id <id> --level info` to see dispatch + retries |
| `condition` item with `status: failed` and `details.reason: "exception"` | Query evaluation threw (missing context key, bad type, invalid operator) | Compare `details.error` against `context_snapshot` — fix the query or the upstream context |
| `422 condition.expression.removed` / `condition.evaluator.removed` / `condition.mode.removed` on specification create/update | Definition uses the removed expression dialect | Rewrite the item as a mongo-like `query` object (see `docs/concepts/item-types.md`) |
| `422 condition.query.required` / `condition.query.type` | A `condition` item is missing `query`, or `query` is not a non-empty object | Add a mongo-like `query` object to the item |
| `422 condition.query.context_rooted_path` / `item.applies_when.context_rooted_path` | The definition addresses fields under `context.` — the old root. Conditions now evaluate against the bare context catalog, exactly like approval policies | Drop the leading `context.` from field paths (the error message names the corrected path), recursing into `$and` / `$or` / `$nor` branches. Leave operator keys, values, `$elemMatch` sub-paths and `external.inputs` `{{ context.* }}` placeholders alone — see `docs/concepts/item-types.md` |
| `422 item.id.reserved` | An item id is `and`, `or`, `not`, `true` or `false` — reserved by the aggregation grammar | Rename the item (e.g. `item_or`). Migrated specifications get this prefix automatically |
| `422 execution_trigger.invalid` on specification create/update | `definition.execution_trigger` is not `explicit`, `automatic_approval` or `any_approval` (a typo, a boolean, an empty string) | Fix the value, or drop the key to get `explicit` — see `docs/operations/specifications-crud.md` |
| Run resolves to `fail` with `outcome_reason` / message mentioning `aggregation_parse_error` | The derived expression doesn't parse — almost always an item id colliding with a reserved word on a specification saved before that guard existed | `get_specification.sh --id <spec_xxx\|tmpl_xxx> \| jq '.derived_expression'`, rename the offending item, re-save |
| Every `gate` fails on every request, and `details.query` looks reasonable | The definition still carries `context.`-rooted paths — persisted specifications were rewritten by the deploy's data migration, but one restored from an old export or hand-copied can still have them | Compare `details.query`'s paths against the keys of `context_snapshot`: they must line up with no `context.` root. Re-saving the specification surfaces a validation error naming each bad path |
| Run resolved as `fail` but you expected `approve_with_override` | No override item was approved (only "exists" doesn't help) | `get_run.sh` → check `item_states["<override id>"].status` |
| Run resolved `approve` (request `auto_approved`) or the request is `approved`, but `execution_status` stays `pending` and the action did not start | Nothing is broken: this approval does not start the action on its own | `get_run.sh \| jq .execution` → `on_approval: wait` and why: `trigger: explicit` (the default — start it with `POST /approval/{id}/execute`), `automatic_approval` with `automatic_run: false` (a person or an external system took part: the table in `docs/concepts/modes.md` says which), a deployment inside a deployment group (the group's approval starts it) or an approval with no callback to run |
| `409 CHECKLIST_RUN.ALREADY_RESOLVED` on `manual_approve_item` | Someone else (or the engine) already resolved the run | `list_events.sh` to see who/when |
| Multiple checklist_event rows with same `sequence_number` | impossible (UNIQUE constraint) — if you see it, it's a UI bug | report it; the DB enforces uniqueness |

## Diagnose a "stuck" run

```bash
# 1. Current state
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
  | jq '{aggregate_status, items: (.item_states | to_entries | map({id: .key, status: .value.status}))}'

# 2. Find pending items
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
  | jq '.item_states | to_entries | map(select(.value.status == "pending")) | .[].key'

# 3. For each pending external item, check its logs
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_item_logs.sh \
  --approval-id 99421 \
  --item-id <pending_external_item>

# 4. Recent events on the run
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_events.sh \
  --approval-id 99421 \
  --limit 25
```

## Diagnose "specification behaviour changed unexpectedly"

If a recently-edited specification seems to be behaving differently from
what you'd expect:

1. Remember that **in-flight runs use the snapshot, not the live
   specification**. The specification you just edited won't affect runs
   that started before the edit.
2. Compare the live specification's `definition` against the run's
   `specification_snapshot`:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_specification.sh --id spec_xxx \
     | jq '.definition'
   ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
     | jq '.specification_snapshot.definition'
   ```
3. Dry-run the action against the run's context_snapshot (the dry-run
   resolves the action's *current* specification):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_run.sh --approval-id 99421 \
     | jq '.context_snapshot' > /tmp/ctx.json
   ${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/dry_run_specification.sh \
     --nrn "<the action's nrn>" \
     --action "<the action, e.g. deployment:create>" \
     --context-file /tmp/ctx.json
   ```
   This shows what the new specification *would* have decided for the same
   context — handy for explaining the divergence to the team.

## Performance: large `specification_snapshot` / `context_snapshot`

The snapshots can grow into hundreds of KB for specifications with many
external items and rich upstream context. `get_run.sh` returns them
inline. For high-traffic listings prefer `list_runs.sh`, which returns
only the summary (`checklist` object); fetch the full run only when
needed.

For analytics / reporting, prefer `np-lake` over many sequential API
calls.
