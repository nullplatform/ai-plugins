# Inbox rules

An inbox rule says what triggers a notification, who receives it and what it says. nullplatform ships
**built-in** rules (approvals, action items, deployments, builds, scopes, service actions, expiring API keys);
an organization adds its own (**custom** rules). Each rule is also a row in every person's Inbox settings, under
the rule's `category`. The API path keeps the old wire names: a rule row is `{ id, organization_id, publisher,
status, document, created_at, updated_at }`, and the definition you write is the `document`.

All paths below are under `https://api.nullplatform.com`. Reads use `/np-api fetch-api "<path>"`; writes use
`${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method <M> --data @<file.json> "<path>"`
(see SKILL.md, "Every API call goes through np-api").

## List and read

```
/np-api fetch-api "/communications/inbox_rule"
/np-api fetch-api "/communications/inbox_rule/<id>"
```

`GET /communications/inbox_rule` answers `{ results: [...] }` with every built-in rule and the organization's
own (no pagination). How to read a row:

| Field | Meaning |
|-------|---------|
| `organization_id: null` | Built-in rule. Read-only for everyone (`403` on PUT/DELETE). `GET .../<id>` answers your organization's edit instead when there is one. |
| `organization_state.enabled` | Built-in only: `false` means the organization deactivated it, so nobody receives it. |
| `organization_state.linked` | Built-in only: the built-in rules that turn on and off together with this one. |
| `organization_state.customized` | Built-in only: the organization edited it. The edit is a second row with the same `id` and your `organization_id`; it runs instead of the built-in one. |
| `organization_state.replaced_by` | Built-in only (legacy): a custom rule `replaces` it and holds it off. |
| `status` | `active` or `deprecated` (deactivated). Only active rules fire. |
| `document.source` | What triggers it: `{ kind: invoked }` (your emission), a source name like `"deployment"` (status changes), or `{ kind: stale, ... }` (an entity stuck in a status). |
| `document.visible_to` | The one NRN the rule applies under. Absent means the organization root. |
| `document.category` | How it shows in Inbox settings: `label`, `group`, `default_mode` (`off`, `involved`, `all`), `configurable`, `allows_all`. |
| `document.audience[]` | One entry per reading (`as`): `who` (recipients), `content` (title/body templates), optional `fallback`. |

Summarize as a table: id, built-in/custom (and Edited), trigger, scope, default mode, state. When explaining one
rule, say in plain words when it fires (source + `when.conditions`), who each reading reaches, and what the
default mode means for people who never touched their settings.

## Write a rule

### Phase 1 — Discovery

Read what the definition can say before asking anything:

```
/np-api fetch-api "/communications/inbox_rule/schema"
/np-api fetch-api "/communications/inbox_rule/source"
```

- `/schema` answers `{ schema }`: the JSON Schema of a definition as an organization writes it, every property
  documented. It is the source of truth for field names and limits; read the parts you need from it rather
  than relying on memory.
- `/source` answers `{ results: [{ entity, kind, statuses, delivered_statuses, fields: [{ name, type }] }] }`. A
  rule riding an entity may only name statuses in `delivered_statuses` and read the `fields` listed.

Then ask with `AskUserQuestion` (one batch):

1. **Trigger**: an event from your own systems (invoked, Recommended for CI/workflows) / a nullplatform entity
   changing status (pick the source) / an entity stuck in a status (stale).
2. **Who receives it**: a user id sent in the data (`who.user`) / everyone who holds an action on the resource
   (`who.can`, e.g. `approval_request:approve`) / only people who chose Everything (no `who`).
3. **Default for people**: Involving me (`involved`, Recommended) / Everything (`all`) / Off (`off`).
4. **Scope**: the whole organization (Recommended) / one account, namespace or application (`visible_to`).

Ask in a second batch for the id, the label and one-line description, the severity, and (invoked) the data each
send will carry.

### Phase 2 — Draft the definition

Write it to a file (`inbox-rule-<id>.json`). Rules the service enforces on a custom rule:

- **`id`**: lowercase letters and underscores with exactly one dot, no digits (`acme.security_finding`;
  `acme.cve2026` is refused), at most 120 characters. It is also the category id in Inbox settings and cannot
  change. Not `platform.*`. Using a built-in rule's id **edits that
  built-in rule** for the organization instead of creating a new one (see "Built-in rules" below).
- **`source`**: `{ "kind": "invoked" }`, a source name from `/source`, or
  `{ "kind": "stale", "entity", "when_status", "after" (>= 15m), "within" (<= 168h) }`.
- **`context_schema`** (invoked): JSON Schema of the data sent with each emission. It **must require `id`**
  (emissions are idempotent by it). Allowed keywords only: `type`, `properties`, `required`, `enum`, `minLength`,
  `maxLength`, `minimum`, `maximum`, `items`, `writeOnly`, `description`, boolean `additionalProperties`. No
  `pattern`, `format`, `$ref`, `$id`, `if/then/else`.
- **`category`**: all six required — `group`, `label`, `description` (one line, at most 70 characters),
  `configurable`, `allows_all` (requires `configurable`), `default_mode` (`off`, `involved`, `all`).
  `default_mode` adds nobody: `all` does not make anyone a follower. Optional
  `channels: { email: { default_mode } }` sets what people already in the audience get **by email** when they
  never changed it (email is `off` unless the rule says otherwise).
- **`severity`**: `informational`, `maintenance`, `degraded` or `outage`.
- **`audience[]`**: at least one reading. `as` names it; `action` must equal the rule id or start with it
  (`acme.security_finding.unowned`); `content.title` (and optional `body`) are templates reading
  `${{ context.<field> }}`. Titles take inline Markdown (`**bold**`, `*italic*`, `` `code` ``); bodies also take
  links and lists. Optional `content.email` / `content.slack` override the copy per medium.
- **`who`**: `{ "user": "${{ context.owner_id }}" }` (or a list, first that renders wins), or
  `{ "can": "<action>" }`. No `who`: only followers (people with Everything on the resource or above).
  `fallback` (same fields) reaches someone else when `who` resolves nobody. `exclude_actor: true` skips whoever
  caused the event.
- **`visible_to`** (optional): exactly one NRN, like `["organization=1:account=2"]`. Emissions of the saved rule
  for resources outside it answer `404`; a draft emission answers `400` on `/nrn`.
- **`keys.dedupe` / `keys.group`** (optional): must start with `<id>:`. `keys.group` defaults to
  `<id>:<context.id>` and is the thread that a source's lifecycle closes.
- **`behaviors`** (optional): an array of single-key objects, one behavior per entry:
  `[{ "delay": { "for": "5m" } }]`, `[{ "batch": { "window", "key_by", "merge" } }]` (`key_by` must include
  `organization` and `recipient`), `only_if_announced`. Never two keys in one entry. A rule with `delay` or `batch`
  answers emissions with `202`.

Minimal invoked rule:

```json
{
  "id": "acme.security_finding",
  "source": { "kind": "invoked" },
  "context_schema": {
    "type": "object",
    "required": ["id", "service", "owner_id"],
    "properties": {
      "id": { "type": "string", "description": "The scanner finding ID" },
      "service": { "type": "string" },
      "summary": { "type": "string" },
      "owner_id": { "type": "integer", "description": "The nullplatform user who owns the service" }
    }
  },
  "category": {
    "group": "security",
    "label": "Security findings",
    "description": "Vulnerabilities your CI scanners report.",
    "configurable": true,
    "allows_all": true,
    "default_mode": "involved"
  },
  "severity": "degraded",
  "audience": [
    {
      "as": "owner",
      "who": { "user": "${{ context.owner_id }}" },
      "action": "acme.security_finding",
      "content": { "title": "Security finding on ${{ context.service }}", "body": "${{ context.summary }}" }
    }
  ]
}
```

Never send `publisher` or `organization_id`: the service sets them and refuses a body that carries them.

### Phase 3 — Validate (no write, read permission is enough)

```
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @validate.json "/communications/inbox_rule/validate"
```

Body: `{ "definition": <the draft>, "mode": "new" }`, or `{ "definition", "mode": "edit", "type_id": "<id>" }` for
an existing rule. Always `200 { valid, problems: [{ path, message }] }`, for a good or a bad document alike. It
runs every check of a save, including the caps and "already exists". Fix each `path` and repeat until
`valid: true`.

### Phase 4 — Dry-run and send a test to yourself (invoked rules)

Use the draft emission route: it takes the definition in the body, so nothing is saved yet. It needs
`notification_center:type:write` over the draft's scope, and the `nrn` must sit under that scope.

```
# What would be sent, to how many people, and why a reading would reach nobody. Writes nothing.
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @draft-emission.json "/communications/inbox_rule/emission?dry_run=true"

# Send the first reading to the caller only, as a real notification in their inbox.
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @draft-test.json "/communications/inbox_rule/emission"
```

- `draft-emission.json`: `{ "definition": <draft>, "nrn": "<resource>", "context": { "id": "test-1", ... } }`.
  Answer: `200 { would_emit: [{ as, recipients, payload, existing? }], rejected, deferred?, unreached?: [{ as, reason }] }`.
  `recipients` and `rejected` are counts; `existing: true` means that `context.id` was already emitted for this
  `nrn`, and a dry run answers `409` when it was emitted for another one. `unreached[].reason` is `nobody` (`who` resolved nobody), `no_watchers`
  (a followers-only reading with no followers) or `preferences` (everyone it reached turned it off).
- `draft-test.json`: the same body plus `"deliver_to": "me"`. Answer `201 { emitted: [...], rejected: 0,
  test: true }` (it reached you) or `200` with `emitted: []` (the rule's conditions rejected the context).
  Ask the user to open their bell and check the wording.

Without `?dry_run=true` and without `deliver_to: "me"` the draft route refuses (`400`): a draft never emits for
real. For a rule that is already saved, the same checks run on `POST /communications/inbox_rule/<id>/emission`
(see emission.md).

Rules that ride a nullplatform entity (`source` is a name, or stale) cannot be emitted; validate them and save
with `?dry_run=true` first.

### Phase 5 — Save (confirm first)

Show the final definition and ask for an explicit yes, then:

```
# Dry run of the save itself: 200 { valid: true }, nothing written
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @inbox-rule-<id>.json "/communications/inbox_rule?dry_run=true"
# Create: 201 with the stored row
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @inbox-rule-<id>.json "/communications/inbox_rule"
```

Update an existing custom rule with a full replacement (the body's `id` must equal the path's):

```
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method PUT --data @inbox-rule-<id>.json "/communications/inbox_rule/<id>?dry_run=true"
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method PUT --data @inbox-rule-<id>.json "/communications/inbox_rule/<id>"
```

A rule scoped below the organization root must restate its `visible_to` on PUT; leaving it out reads as a move
to the root. Moving a rule needs `type:write` over both NRNs. Editing a rule never changes notifications already
sent.

### Phase 6 — Verify

Read it back (`GET /communications/inbox_rule/<id>`) and confirm `status: active`. For an invoked rule, run one
`?dry_run=true` emission against the saved rule with a real `nrn`. Then hand over to emission.md to wire it
into the user's pipeline.

## Deactivate, reactivate, delete

| Goal | Request |
|------|---------|
| Deactivate a custom rule (frees its slot, sent notifications stay) | `DELETE /communications/inbox_rule/<id>` |
| Reactivate it | `PUT /communications/inbox_rule/<id>` with the full definition and `"status": "active"` at its top level, next to `id` (takes a slot again) |
| Delete it for good, with everyone's Inbox settings for it | `DELETE /communications/inbox_rule/<id>/permanent` (only once deactivated, else `409` with `detail` "Deactivate the type before deleting it") |

Prefer deactivating. Confirm before `/permanent`: it cannot be undone and it removes people's settings.

## Built-in rules

| Goal | Request |
|------|---------|
| Turn a built-in rule off (or back on) for the organization | `PUT /communications/inbox_rule/<id>/organization_state` with `{ "enabled": false }` / `{ "enabled": true }` |
| Edit a built-in rule for the organization | `POST /communications/inbox_rule` with a document whose `id` is the built-in id (start from `GET .../<id>`'s `document`). Only built-ins that ride an entity can be edited; invoked and stale ones (`api_key.expiring`) cannot. |
| Change an existing edit | `PUT /communications/inbox_rule/<id>`: it updates your organization's row, never the built-in |
| Discard the edit (Reset to default) | `DELETE /communications/inbox_rule/<id>/customization` |
| Start a new rule from a built-in one | Copy its `document`, give it a new id under your own prefix, and create it |

`organization_state` answers for the rule and the built-in rules linked to it, which turn on and off together.
An edited built-in rule stays at the organization root (`visible_to` exactly `organization=<id>`), is always
active and keeps the built-in id and source. `DELETE .../<id>` on it answers `409` (`CUSTOMIZED_DEFAULT`): reset it
with `/customization`, or turn it off with `organization_state`.

## Limits

- Up to **50 active custom rules** per organization, edited built-in rules included.
- Up to **10 active rules watching the same entity** (for example deployments).
- Both are reported by `validate` and by `?dry_run=true` as located problems.

## CLI equivalents (for the user to run, when their CLI has `np communications`)

```
np communications inbox rule list
np communications inbox rule read --id <id>
np communications inbox rule schema
np communications inbox rule validate --body validate.json
np communications inbox rule create --body inbox-rule.json
np communications inbox rule update --id <id> --body inbox-rule.json
np communications inbox rule delete --id <id>          # deactivates
```

Known limits: `dry_run` is not sent by the CLI (use `validate`, or `"deliver_to": "me"` on an emission);
`inbox rule list` accepts `--offset/--limit/--all` but the service ignores them and answers every rule.
`organization_state`, `/customization` and `/permanent` have no CLI command: use the API.
