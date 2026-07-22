# State & persistence patterns

The workflow system deliberately has **no user tables**. Everything a
production-grade workflow suite needs to remember is composition of existing
platform primitives. Choosing the right one is the difference between a toy
workflow and a product; this guide is that decision, distilled from suites
built and operated in production (see the reference suites in
`github.com/nullplatform/workflows` — the cost suite exercises every pattern
here).

## The decision table

| You need to remember… | Use | Lifetime |
|---|---|---|
| A value across steps of ONE run | workflow `variables` (+ `set-variable`) | the execution |
| Iteration state of ONE node across loop re-entries | `nodeContext` | the execution |
| Durable state attached to a platform entity (scope, app, account) | **catalog metadata instance** | forever, entity-scoped |
| Work items with lifecycle, owners and UI | **governance action items** | until closed |
| Org/folder configuration and credentials | **config entries** (`${{ vars.X }}` / `${{ secrets.X }}`) | until changed |
| Fine-grained/high-volume data (metrics, events) | leave it in its system of record (Prometheus, lake); store the SHAPE, not the points | that system's retention |

## Catalog metadata as the data spine

The heavyweight pattern. A `metadata_specification` on an entity type plus
one instance per entity gives you durable, schema-validated, UI-rendered,
lake-mirrored state with zero new infrastructure:

- **Spec** (`POST /metadata/metadata_specification`, entity e.g. `scope`):
  JSON-schema fields, per-property `visibleOn: ["read","list"]` for
  read-only UI, chips via uiSchema (`format: chip` + color/icon mapping per
  value). PATCH the spec in place to evolve it.
- **Instance** (`POST /metadata/{entity}/{id}/{key}`): the entity's state.
  The metadata service COERCES types to the schema (send strings, get
  numbers back — don't stringify for the UI).
- **Lake mirror**: every instance lands in `core_entities_metadata` within
  seconds (`metadata_type = <key>`, `data` = JSON string) — dashboards read
  the lake, never your workflow.

Rules that keep a shared instance sane (learned the hard way):

1. **Field ownership per workflow.** When several workflows write one
   instance, each field has exactly ONE writer; every other workflow
   PRESERVES it on write (read-modify-write upsert: GET the instance, spread
   the fields you don't own, POST the merge). Example: a daily collector
   owns the measurement fields; a weekly scanner owns the verdict fields
   (`status`, `note`, item pointer); the collector spreads the scanner's
   fields untouched.
2. **Bounded series, not raw points.** A `daily_series` array with FIFO cap
   (e.g. 365 entries, one compact object per day) keeps the SHAPE of a
   signal beyond the source system's retention at negligible size. Never
   store per-minute data in an instance — it explodes the instance AND the
   lake row. The fine grain stays in Prometheus/the lake; your workflow
   queries it live when it needs to zoom in.
3. **`last_*` stamps as cheap cross-run coordination.** A verdict stamp
   (`last_scan_at`, `last_scan_status`, plus a human-readable
   `last_scan_note`) turns "should this run process this entity again?"
   into two API reads — no queue, no lock. Conclusive outcomes stamp;
   `no_data` stamps nothing (unmonitored is not resolved).
4. **Status fields are consequences, not computations.** A chip like
   `provisioning_status` should reflect a decided lifecycle ("there is an
   open, validated finding"), not a live calculation that flip-flops with
   every data refresh.

## Action items as queues and idempotency

- **Idempotency key in metadata**: give each item a deterministic key
  (`metadata.my_key = "<workflow>-<entity>"`) and upsert by searching it —
  re-runs update instead of duplicating.
- **The item pointer lives on the entity** (metadata instance field, e.g.
  `open_item_id`): the follow-up workflow's work queue is "entities with a
  live pointer", one API read each. Heal the pointer when you find it stale.
- **Aggregation items**: findings individually too small to act on
  accumulate in ONE org-level item (a label of its own + a
  `metadata.entries` map keyed by entity, rendered as a table in the
  description). Enter on below-threshold, leave on any other resolution.
- Closed items **cannot be reopened** — recreate instead.
- Transitions need an `actor` (`POST /governance/action_item/{id}/{action}`
  body `{actor}`).

## Run-scoped state (the small two)

- `variables` + `set-variable`: the accumulator of the streaming-pagination
  pattern; seeded from `initialValue` (an input `default` is NOT applied at
  runtime — constants a step needs go in `variables`).
- `nodeContext`: per-NODE bag surviving loop re-entries within a run
  (split-in-batches, paginated-fetch stream). Plugin-internal — workflow
  authors don't touch it; if you author a PLUGIN that mutates it, declare
  `capabilities: ['uses-node-context']` or mutations are silently dropped
  at the step boundary.

## What NOT to do

- No per-minute/high-volume data in metadata instances (store the shape).
- No state in code-exec module scope — every execution is a fresh sandbox.
- No secrets anywhere except config entries (`${{ secrets.X }}`).
- No new storage tables or CRUD APIs for integrations — if a design seems
  to need a new entity, restate it on the primitives above.
