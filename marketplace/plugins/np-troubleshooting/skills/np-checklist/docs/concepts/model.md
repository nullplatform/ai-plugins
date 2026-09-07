# Data Model

The checklist domain lives in the approval-api alongside the classic policy
model. Five tables, all scoped by NRN.

## Entities

### `checklist_specification`
A versioned, NRN-scoped definition of a checklist. The `definition` JSONB
field holds the items array and any aggregation override. The server
computes `derived_expression` (the boolean expression derived from item
`behavior`s, used by the aggregation engine).

Named `checklist_template` until mid-2026 — the table and the API surface
were renamed to `specification` (the FK columns run expand/contract: see
"Transitional state" below). Rows created before the rename keep their
`tmpl_`-prefixed ids; new rows get `spec_`. Both prefixes coexist and ids
are opaque — never rewrite one.

```
checklist_specification
├── id                  VARCHAR(26) PK     (spec_<nanoid16>; pre-rename rows: tmpl_<nanoid16>)
├── nrn                 VARCHAR(255)
├── status              VARCHAR(16)         active | inactive | deleted
├── name                VARCHAR(255)
├── description         TEXT
├── version             INTEGER
├── definition          JSONB              { items: [...] }
├── derived_expression  TEXT               computed by server
├── created_by          VARCHAR(255)
├── created_at, updated_at  TIMESTAMPTZ
└── UNIQUE (nrn, name, version)
```

### `checklist_run`
The runtime instance — one per `approval_request` in checklist mode.
Snapshots both the specification and the evaluation context at creation time.

```
checklist_run
├── id                   VARCHAR(26) PK     (crun_<nanoid21>)
├── approval_request_id  INTEGER  UNIQUE → approval_request(id) ON DELETE CASCADE
├── specification_id     VARCHAR(26)      → checklist_specification(id)
├── specification_snapshot  JSONB           full specification at trigger time
├── template_id          VARCHAR(26)        transition twin of specification_id (authoritative until Phase 4)
├── template_snapshot    JSONB   NOT NULL   transition twin of specification_snapshot (authoritative until Phase 4)
├── context_snapshot     JSONB              context evaluated against
├── idempotency_key      VARCHAR(64) UNIQUE
├── aggregate_status     VARCHAR(32)        pending_items | pending_aggregation | pending_override | resolved
├── final_outcome        VARCHAR(32)        approve | approve_with_override | fail | cancelled | expired
├── outcome_reason       TEXT
├── item_states          JSONB              { item_id: { status, behavior, severity, message, details, ... } }
├── override_metadata    JSONB
├── started_at           TIMESTAMPTZ
└── resolved_at          TIMESTAMPTZ
```

### `checklist_event`
Cronologically ordered audit trail per run. Every state transition (item
evaluated, dispatch sent, callback received, aggregation computed,
override applied, run resolved) lands here.

```
checklist_event
├── id                VARCHAR(26) PK         (cevt_<nanoid21>)
├── checklist_run_id  VARCHAR(26)           → checklist_run(id) ON DELETE CASCADE
├── sequence_number   BIGINT                 monotonic per run
├── occurred_at       TIMESTAMPTZ
├── event_type        VARCHAR(64)            e.g. "item.status_changed", "checklist.resolved"
├── actor             VARCHAR(255)           user | system | external
├── payload           JSONB
└── UNIQUE (checklist_run_id, sequence_number)
```

### `checklist_item_log`
Structured log lines per item — used for diagnosis, especially for
`external` items whose executor reports back asynchronously.

```
checklist_item_log
├── id                VARCHAR(26) PK         (clog_<nanoid21>)
├── checklist_run_id  VARCHAR(26)           → checklist_run(id) ON DELETE CASCADE
├── item_id           VARCHAR(128)
├── occurred_at       TIMESTAMPTZ
├── level             VARCHAR(16)            debug | info | warn | error
├── message           TEXT
└── details           JSONB
```

### `revoked_token`
Used to invalidate one-shot callback tokens issued to external item
executors. Not strictly part of the checklist domain but introduced
alongside it.

```
revoked_token
├── token_hash        VARCHAR(128) PK
├── revoked_at        TIMESTAMPTZ
├── expires_at        TIMESTAMPTZ
└── checklist_run_id  VARCHAR(26)
```

## Approval-side additions

The migration also extends two existing tables:

```
approval_action
├── checklist_template_id       VARCHAR(26)  nullable — legacy column, AUTHORITATIVE during
│                                             the transition (the app reads it; see below)
└── checklist_specification_id  VARCHAR(26)  nullable, references checklist_specification(id)
                                              dual-written mirror of the legacy column
                                              XOR with approval_action_policy associations

approval_request
├── mode             VARCHAR(16)         NULL (legacy) | 'policy' | 'checklist'
└── checklist_run_id VARCHAR(26)         nullable, references checklist_run(id)

approval_action_policy
└── deleted_at       TIMESTAMPTZ         nullable (soft-delete; defaultScope filters)
```

## Transitional state (until Phase 4 of the rename)

The rename runs expand/contract, so **both column families coexist** and
the DB you query today is not the post-sunset schema described above in
its clean form:

- `approval_action.checklist_template_id` (legacy) and
  `checklist_specification_id` (canonical) are **dual-written** on every
  save, but the **legacy column is authoritative**: rows mutated by
  pre-rename code during the 0.50.0 deploy window can carry a stale
  canonical value (the initial backfill is frozen at migration time), so
  the app reads the legacy column **even when it is NULL** and raw SQL
  should filter on `checklist_template_id` directly. Don't
  `COALESCE(legacy, canonical)`: it diverges exactly on the stale case —
  a row unlinked by pre-rename code (legacy NULL, canonical still
  holding the dead association).
- `checklist_run.template_id` / `template_snapshot` (legacy, `template_snapshot`
  holds the NOT NULL constraint) coexist with `specification_id` /
  `specification_snapshot`, same dual-write and same caveat.
- A **compatibility view named `checklist_template`** is defined as
  `SELECT * FROM checklist_specification`, so old SQL keeps resolving.

Phase 4 (legacy sunset) drops the legacy columns and the view, making the
canonical names the only ones — at that point the clean schema above is
literal.

## Relationships

```
ApprovalAction ──(1:1, optional)──→ ChecklistSpecification
                                          │
                                          │ (versioned definition)
                                          ▼
ApprovalRequest ──(1:1)──→ ChecklistRun ──(1:N)──→ ChecklistEvent
                                  │
                                  └───────(1:N)──→ ChecklistItemLog (keyed by item_id)
```

## Notes

- The XOR (action has policies OR a specification, never both) is enforced
  at the service layer, not at the DB level. Migration archives policies
  with `deleted_at`.
- `specification_snapshot` and `context_snapshot` on `checklist_run` are
  **immutable** — they hold the exact state used by the evaluator at
  trigger time. Edits to the live specification do not retroactively alter
  in-flight runs.
- Item-level events live in two places intentionally:
  - `checklist_event` for the audit trail (one row per transition).
  - `checklist_item_log` for diagnostic logs (multiple rows per item).
