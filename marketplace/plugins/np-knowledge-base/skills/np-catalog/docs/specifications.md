# Specifications

A specification is the schema-driven definition of an instance type: its properties,
validations, relations, custom actions, handlers, and authorization policy. Instances
are instances of exactly one specification.

## CRUD

```bash
# List (paginated; schema is included per result)
catalog-api.sh GET '/specifications?limit=100'

# Create — slug is DERIVED from name (lowercased, dashed); capture id + slug from the response
catalog-api.sh POST /specifications '{
  "name": "Service",
  "description": "A deployable service",
  "schema": { ... }
}'

# Read / Update / Soft-delete
catalog-api.sh GET    /specifications/<id>
catalog-api.sh PATCH  /specifications/<id> '{"schema": { ...minimal diff... }}'
catalog-api.sh DELETE /specifications/<id>
```

`tenant_id` comes from the token. Specifications with `tenant_id: "*"` are global —
they appear in every tenant's queries and their instances are shared.

**The stored schema is normalized, not verbatim.** On create the API injects:
an implicit `id` property (`primaryKey`/`autoGenerate` true) unless you declared a
primary key; `created_at`/`updated_at`/`deleted_at` properties (sort-indexed);
a default `alias` mirroring each property key; `relations: {}`;
`additionalProperties: false`; and — when you omit `authorization` (or a plane) —
a materialized default policy: **org-readable/listable by every admitted caller,
creator-owned** (see `authorization.md`). Declare the block only to say something
different; expect reads of the spec to return this normalized form (some
normalization — e.g. the system `id` alias — may only appear after the first
update; don't diff schemas across writes expecting byte stability).

## Updating `schema` is an RFC 7386 MERGE PATCH — the #1 footgun

The API merges the `schema` you send into the stored schema:

- **Omitted key → stored value is PRESERVED.**
- **`"key": null` → stored value is REMOVED.**
- Objects merge recursively; arrays and scalars replace wholesale.

So to remove the property `owner` and the action `reboot`:

```json
{ "schema": { "properties": { "owner": null }, "actions": { "reboot": null } } }
```

NEVER re-send a fully composed schema when your intent includes a removal — the
removed key simply survives. Workflow: `GET` the spec, compute the minimal diff
(changed keys + explicit nulls for removals), `PATCH` that. `name`/`description`
at the top level replace normally (sending `"description": ""` clears it).

**Destructive changes require an explicit opt-in (verified behavior)**: a patch
that removes a property or a relation is rejected with a 400 enumerating the
breaking changes (`schema update contains 1 breaking change: property 'owner'
removed (stored values will be deleted)`) until you re-send it with
`"allow_destructive": true` at the **body root**, next to `schema`:

```json
{ "schema": { "properties": { "owner": null } }, "allow_destructive": true }
```

Removing an action needs no flag — nothing stored is lost. Treat the flag as a
per-request confirmation, not a default: include it only on patches whose
destruction you have already decided.

**Removal grammar caveat (verified behavior)**: a per-item null inside a keyword
map (`actions`, `relations`) only works while OTHER items remain. Nulling the LAST
item leaves an empty map that fails keyword validation with a 400
(`keyword "actions" value is invalid ... data must be object`). To remove the last
item, null the whole section instead: `{"schema": {"actions": null}}` — the key
then VANISHES from the stored schema (reads return no `actions` key, not `{}`).
Plain `properties` entries have no such restriction.

## Schema shape

The `schema` is a JSON Schema object (`type: "object"`, `properties`, `required`,
nested objects/arrays all work) extended with catalog keywords:

```json
{
  "type": "object",
  "properties": {
    "name":   { "type": "string", "alias": "service_name", "index": ["fulltext", "filter", "sort"] },
    "status": { "type": "string", "enum": ["active", "inactive"], "index": ["filter", "facet"] },
    "annotations": { "type": "object", "additionalProperties": true, "index": ["filter", "facet"] }
  },
  "required": ["name"],
  "relations": { ... },
  "requiredRelations": [ ... ],
  "actions": { ... },
  "authorization": { ... }
}
```

### Custom keywords

| Keyword | On | Meaning |
|---------|----|---------|
| `alias` | any property | snake_case API-facing name used in ALL payloads instead of the internal key. Must be unique per JSON object level; relation aliases share the same namespace |
| `index` | scalar/object/array property | array of `fulltext` (feeds `query`), `filter`, `sort`, `facet`, `semantic`. Un-indexed fields cannot be filtered, sorted, or faceted. On an object/array it applies to the leaves under it; on an open object (`additionalProperties: true`) it makes discovered keys dynamically filterable/facetable. **`semantic`** opts a `string` field into chunking + embedding for `sort=relevance` retrieval — a different mechanism from `fulltext`, with its own caps; read `semantic-retrieval.md` before using it |
| `primaryKey` | one property max | Marks the identity field — see Identity strategies below |
| `autoGenerate` | the `primaryKey` property | `true` = API generates the id; `false` = caller supplies the identity value |
| `nrn` | string property | Marks the property as a Nullplatform Resource Name (`organization=1:account=2` style); anchors authorization scoping |
| `relations` | schema root | Relation declarations — read `relations.md` before touching |
| `requiredRelations` | schema root | Array of relation keys that must be linked at instance create |
| `actions` | schema root | Custom operations — see `automation.md` |
| `authorization` | schema root | Policy document — see `authorization.md` |

System fields (`id`, `created_at`, `updated_at`) are aliasable too: declare the
property (e.g. `id: { "type": "string", "primaryKey": true, "autoGenerate": true, "alias": "service_id" }`)
and responses use the alias.

## Identity strategies

| Aspect | UUID_V4 (auto) | UUID_V5 (external) |
|--------|----------------|--------------------|
| Declaration | none (default), or `primaryKey: true, autoGenerate: true` | `primaryKey: true, autoGenerate: false` |
| Who provides the id | API (random v4). Sending an id at create → 400 | Caller, at create (required). Stored as a deterministic UUID v5 of the value |
| URL addressing | `/instances/:slug/<uuid>` | `/instances/:slug/<externalValue>` — the API converts transparently |
| Response | system uuid as `id` (or its alias) | the user's original value under the PK field; internal uuid is NOT exposed |

Pick UUID_V5 when instances mirror an external system (repos, ARNs, employee ids):
addressing and dedup then key off the external value, and re-creates are idempotent
per value. Otherwise let the API generate v4 ids.

## Validation limits (schema authoring)

- Max ~2000 schema nodes, max pointer depth 64, max regex `pattern` length 1000 —
  the API 400s beyond these.
- Enum values and aliases must be snake_case.
- An alias may not shadow a reserved query-param name (`offset`, `limit`, `sort`,
  `facets`, `facet`, `include`, `exclude`, `expand`, `upsert`, `q`, `query`) —
  the collision is rejected at spec write.
- Every key in `required` must exist in `properties`; every key in
  `requiredRelations` must exist in `relations`.
- Unknown keys inside `authorization` are rejected (not stripped) — typos fail loudly.

## Relation target resolution at create/update

A relation may reference its target by `target` (the target spec's **slug**) or
`targetId` (its uuid). On create, prefer `target` slugs — the API resolves and
stores `targetId`. Stored specs return relations with `targetId` (slug re-added on
read). Targets must exist for the same tenant (or be global) or the spec is
rejected with 400 when `strict` is true (the default).
