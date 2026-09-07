# Search & Query Dialect

Two surfaces share one dialect:

- `GET /instances/:slug` — typed list query (filters, sort, facets, `query`)
- `GET /search` — cross-type search over every specification the caller may list

Both serve from a read index that can trail writes by a moment (reads by id never lag).

## Filters

`?field=value`, with an optional operator suffix `field:op=value`. Fields are
**aliases**, nested paths use dots (`profile.department`), and the field MUST carry
`"index": ["filter"]` in the spec (else 400).

| Operator | Meaning | Field type |
|----------|---------|-----------|
| (none) / `eq` | equals; comma list = `IN` | any |
| `ne` | not equals | any |
| `gt` `gte` `lt` `lte` | comparison | numeric, timestamp |
| `range` | `field:range=min,max` (exactly 2 values) | numeric, timestamp |
| `contains` / `contains_cs` | substring (ci / cs) | text |
| `starts_with` / `starts_with_cs` | prefix | text |
| `ends_with` / `ends_with_cs` | suffix | text |
| `is_null` | `field:is_null=true\|false` — presence check | any |

```bash
catalog-api.sh GET '/instances/service?status=active,degraded&replicas:gte=3&service_name:contains=bill'
```

- Comma always splits into an `IN` list — a literal comma inside a value is
  inexpressible (known gap). `true`/`false`/numerics are coerced.
- `id=<value>` works and accepts external identity values (UUID_V5 specs).
- `created_at`/`updated_at` (or their aliases) filter as timestamps:
  `?created_at:gte=2026-08-01T00:00:00Z`.
- Wrong operator/type pairs 400 with a clear message.

## Full-text: `query`

`?query=<term>` (alias `q`) is a **case-insensitive substring match** over the
instance's summary — the concatenation of all fields indexed `fulltext` (so
`query=bill` matches `billing-batch`). Combine freely with filters.

## Sort

`?sort=field:asc,other:desc` — order defaults to `asc` per entry, overall default is
`created_at:desc`. Sortable fields are declared indexed fields plus the system
timestamps; anything else 400s.

## Paging

`?limit=N` (default 30, max 100 — above that the API rejects with
`limit must not exceed 100`) and `?offset=N`.
Responses carry `{ paging: { offset, limit }, results }` and NO total; iterate until
`results.length < limit`.

## Sparse fieldsets: `include` / `exclude`

Trim response payloads to the fields you need — one of the two, not both:

```bash
catalog-api.sh GET '/instances/service?include=service_name,status,annotations.team'
catalog-api.sh GET '/instances/service/<id>?exclude=raw_config'
```

They also work on every FIXED-schema read surface — and that is where they save the
most: every specification row embeds a full JSON Schema, which you rarely need.

```bash
catalog-api.sh GET '/specifications?include=name,slug'        # catalog inventory, no schemas
catalog-api.sh GET '/specifications/<id>?exclude=schema'      # spec metadata without the schema
catalog-api.sh GET '/specifications/<id>/events?include=action,url'
catalog-api.sh GET '/actions/<slug>/<id>/history?include=action,status'
```

- Selectors are comma-separated **dot-paths on aliases** — the same dialect filters
  use. A selector the resource does not declare is a 400 naming what you sent.
- Works on typed lists, single reads, `/search` (spec-prefix the paths there),
  specifications, events/interceptors, and action-execution history.
- `id` always survives an `include` unasked (identity floor); excluding it is a 400.
- Nesting reaches exactly as deep as declared structure (`include=retry.max_attempts`
  on an event works). Free-form objects are whole-field only: `exclude=schema` is
  fine, `include=schema.properties` is a 400 — take or drop the whole document.
- A field the authorization policy redacts is silently absent even when included —
  its omission is not an error.
- **Spell the params exactly.** On `/instances` a mistyped param becomes a filter and
  400s, but on the fixed-schema routes an unknown query param (`excludes=`, `inclde=`)
  is currently **silently ignored** and the full payload comes back — a response that
  looks honest but ignored your selector. If a response is unexpectedly wide, check
  the spelling before anything else.

## Facets

Request value-count aggregations with `?facets=status,annotations.team`:

```json
"facets": { "status": [ { "value": "active", "count": 12 }, ... ] }
```

- Fields need `"index": ["facet"]`.
- **Facets aggregate over the FILTERED result set** — `?severity=high&facets=severity`
  counts only the high rows. For a full breakdown alongside filtered results, make a
  second unfiltered call, or filter the facet itself with the `facet:` form below.
- An open object (`additionalProperties: true`) indexed `facet` can be requested by
  its own name (`facets=annotations`) — discovered keys come back dynamically.
- **Facet filters** narrow ONE facet's aggregation without narrowing the results:
  `?facet:status=active` or with an operator `?facet:price:gte=100`. The facet must
  also be in `facets=` and the field must be filter-indexed.

## Cross-type `/search`

```bash
catalog-api.sh GET '/search?query=billing&limit=20'
catalog-api.sh GET '/search?type=service,incident&query=payments'
catalog-api.sh GET '/search?service.status=active'
```

- `type` (or `slug`): comma list restricting which specifications are searched;
  omitted = all the caller can list.
- `tenant_id` (or `tenantId`): target a tenant other than the token's — mainly for
  searching global specifications from another tenant's context. Authorization still
  decides admission per specification; this only selects whose catalog is asked.
- Field filters are **spec-prefixed**: `service.status=active` (the un-prefixed form
  belongs to typed lists).
- Results: `{ "results": [ { "nrn": ..., "entity": "<specSlug>", "data": { ...alias-keyed... } } ] }`.
- Facets are unreliable across types — prefer typed lists when you need counts.
- Authorization prunes silently: specifications that don't admit the caller are
  dropped, not errored. An empty result may mean "no access", not "no data".

## Relevance mode

`sort=relevance` repurposes `query` from a `summary ILIKE` filter into a ranking query over
prose stored in `index: ["semantic"]` fields, and adds `score` + `matches[]` to each
result. `POST /search` accepts the identical query object as a body. Both are covered
in `semantic-retrieval.md` — read it before reaching for `sort=relevance`, because a
prose field indexed `fulltext` produces no chunks and the mode returns nothing for it
without erroring.
