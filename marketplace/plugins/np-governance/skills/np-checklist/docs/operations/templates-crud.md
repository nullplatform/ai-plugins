# Templates CRUD

The five template lifecycle scripts. All endpoints are scoped by NRN —
the platform-team that owns the NRN owns the templates inside it.

## List

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/list_templates.sh \
  --nrn "organization=1::account=2" \
  --status active \
  --limit 25
```

Response:

```jsonc
{
  "results": [
    {
      "id": "tmpl_xxx",
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

The `definition` is not returned in list mode — fetch via `get_template`
when you need the items.

## Get

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/get_template.sh --id tmpl_xxx
```

Returns the full record including `definition` and `derived_expression`.

## Create

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/create_template.sh \
  --nrn "organization=1::account=2::namespace=3" \
  --name "prod-deploy-gate" \
  --definition-file ./prod-deploy-gate.yaml \
  --created-by "alice@acme.com" \
  --description "Coverage + Snyk + security sign-off; CAB override."
```

- `--definition-file` accepts YAML (`.yaml`/`.yml`) or JSON (`.json`).
- The server assigns the `id` (`tmpl_<nanoid21>`).
- Initial `version` defaults to `1` (override with `--version` if you're
  importing a numbered template from elsewhere).
- The server computes `derived_expression` from the items' `behavior`s.
- UNIQUE `(nrn, name, version)` — re-creating with the same triple fails
  with `409`.

### Defining the items

See `docs/concepts/item-types.md` for the full reference. The minimum
viable template is:

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

Two things the validator will bounce a definition for, both of which used
to fail silently at run time instead:

- **`context.`-rooted field paths** in `query` or `applies_when`
  (`condition.query.context_rooted_path` /
  `item.applies_when.context_rooted_path`). Paths address the context
  catalog directly, the same way approval policies address it —
  `build.metadata.tests_status`, not
  `context.build.metadata.tests_status`.
- **An item id equal to `and`, `or`, `not`, `true` or `false`**
  (`item.id.reserved`) — the aggregation grammar reserves those words.

See `docs/concepts/item-types.md` for the full addressing rules (including
how to rewrite an old `context.`-rooted definition) and the reserved-id
rationale.

## Update

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/update_template.sh \
  --id tmpl_xxx \
  --description "Updated copy"
```

Partial — only provided fields are updated. Mutable fields:

- `--name`
- `--description`
- `--status` (`active` / `inactive`; for `deleted` use `delete_template.sh`)
- `--definition-file` — re-emits items + recomputes `derived_expression`.
  Typically bumps `version` (confirm against the API contract); existing
  runs are unaffected because they use `template_snapshot`.

If you change item ids in a definition update, existing runs that
reference those ids in `item_states` keep them — but new runs from this
template forward use the new ids. Avoid renaming ids when possible.

## Delete

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-checklist/scripts/delete_template.sh --id tmpl_xxx
```

Soft delete (`status = deleted`). The template is hidden from listings
by default. Existing checklist runs remain unaffected because they hold
a `template_snapshot`. The `set_action_template` endpoint refuses to
associate deleted templates.

## Authoring a template from scratch (typical flow)

1. Draft items in YAML.
2. `dry_run_template.sh` against a sample context to preview which items
   would pass / fail.
3. `create_template.sh` with the YAML.
4. `set_action_template.sh` to wire it to a new action — or
   `migrate_action.sh` to swap it onto an existing policy-action.
5. Trigger an approval-request through the upstream flow and inspect the
   run with `get_run.sh` to verify behaviour end-to-end.
