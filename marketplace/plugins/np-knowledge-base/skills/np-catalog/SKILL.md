---
name: np-catalog
description: The nullplatform catalog — building it and reading it. Building — specifications, instances (entities), relations (belongs_to, has_one, has_many, many_to_many), interceptors, events, custom actions, authorization, modeling an org's data as a graph, ingesting repos, docs, runbooks or services into a knowledge base, semantic fields and embeddings. Reading — any question answerable from records already in the catalog — analysing, reporting on, counting, comparing, auditing or explaining deployments, releases, services, applications, incidents or documents. Covers "give me the deployment analysis", "what shipped last month", "what changed across our services", "how many X by Y", "is this field trustworthy". Use it whenever a question could be answered from catalog data, even if the user never says "catalog", never names the API, and only asks for an analysis, summary or report. Also use when a spec change or ingest misbehaves. Requires NP_TOKEN or NP_API_KEY (same auth as np-api).
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/scripts/*.sh)
---

# np-catalog

Skill to operate the **nullplatform catalog**: a schema-driven, multi-tenant
metadata system. Types are **specifications** (JSON Schema + custom keywords),
records are **instances** attached to a specification, links between records
are **relations**, and everything is queryable with filters, facets, and full-text search.

## Critical Rules

1. **Every API call goes through `catalog-api.sh`** — never raw `curl`. The script
   delegates auth (token exchange, caching) to `np-api` and points at the catalog host.
2. **`PATCH /specifications/:id` merge-patches `schema` (RFC 7386)**: an omitted
   key PRESERVES the stored value, an explicit `null` REMOVES it. To delete a property,
   relation, action, or authorization plane you MUST send `"key": null` — re-sending the
   composed schema without the key silently keeps it. Read the stored spec first, send
   the minimal diff.
3. **Instance payloads are alias-first**: request/response bodies use the **aliases**
   defined in the spec, not internal property keys. User-defined aliases are sacred
   (`userName` stays `userName`); only system envelope keys (`id`, `tenant_id`,
   `created_at`, `updated_at`) are snake_case — and even those can be aliased by the spec.
4. **Reference by ID, never by slug** — spec slugs and aliases are mutable, IDs are not.
   Resolve the slug once, then carry the ID.
5. **Deletes are soft** — `DELETE` sets `deleted_at`; nothing is ever hard-deleted.
6. **Two read paths**: `GET` by id is immediately consistent with writes; list/facet/
   search queries serve from a separate read index and can lag writes by a moment.
   If a just-created instance is missing from a list, retry the list — do not re-create.
7. **`limit` must be ≤ 100** (the API rejects more with `limit must not exceed 100`).
   Default page size is 30.
   Paginated responses return `{ paging: { offset, limit }, results, facets }` — there is
   NO total count anywhere; page until `results` comes back short.
8. **Read the schema, then pick the method.** If the spec declares `index: ["semantic"]`
   or `["fulltext"]` on a field, any question about *what the records say* MUST go
   through ranking (`sort=relevance`) or `query` — never through paging every record
   and reading rows. Under `sort=relevance`, `query` MUST state the full information
   need — a natural-language question or a content-rich phrase ("how does retry
   backoff work?"), never a bare keyword: the whole phrase is embedded, and a single
   word degrades ranking to keyword matching. Reformulating and re-asking is cheap
   and normal. (`query` and `q` are aliases; prefer `query`.) Paging answers *how many*; it cannot answer *what happened*, and it
   fails **silently**: you get a confident, plausible, wrong answer with no error.
   Methods compose — pick from the matrix in **Reading the catalog** below, which is
   inline precisely because this failure has no error to catch it.

## Environment

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `NP_TOKEN` / `NP_API_KEY` | yes | — | Auth, resolved by `np-api` (token exchange + cache). Same precedence as `/np-api check-auth` |

`np-api` MUST be installed alongside this skill (the `np-catalog` bundle includes it).

Quick connectivity check (also verifies auth):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/scripts/catalog-api.sh GET '/specifications?include=name&limit=1'
```

Do NOT use `GET /health` as the check — it is not part of the public catalog
surface and answers with an unrelated 200 that never touched the catalog
(a false positive).

## Endpoint Map

All paths are relative to the public base URL (`https://api.nullplatform.com/catalog`). The legacy `/entities/*` and `/entity_specifications/*` spellings are gone — they 404; the current families are `/instances/*` and `/specifications/*`.

| Area | Endpoints |
|------|-----------|
| Specifications | `GET/POST /specifications`, `GET/PATCH/DELETE /specifications/:id` |
| Instances | `GET/POST /instances/:slug`, `GET/PATCH/DELETE /instances/:slug/:id` (PATCH supports `?upsert=true`) |
| Relations | `GET/POST /instances/:slug/:id/:relation`, `GET/PATCH/DELETE /instances/:slug/:id/:relation/:relatedId` |
| Search | `GET/POST /search` (cross-type), plus the filter/facet dialect on every list endpoint |
| Retrieval | `GET/POST /search?query=…&sort=relevance` — semantic/hybrid ranking over prose fields, results carry `matches[]` |
| Traversal | `POST /traverse` — bounded relation walk (`from` + ordered `steps`) returning `nodes` + `edges` with EXTERNAL ids |
| Interceptors | `GET/POST /specifications/:id/interceptors`, `GET/PATCH/DELETE .../interceptors/:interceptorId` |
| Events | `GET/POST /specifications/:id/events`, `GET/PATCH/DELETE .../events/:eventId` |
| Actions | `POST /actions/:slug/:id/:action`, `GET /actions/:slug/:id/history`, `GET/PATCH /actions/:slug/executions/:actionId` |

## Reference docs — you must OPEN these; they do not arrive on their own

These paths are `@`-referenced so a plugin-marketplace install inlines them. **In a
plain `.claude/skills/` install the `@` does nothing** — `${CLAUDE_PLUGIN_ROOT}` stays
literal and none of this content reaches you. If you can see the words
`${CLAUDE_PLUGIN_ROOT}` in the table below, that is the case right now: read the file
yourself with Read, resolving `${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/` against this
skill's base directory.

Everything needed to pick a read method is inlined in **Reading the catalog** below, so
a query can proceed without opening anything. The docs carry the depth — open the one
matching your task before acting on it.

| Doc | Read when |
|-----|-----------|
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/specifications.md | Creating or updating a specification: schema keywords (`alias`, `index`, `primaryKey`, `autoGenerate`, `nrn`, `relations`, `requiredRelations`, `actions`, `authorization`), identity strategies, merge-patch semantics, limits |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/instances.md | Creating, reading, updating, upserting, or deleting instances |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/relations.md | Declaring relations in a spec or linking/unlinking/querying related instances — the four types behave very differently |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/search.md | **The one to open for almost any read** — filters and operators, `is_null`, sort, facets, sparse fieldsets (`include`/`exclude`, which keep a paged read cheap — on instances AND on specifications/handlers/action history, where `exclude=schema` drops the embedded JSON Schema), full-text `query`, and the cross-type `/search` endpoint |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/method-selection.md | What each read method *costs*, and the diagnostics for when a number looks wrong — verifying a grouping key, proving a derived field was never written, reading a `truncated` answer. Method choice itself is inline below |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/organization-knowledge.md | **Read FIRST when designing a catalog or knowledge base**, before writing any spec: which job belongs to relations vs semantic fields vs indexed scalars, identity for idempotent re-ingest, shaping the graph so questions can be bounded, splitting long documents, provenance via `kind`, deriving artifacts instead of dumping sources, anti-patterns |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/semantic-retrieval.md | Storing prose for retrieval (`index: ["semantic"]`), asking questions in natural language (`sort=relevance`, `matches[]`), walking relations (`POST /traverse`), scoping a ranking to a neighborhood |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/automation.md | Interceptors (sync gates), events (async notifications), custom actions and their execution/history |
| @${CLAUDE_PLUGIN_ROOT}/skills/np-catalog/docs/authorization.md | The `authorization` schema block: planes, grants, denials, principals, field scopes |

## Reading the catalog

Everything in this section is inline on purpose: choosing the read method wrong is the
one failure here that produces no error, so the guidance cannot sit behind a file you
might not open. `docs/search.md` has the query dialect these calls are written in;
`docs/method-selection.md` has each method's cost and the diagnostics.

### Orient first

1. `GET /specifications` to discover types; `GET /specifications/:id` for the schema.
2. **Read the schema's `index` flags** — they tell you which methods exist for this spec:
   `filter`/`facet`/`sort` → scalars, `semantic` → ranking, `fulltext` → `query`.
   A spec carrying semantic fields is telling you its answers live in prose.

### Then pick by the question, not by the record count

| Question | Facets | Filter + page | Semantic | Fulltext | Traverse |
|---|---|---|---|---|---|
| How many / what distribution | **1** | 2 *if you need rows* | — | — | — |
| Find every instance of X | 2 *size it* | 3 *hydrate* | **1** | — | — |
| Did a change ripple across services | — | 3 *join fields* | **1** | — | 4 *blast radius* |
| Is this flag / derived field trustworthy | 2 *count* | 3 *cross-ref* | **1** | 4 *evidence* | — |
| How does X work in this application | — | 4 *hydrate* | 3 *scoped* | — | **1→2** *bound* |
| Which record mentions this exact identifier | — | 2 *hydrate* | — | **1** | — |

Bold = entry point; numbers = order. Facets give the **shape**, ranking gives the
**story**, traverse gives the **boundary**. A question with both a *how many* and a
*what happened* clause needs two instruments, and the finding is usually in the join
rather than in either response.

**Stop when the question is answered.** The matrix says what each question *needs*, not a
checklist to work through. Facets are a complete answer to a distribution question, and
pulling the records afterwards transfers the whole population to re-derive a number the
aggregation already gave you. Verification is cheap to justify and expensive to run, so
spend it where being wrong would change the answer — when a count contradicts something
you already know, or when you are about to act on it. `docs/method-selection.md` covers
the diagnostic reads (checking a grouping key, reconciling a relation against a
denormalised label) for when you are actually chasing a discrepancy.

### The join: rank → confirm → hydrate

Ranking knows *which* records are relevant but returns only candidates and passages;
the scalar fields live on the records. Nothing else substitutes for combining them.

1. **Rank** — `POST /search` with `query` and `sort: "relevance"`.
2. **Confirm from `matches[].text`, not from rank.** Ranking is recall-oriented by
   contract: a candidate set for a reader to judge, not a filtered result. Treating
   rank as classification is the fastest way to publish a wrong number.
3. **Hydrate** — join the confirmed ids against paged records (or `GET /instances/:slug/:id`)
   for the fields ranking never returns.

### Three traps worth naming

- **Negation blindness.** Ranking registers topic, not polarity: a record saying
  *"**No** auth or schema changes"* ranks high for *"auth change"*. No error, no score
  penalty. Decide yes/no questions from an indexed scalar or a rationale field, never
  from rank alone.
- **Paging is not reading.** Paging every record and skimming rows answers *how many*
  and silently fails *what happened* — you end up describing whatever sat at the top of
  your sort. If the question is about what the records *say*, rank; don't scroll.
- **A sorted slice is not the population.** Reading the top-severity rows and then
  describing the whole set is the same error wearing a filter: everything below the
  cutoff is structurally invisible, so a pattern that spans severities reads as though it
  were confined to the worst ones. Whatever bounded your view — a sort, a filter, a first
  page — bounds your conclusion too, so either widen it or say what it was.

### Scope a question to one thing (search → traverse → scoped search)

For "how does X work **in this app**" — anchor, bound, then ask
(details and a runnable example in `docs/semantic-retrieval.md`):

1. Find the anchor: `GET /search?query=<name>&limit=1` — the result carries the spec
   slug (`entity`) and the id, exactly what `traverse` needs.
2. Bound the context: `POST /traverse` with `from: {id, specification_slug}` and
   `steps` — returns the neighborhood's `nodes` (external ids, no data).
3. Ask inside the bound: `POST /search` with `query`, `sort: "relevance"`, and
   `id: [<nodes[].id>]` (POST because the id set outgrows a URL).
4. Hydrate specifics: `GET /instances/:slug/:id` per node of interest.

Skip step 2–3 scoping and rank tenant-wide only for discovery questions
("which service does X?") — scoped is both more precise and cheaper.

## Writing to the catalog

### Create a specification and attach instances

1. Read `docs/specifications.md`, then `POST /specifications` with
   `{ "name": ..., "description": ..., "schema": { ... } }` (slug is derived from name).
2. Capture the returned `id` and `slug`.
3. `POST /instances/:slug` with the instance data keyed by **aliases** — repeat per instance.
4. Verify: `GET /instances/:slug/:id` (PG, immediate), then `GET /instances/:slug` (CH list).

### Wire two specifications together

1. Ensure the target spec exists; capture its slug.
2. `PATCH` the source spec's schema with a `relations` entry (see `docs/relations.md`
   for type selection — inline-FK types auto-create a backing property).
3. Traversal is per-declaration: if BOTH directions must be walkable
   (child→parent and parent→children), declare a relation on each spec —
   `belongs_to` on the child, `has_many` on the parent (create child spec first,
   then PATCH the parent; see the mutual-reference ordering in `docs/relations.md`).
4. Link instances: `POST /instances/:slug/:id/:relationKey` (creates + links for
   `belongs_to`/`has_one`/`has_many`; links existing by `[{"id": "..."}]` for
   `many_to_many`).

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `401` | No/expired token | `/np-api check-auth`; set `NP_TOKEN` or `NP_API_KEY` |
| `Field 'x' is not indexed and cannot be filtered` | Filtering on a field without `"index": ["filter"]` | Add the index to the spec schema, or filter on an indexed field |
| `Sort field 'x' is not sortable` | Sorting needs a declared indexed field | Sort on an indexed field or `created_at`/`updated_at` |
| `Operator 'gt' cannot be used with text field` | Numeric operator on a text field | Use string operators (`contains`, `starts_with`, ...) or fix the field type |
| `limit must not exceed 100` | Oversized page | Page with `offset` instead. Beware jq: `.results\|length` turns the rejection into `0`, which reads as an empty tenant |
| `409`/`already exists` on spec create | Slug collision (derived from name) | Pick a different name, or `PATCH` the existing spec |
| Spec update 400s about a relation target | Relation `target` slug doesn't exist for that tenant | Create the target spec first, or use `targetId`. If the named relation is one the patch never touched (an older deployment), re-state every sibling relation with its `target` slug |
| Spec update 400 `... which are different specifications` | Patch carries both `target` and `targetId` naming different specs (usually a slug echoed back from a read after the target was renamed) | Drop the stale `target`, or send `targetId: null` alongside the new slug to re-point deliberately |
| Instance create 400 `entity ID is required when 'autogenerate' is set to false` | External identity (UUID_V5) missing from the payload | Send the identity under the PK's alias (the literal `id` key also works) — see `docs/instances.md` |
| Instance create 400 `id` not allowed | Spec uses auto-generated identity (UUID_V4) — the API assigns ids | Drop `id` from the payload; see identity strategies in `docs/specifications.md` |
| Relation FK reads back `null` but the link works | Relation alias was changed on an older deployment, where the backing property keeps the old alias | Compare `schema.relations.<k>.alias` with `schema.properties.<k>.alias`; drop and recreate the relation to re-align — see `docs/relations.md` |
| Just-created instance missing from list | Lists/facets serve from a read index that can lag writes | `GET` by id is consistent; retry the list after a moment |
| `sort=relevance` returns 0 hits for prose you know exists | The field is indexed `fulltext`, not `semantic` — no chunks were ever produced, and the miss is silent | Declare `index: ["semantic"]` and re-write the instance; see `docs/semantic-retrieval.md` |
| An analysis reads plausibly but a second method contradicts it | One instrument answered a question spanning two. Paging answers *how many* and cannot answer *what happened*; ranking answers *what happened* and returns no scalars | Re-run through the matrix in **Reading the catalog** above and join the methods |
| `sort=relevance` returns records that **deny** the queried property | Negation blindness — ranking registers topic, not polarity ("**No** auth or schema changes" ranks high for "auth change") | Use rank to build the candidate set, then decide from an indexed scalar or a rationale field per record |
| `traverse` returns fewer nodes than a filter on the denormalized label | Those records have a **null** foreign key — the edge was never written, though the label was | Check both keys before grouping; a disagreement is an ingest bug surfaced by a retrieval check |
| `403` on `/search` while `/instances/:slug` reads fine | Cross-type search is a separate permission from reading one specification; the token has the latter, not the former | Rank within a spec via its list endpoint, or get the token's grants widened. Say so in the answer — without cross-type ranking, a "how many match" figure is a floor, not a total |
| A reported count came from a response with `truncated: true` | The set was capped by the retrieval depth or node budget | Treat the number as a floor, not a total — narrow the filter or page |
| Spec create 400 `semantic field '/x' declares maxLength N, above the per-field cap` | Semantic fields cap at 32768 characters regardless of the 1 MB document ceiling | Lower `maxLength`, or split the prose across child instances |
| `POST method is only allowed for endpoints matching…` on `/search` or `/traverse` | Installed `np-api` predates these paths in its `ALLOWED_MODIFY` allowlist | Update/reinstall `np-api` together with `np-catalog` |
| Interceptor 5xx blocks a create/update | A gating interceptor failed with `on_failure: fail` | Inspect handlers via `GET .../interceptors`; fix or disable the handler |
| `keyword "actions" value is invalid ... must be object` on spec PATCH | Nulled the LAST item of a keyword map | Null the whole section (`"actions": null`) instead — see `docs/specifications.md` |
| `schema update contains N breaking change(s)` on spec PATCH | Removing a property or relation destroys stored data/links | Re-send with `"allow_destructive": true` beside `schema` once the loss is intended — see `docs/specifications.md` |
| `Cannot delete specification ... referenced by relation` | Another spec's relation targets it | Remove the referencing relation first (destructive change), then delete — see `docs/relations.md` |
| `Relationship 'x' not found` on a relation URL | Used the relation's alias in the URL | The `:relation` segment is the relation KEY from `schema.relations` |

## Known API gaps (do not fight these)

- **Comma-in-value filters are inexpressible**: `,` is the `IN` separator with no
  escape — `?name=a,b` always means `IN (a, b)`. Filter on another field instead.
- **`many_to_many` linking does not resolve external IDs**: for targets with external
  identity (UUID_V5), pass the internal UUID (from a read/list of the target), not the
  external value.
- **Sibling `has_many` relations can mix** when two source specs use the same relation
  key against the same target — use distinct relation key names per source spec.
- **Nulling the last item of a keyword map 400s** — see the removal grammar caveat in
  `docs/specifications.md`.
- **A relation's backing-property alias is set once, at relation creation** — changing
  `relations.<k>.alias` later re-aligns it on current deployments; older ones don't.

Fixed upstream — expect these only on older deployments:

- A patch touching one relation used to 400 over untouched sibling relations, and
  `targetId`-only relations were rejected at create.
- A patch carrying the spec's own `name` used to collide with its own slug.
  Sending `name` unchanged is now accepted.
