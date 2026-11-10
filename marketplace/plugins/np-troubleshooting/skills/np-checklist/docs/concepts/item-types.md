# Item Types and Behaviors

A `ChecklistTemplate` defines an array of `items`. Each item has a `type`
(what kind of evaluation) and a `behavior` (how it influences the final
outcome).

## Item ids

Every item needs an `id` matching `^[a-z][a-z0-9_]{0,63}$`. The id is how
the aggregation expression refers to the item (`coverage_gate.passed`),
how `item_states` is keyed, and what you pass to `--item-id`. The
validator enforces uniqueness among siblings; keep ids unique across the
whole specification anyway, since the expression and `item_states` address them
globally.

**Never use `and`, `or`, `not`, `true` or `false` as an item id.** The
aggregation grammar claims those five words as operators and literals, so
`or.passed` tokenizes as the operator `or` followed by a stray `.` and the
whole expression fails to parse — the run resolves to `fail` /
`aggregation_parse_error`. The validator rejects them with
`item.id.reserved`; before that guard existed the specification saved cleanly
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
naming the corrected path in the message. Any specification written against the
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

## Visibility

`visibility` keeps an item out of the runner without taking it out of the
run. It is optional on any item, groups and items that declare `for_each`
included, and takes `visible` (the default: absent or `null` reads the
same) or `hidden`. The API stores the definition as sent and never writes
the default.

**Inheritance.** A hidden group hides its whole branch, at any depth. An
item that declares `for_each` (expanded in the run into a group with one
child per resource) hides the group and every child.

### When a hidden item shows anyway

A hidden item shows while it **decides** or **holds** the run, so nothing
out of sight can deny a request, let it through over a check, or keep it
waiting:

- **It decided.** A gate that ended without passing (`failed`,
  `timed_out`, `cancelled` or `skipped`) shows, even when an override then
  let the run through. A gate that passed stays hidden. Under a hidden
  `any` group the group decides, not its children (see below).
- **It holds the run.** A gate still open (`pending`, `in_progress`,
  `validating`, `undetermined`) shows while the run is not resolved,
  during a retry too; under a hidden `any` group, only when the group
  itself decides or holds (see below).
  - Exception: an item that waits on other items (`status: undetermined`,
    its `depends_on` naming them) stays hidden when everything open it
    waits on is visible. What it waits on is already on screen. If it
    waits on another hidden item, or on nothing open, it shows.
- **A closure reveals nothing.** These stay hidden:
  - an item that did not apply: `applicable: false`, or
    `sub_status: not_applicable`;
  - an item the resolved run never needed or never reached:
    `sub_status` `not_required` (on an approval) or `not_evaluated` (on a
    fail);
  - what the manual review swept (`sub_status: early_routed_to_manual`);
  - what the run's cancellation or expiry swept as `cancelled`.

  So a `skipped` reveals only when no closure explains it, as when a
  callback reports it; a `skipped` with `sub_status: not_applicable`
  stays hidden. A gate that failed, or that a callback cancelled, before
  the run was cancelled or expired stays visible: it is why the run did
  not approve.
- **An `informational` item never shows.** It neither decides nor holds
  anything.

A revealed item brings its ancestor groups. In a fan-out (`for_each`) it
brings the group and all of its children.

A hidden `any` group decides as a unit. When it ended without passing, or
the open run waits on it, it shows with its children that neither passed
nor closed, still-open ones included (an `informational` child stays
hidden). When it passed, its children stay hidden whatever their state, a
failed or a still-open one included.

### What the API returns

- `GET /approval/:id/checklist`: every entry of `items[]`, groups
  included, carries its effective `visibility` (`visible` once revealed).
- `items_summary`, on the run read and under `checklist` on
  `GET /approval/:id` and on each row of `GET /approval`: effectively
  hidden items leave `total`, every bucket and
  `first_pending_actionable_by_me`, and `hidden` counts them.
- `POST /approval/dry-run`: every entry of `policies[]` carries
  `visibility`, computed on the predicted states (`preview.items[]` does
  not carry it). When the prediction resolves to `fail`, hidden gates
  still pending stay hidden and hidden gates predicted to fail show.
- `specification_snapshot` carries every item as declared. Nothing is
  pruned from any response.

Inspecting a run: `docs/operations/runs-inspection.md`.

### Validation

The validator refuses to hide an item that someone must act on, or that
could decide the run unseen:

| Rule | Type | When |
|---|---|---|
| `item.visibility.invalid` | error | A value other than `visible` or `hidden` (uppercase and booleans included). |
| `item.visibility.needs_user` | error | A hidden `manual` item or `trigger: on_demand` external, hidden by its own `visibility` or by a group above it. |
| `item.visibility.override` | error | A hidden item with `behavior: override`, groups included, hidden by its own `visibility` or by a group above it. |
| `item.visibility.unsafe_ancestor` | error | An item that declares `hidden` under a visible `any` group or under an override. Hiding the whole `any` group is valid. |
| `item.visibility.custom_expression` | error | An item that declares `hidden` in a specification with `aggregation.type: expression`. |
| `group.visibility.all_children_hidden` | warning | A visible group whose children all declare `hidden`: the runner would draw it empty. |

Errors come back as `422 VALIDATION_FAILED` on create and update, with
`path` at the item's `visibility` when it declares `hidden`, or at the
item when a group hides it. The warning saves the specification and rides
back in `warnings[]`.

### What does not change

- **The engine.** A hidden item is evaluated, aggregated, audited (events,
  item logs) and notified like any other.
- **Older runs.** Runs created before `visibility` existed have none in
  their snapshot: every item stays visible.
- **The frozen snapshot.** `visibility` is read from the run's
  `specification_snapshot`. Changing it means a new specification version
  re-associated with the action, and only runs created afterwards see it.
- **Not authorization.** The specification, the snapshot, events and logs
  expose a hidden item to anyone with `approval_request:read`.

### When to use it

- **An auxiliary gate** that exists only so a rejection denies the run:
  for example, a gate whose `applies_when` reads
  `run.items.<approval>.status`, so it applies, and fails, only when that
  approval is rejected. Hidden, it stays out of the runner while it waits
  on the visible approval, and shows when it fails.
- **A data provider**, such as an external that feeds other items'
  `applies_when`. Prefer `informational`: a hidden `gate` shows while it
  runs, because it holds the run.
- **A silent audit**, recorded on every run and read later from the
  events or with `np-lake`. Use `informational`.
- **Shadow mode** for a new gate: ship it `informational` and hidden,
  measure it, then promote it.

```yaml
items:
  - id: coverage_gate
    type: condition
    behavior: gate
    title: "Coverage at least 80%"
    query:
      "build.metadata.coverage": { "$gte": 80 }

  # Shadow mode: evaluated and recorded on every run, never shown.
  - id: coverage_90_shadow
    type: condition
    behavior: informational
    visibility: hidden
    title: "Coverage at least 90% (shadow)"
    query:
      "build.metadata.coverage": { "$gte": 90 }

  # A hidden group hides its branch: its gates show only while they decide
  # or hold the run (here, when a check fails).
  - id: release_checks
    type: group
    behavior: gate
    visibility: hidden
    title: "Release checks"
    children:
      - id: tests_passed
        type: condition
        behavior: gate
        title: "Tests passed"
        query:
          "build.metadata.tests_status": { "$eq": "passed" }
      # A manual item here is rejected (item.visibility.needs_user):
      # someone has to act on it in the runner.
```

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

## YAML specification skeleton

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
