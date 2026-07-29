# Item Types and Behaviors

A `ChecklistTemplate` defines an array of `items`. Each item has a `type`
(what kind of evaluation) and a `behavior` (how it influences the final
outcome).

## Item ids

Every item needs an `id` matching `^[a-z][a-z0-9_]{0,63}$`. The id is how
the aggregation expression refers to the item (`coverage_gate.passed`),
how `item_states` is keyed, and what you pass to `--item-id`. The
validator enforces uniqueness among siblings; keep ids unique across the
whole template anyway, since the expression and `item_states` address them
globally.

**Never use `and`, `or`, `not`, `true` or `false` as an item id.** The
aggregation grammar claims those five words as operators and literals, so
`or.passed` tokenizes as the operator `or` followed by a stray `.` and the
whole expression fails to parse — the run resolves to `fail` /
`aggregation_parse_error`. The validator rejects them with
`item.id.reserved`; before that guard existed the template saved cleanly
and only blew up at run time. Note `nor` is fine — the grammar does not
claim it.

## Types

### `condition`
Automatically evaluated against the snapshotted context via a required
`query` field — a **mongo-like filter document** (the same condition
language used by approval policies), e.g.
`query: { "build.metadata.coverage": { "$gte": 80 } }`.
Operators: `$eq`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$and`, `$or`,
`$nor`, etc. The evaluated `query` and the resulting `passed` flag are
stored in `item_states[id].details.{query, passed}`.

#### Field paths: no `context.` prefix

**Paths address the context catalog directly — `build.metadata.coverage`,
never `context.build.metadata.coverage`.** Not just the same *language* as
approval policies: the same *addressing*, over the same catalog object. A
policy predicate and the checklist condition derived from it are written
identically, which is why `migrate_action.sh` can copy one into the other
verbatim.

Conditions used to be evaluated against a `{ context: <catalog> }` wrapper
that policies never had, so they needed the prefix. The wrapper is gone
and the validator now **rejects** `context.`-rooted paths with
`condition.query.context_rooted_path` / `item.applies_when.context_rooted_path`,
naming the corrected path in the message. Any template written against the
old contract fails at save time — which is the improvement: it used to
save cleanly and then resolve nothing, so every `gate` silently failed on
every approval request.

Rewriting an old definition:

```diff
- { "query": { "context.build.metadata.coverage": { "$gte": 80 } } }
+ { "query": { "build.metadata.coverage": { "$gte": 80 } } }
```

Only **keys that name a field** lose the prefix, and the rewrite must
recurse into `$and` / `$or` / `$nor` branches, since each entry is a
criteria object in its own right:

```jsonc
{
  "$or": [
    { "build.metadata.coverage": { "$gte": 80 } },
    { "build.metadata.tests_status": { "$eq": "waived" } }
  ]
}
```

Leave the expression side alone: operator keys and values are verbatim,
and `$elemMatch` sub-paths are relative to their field, not to the root —
a `context` key inside `$elemMatch` is a real field name.

The one place `context.` survives is `external.inputs` placeholders (see
`external` below) — that is the dispatch payload, not the query language.

Validation rules:
- `query` is **required** and must be a non-empty object
  (`condition.query.required` / `condition.query.type`).
- Field paths must not be rooted at `context.`
  (`condition.query.context_rooted_path`).
- The legacy expression dialect was **removed**: the fields `evaluator`,
  its alias `mode`, and `expression` (JS-like strings such as
  `"build.metadata.coverage >= 80"`) are rejected with
  `condition.evaluator.removed`, `condition.mode.removed`, and
  `condition.expression.removed`. This is independent of the addressing
  change — the whole dialect is gone, whatever the paths look like.

Items and groups also accept an optional `applies_when` — a mongo-like
query object (same language, same addressing) that gates whether the item
applies to the run at all, e.g.
`applies_when: { "scope.dimensions.environment": "production" }`.
String expressions are rejected here too, and so are `context.`-rooted
paths (`item.applies_when.context_rooted_path`).

Conditions are evaluated **once at run creation** (pre-evaluation phase)
and do not re-evaluate on each poll. Status: `passed` or `failed`.

### `manual`
A step that requires a human action. Status starts as `pending`; flips
to `passed` or `failed` when someone calls
`POST /approval/:id/checklist/items/:itemId/approve` (see
`manual_approve_item.sh`). Each manual item has:
- `title` — short label shown in the runner UI.
- `description` — longer guidance for the human approver.

### `external`
Delegates evaluation to an external system via HTTP. The backend
dispatches the request when the run starts (`trigger: auto`) or when
explicitly invoked (`trigger: on_demand`). External executors call back
via a signed one-shot token to set status. Each `external` item has:
- `external.channel` — `http` (currently the only supported channel).
- `external.url`, `external.method`, `external.headers`.
- `external.inputs` — arbitrary payload merged into the dispatch.
- `external.timeout_seconds` — when to mark the item as `failed` if no
  callback arrives.

`inputs` values support `{{ ... }}` mustache placeholders resolved against
the run context. **These keep the `context.` form** —
`"{{ context.release.id }}"` — because the dispatch payload is still
wrapped as `{ context: <catalog> }`. That wrapper is deliberate and
unrelated to the query language, so do **not** strip the prefix here the
way you would in `query` / `applies_when`. (The resolver also accepts
`{{ release.id }}`; `context.`-rooted is the documented form.)

### `group`
Composite items that hold a list of `children` (which themselves can be
of any type, including nested groups). Useful to organize the runner UI
("Pre-deploy checks", "Manual sign-offs", etc.) and to combine
behaviors. The group itself does not have a status independent of its
children — the aggregation engine walks into children.

## Behaviors

Every item must declare a `behavior`. Validated server-side.

### `gate`
Bound to the outcome: if any `gate` item is `failed`, the aggregate
status moves toward `pending_override` (if there are override items) or
resolves as `fail` directly.

### `informational`
Recorded and surfaced in the UI, but does not influence the final
outcome regardless of pass/fail. Useful for visibility ("here's the
Snyk report, FYI") without blocking releases.

### `override`
Only relevant when at least one `gate` item is `failed`. An approved
`override` item resolves the run as `approve_with_override`. Typically
used for CAB emergency approvals or off-hours fast-tracks.

## Aggregate transitions

The aggregation engine derives `aggregate_status` based on item states:

```
pending_items        →  some items still pending evaluation
pending_aggregation  →  all items resolved, computing aggregate
pending_override     →  at least one gate failed; awaiting override decision
resolved             →  final_outcome set, run ended
```

And `final_outcome`:

```
approve                 →  all gate items passed (or no gates)
approve_with_override   →  some gate failed but an override item approved
fail                    →  some gate failed, no override approved (or no overrides defined)
cancelled               →  run cancelled externally
expired                 →  hit the action's allowed_time_to_execute window
```

## YAML template skeleton

```yaml
items:
  - id: coverage_gate
    type: condition
    behavior: gate
    severity: high
    query:
      "build.metadata.coverage": { "$gt": 80 }

  - id: security_signoff
    type: manual
    behavior: gate
    title: "Security team sign-off"
    description: "Required for releases touching auth surfaces."

  - id: snyk_report
    type: external
    behavior: informational
    external:
      channel: http
      url: "https://hooks.acme.com/snyk-report"
      method: POST
      trigger: auto
      timeout_seconds: 300
      inputs:
        # Placeholders keep the `context.` root — dispatch payload, not query language.
        release_id: "{{ context.release.id }}"

  - id: cab_override
    type: manual
    behavior: override
    title: "CAB emergency override"
    description: "Use only when blocking gates are misconfigured and a release must ship now."

  - id: pre_deploy_checks
    type: group
    behavior: gate
    children:
      - id: tests_passed
        type: condition
        behavior: gate
        query:
          "build.metadata.tests_status": { "$eq": "passed" }
      - id: lint_clean
        type: condition
        behavior: gate
        query:
          "build.metadata.lint_errors": { "$eq": 0 }
```
