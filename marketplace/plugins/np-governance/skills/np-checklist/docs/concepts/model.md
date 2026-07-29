# Data Model

The checklist domain lives in the approval-api alongside the classic policy
model. Five tables, all scoped by NRN.

## Entities

### `checklist_template`
A versioned, NRN-scoped definition of a checklist. The `definition` JSONB
field holds the items array and any aggregation override. The server
computes `derived_expression` (the boolean expression derived from item
`behavior`s, used by the aggregation engine).

```
checklist_template
├── id                  VARCHAR(26) PK     (tmpl_<nanoid21>)
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
Snapshots both the template and the evaluation context at creation time.

```
checklist_run
├── id                   VARCHAR(26) PK     (crun_<nanoid21>)
├── approval_request_id  INTEGER  UNIQUE → approval_request(id) ON DELETE CASCADE
├── template_id          VARCHAR(26)      → checklist_template(id)
├── template_snapshot    JSONB              full template at trigger time
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
└── checklist_template_id  VARCHAR(26)   nullable, references checklist_template(id)
                                          XOR with approval_action_policy associations

approval_request
├── mode             VARCHAR(16)         NULL (legacy) | 'policy' | 'checklist'
└── checklist_run_id VARCHAR(26)         nullable, references checklist_run(id)

approval_action_policy
└── deleted_at       TIMESTAMPTZ         nullable (soft-delete; defaultScope filters)
```

## Relationships

```
ApprovalAction ──(1:1, optional)──→ ChecklistTemplate
                                          │
                                          │ (versioned definition)
                                          ▼
ApprovalRequest ──(1:1)──→ ChecklistRun ──(1:N)──→ ChecklistEvent
                                  │
                                  └───────(1:N)──→ ChecklistItemLog (keyed by item_id)
```

## Notes

- The XOR (action has policies OR a template, never both) is enforced at the
  service layer, not at the DB level. Migration archives policies with
  `deleted_at`.
- `template_snapshot` and `context_snapshot` on `checklist_run` are
  **immutable** — they hold the exact state used by the evaluator at
  trigger time. Edits to the live template do not retroactively alter
  in-flight runs.
- Item-level events live in two places intentionally:
  - `checklist_event` for the audit trail (one row per transition).
  - `checklist_item_log` for diagnostic logs (multiple rows per item).
