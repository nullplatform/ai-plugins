# Specifications CRUD

The five specification lifecycle scripts. All endpoints are scoped by NRN —
the platform-team that owns the NRN owns the specifications inside it.

## List

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_specifications.sh \
  --nrn "organization=1::account=2" \
  --status active \
  --limit 25
```

Response:

```jsonc
{
  "results": [
    {
      "id": "spec_xxx",
      "nrn": "organization=1::account=2",
      "name": "prod-deploy-gate",
      "version": 3,
      "status": "active",
      "created_by": "alice@acme.com",
      "created_at": "2026-04-30T12:01:00Z",
      "updated_at": "2026-05-10T09:18:00Z"
    },
    ...
  ],
  "total": 12,
  "offset": 0,
  "limit": 25
}
```

`--nrn` is **required** — the list route rejects the call without it
(`400`, confusingly labeled `CHECKLIST_SPECIFICATION.INVALID_ID`).
`--name` is a substring match (the wire param is `name:contains`; the API
has no exact-name filter).

Specifications created before the mid-2026 rename keep their `tmpl_`-prefixed
ids; new ones get `spec_`. Both coexist in listings — ids are opaque.

The `definition` is not returned in list mode — fetch via `get_specification`
when you need the items.

## Get

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_specification.sh --id spec_xxx
```

Returns the full record including `definition` and `derived_expression`.

## Create

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_specification.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "prod-deploy-gate" \
  --definition-file ./prod-deploy-gate.yaml \
  --created-by "alice@acme.com" \
  --description "Coverage + Snyk + security sign-off; CAB override."
```

- `--definition-file` accepts YAML (`.yaml`/`.yml`) or JSON (`.json`).
- The server assigns the `id` (`spec_<nanoid16>`).
- Initial `version` defaults to `1` (override with `--version` if you're
  importing a numbered specification from elsewhere).
- The server computes `derived_expression` from the items' `behavior`s.
- UNIQUE `(nrn, name, version)` — re-creating with the same triple fails
  with `409`.

### Defining the items

See `docs/concepts/item-types.md` for the full reference. The minimum
viable specification is:

```yaml
items:
  - id: my_check
    type: condition
    behavior: gate
    query:
      "build.metadata.tests_status": { "$eq": "passed" }
```

Condition items take a mongo-like `query` object (non-empty, required).
The legacy `evaluator` / `mode` / `expression` fields are rejected by the
validator with `condition.*.removed` errors.

### Choosing what starts the approved action

`execution_trigger` is a key of the `definition`, next to `items` (not an
item field):

```yaml
execution_trigger: automatic_approval   # explicit (default) | automatic_approval | any_approval
items:
  - id: my_check
    type: condition
    behavior: gate
    query:
      "build.metadata.tests_status": { "$eq": "passed" }
```

Without it the definition reads `explicit`: an approved request waits for
someone to start it (Start deployment, or `POST /approval/{id}/execute`).
`automatic_approval` starts it on its own when no person or external system
took part in the run; `any_approval`, on any approval. The full rule is in
`docs/concepts/modes.md` ("Success path").

### What the validator rejects

Three things the validator will bounce a definition for, each of which
would otherwise fail silently at run time:

- **`context.`-rooted field paths** in `query` or `applies_when`
  (`condition.query.context_rooted_path` /
  `item.applies_when.context_rooted_path`). Paths address the context
  catalog directly, the same way approval policies address it —
  `build.metadata.tests_status`, not
  `context.build.metadata.tests_status`.
- **An item id equal to `and`, `or`, `not`, `true` or `false`**
  (`item.id.reserved`) — the aggregation grammar reserves those words.
- **An `execution_trigger` outside `explicit`, `automatic_approval` and
  `any_approval`** (`execution_trigger.invalid`, path
  `definition.execution_trigger`) — a typo would otherwise never start
  anything. Absent and `null` pass and read `explicit`.

All three come back as `422 VALIDATION_FAILED`, on create and on update.

See `docs/concepts/item-types.md` for the full addressing rules (including
how to rewrite an old `context.`-rooted definition) and the reserved-id
rationale.

## Update

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/update_specification.sh \
  --id spec_xxx \
  --description "Updated copy"
```

Partial — only provided fields are updated. Mutable fields:

- `--name`
- `--description`
- `--definition-file` — re-emits items + recomputes `derived_expression`.

There is **no `--status`**: the PATCH endpoint ignores a `status` field
(the call returns `200` but changes nothing). To soft-delete, use
`delete_specification.sh`; there is no way to flip a specification to
`inactive` via update.

Every successful update creates a **new row**: a new `spec_` id with
`version = max(version) + 1` for the `(nrn, name)` lineage. The previous
row stays untouched — including the action association, which keeps
pointing at the OLD id. Always re-run `set_action_specification.sh` with
the returned id. Existing runs are unaffected either way, because they
evaluate `specification_snapshot`.

If you change item ids in a definition update, existing runs that
reference those ids in `item_states` keep them — but new runs from this
specification forward use the new ids. Avoid renaming ids when possible.

## Delete

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/delete_specification.sh --id spec_xxx
```

Soft delete (`status = deleted`). The specification is hidden from listings
by default. Existing checklist runs remain unaffected because they hold
a `specification_snapshot`. The `set_action_specification` endpoint refuses
to associate deleted specifications.

## Authoring a specification from scratch (typical flow)

1. Draft items in YAML.
2. `create_specification.sh` with the YAML.
3. `set_action_specification.sh` to wire it to a new action — or
   `migrate_action.sh` to swap it onto an existing policy-action.
4. `dry_run_specification.sh` against the action with a sample context to
   preview which items would pass / fail (dry-run resolves the
   specification through the action association, so it comes after step 3).
5. Trigger an approval-request through the upstream flow and inspect the
   run with `get_run.sh` to verify behaviour end-to-end.
