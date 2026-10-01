# Instances

An instance is one record attached to a specification, addressed as
`/instances/<specSlug>/<id>`. The body of every request and response is the instance's
**data keyed by aliases** — there is no `{ "data": ... }` envelope.

## CRUD

```bash
# Create — body is the instance data itself, alias-keyed
catalog-api.sh POST /instances/service '{
  "service_name": "billing",
  "status": "active",
  "annotations": { "team": "payments" }
}'

# Read (immediately consistent after writes)
catalog-api.sh GET /instances/service/<id>

# Update — partial: send only the fields to change
catalog-api.sh PATCH /instances/service/<id> '{"status": "inactive"}'

# Upsert — PATCH with ?upsert=true creates the instance when it does not exist
catalog-api.sh PATCH '/instances/service/<id>?upsert=true' '{"service_name": "billing", "status": "active"}'

# Soft delete
catalog-api.sh DELETE /instances/service/<id>
```

## Rules of the data contract

- **Keys are aliases.** If the spec says `{"name": {"alias": "service_name"}}`, you
  write and read `service_name`. Fields without an alias use their property key.
- **Validation is the spec's JSON Schema.** Required properties, enums, types,
  patterns — a violation is a 400 naming the pointer. Unknown keys are stripped
  silently, so a typo'd field just disappears: verify the
  response echoes what you meant to write.
- **`id` handling depends on the identity strategy** (see `specifications.md`):
  - auto (UUID_V4): never send an id — 400 if you do. The response carries the
    generated uuid under `id` (or its alias).
  - external (UUID_V5): the identity is required in the payload and is also how you
    address the instance in URLs (`/instances/repo/github.com%2Forg%2Frepo` — URL-encode).
    **Write it under the PK's alias, like every other field** (the literal internal
    key `id` is also accepted; both spellings derive the same identity). Reads
    return it under the alias:
    ```bash
    # spec: { "id": { "primaryKey": true, "autoGenerate": false, "alias": "repo_key" } }
    catalog-api.sh POST /instances/repo '{"repo_key": "github.com/org/repo", "stars": 12}'
    catalog-api.sh GET  /instances/repo/github.com%2Forg%2Frepo
    # -> { "repo_key": "github.com/org/repo", "stars": 12, ... }
    ```
    `entity ID is required when 'autogenerate' is set to false` means the payload
    carried the identity under NEITHER spelling.
- **Nested updates are NOT deep-merged** (verified): PATCH replaces each top-level
  field you send wholesale — `PATCH {"meta": {"b": 9}}` on `meta: {"a": 1, "b": 2}`
  leaves `meta: {"b": 9}`. To change one key inside an object field, send the whole
  object. `null` is stored as a literal value, NOT a removal (unlike spec-schema
  patches) — to drop a key from an object field, re-send the object without it.
- **`requiredRelations`** must be satisfiable at create: create via the relation
  endpoint from the parent (see `relations.md`) or include the inline FK field.
- **Inline FK fields** (`belongs_to`/`has_one`) may be set directly in data (the
  relation's alias holds the target's id) — the API syncs the relation row. Prefer
  the relation endpoints; they also validate the target exists.

## Interceptors fire on create/update/delete

If the spec has interceptors for the action, they run BEFORE the mutation and can
reject it (their 4xx/5xx becomes your error) or merge extra fields into the data.
Events fire after, asynchronously, and never affect the response. See `automation.md`
when a mutation fails with an upstream-looking error.

## Listing

`GET /instances/:slug` is the list/query endpoint — filters, sort,
facets, `query`, paging. Read `search.md` for the full dialect. Two consistency notes:

- A just-written instance may take a moment to appear in lists/facets — they serve
  from a read index that trails writes slightly; `GET` by id never lags.
- List responses are `{ "paging": {"offset": N, "limit": N}, "results": [...], "facets": {...} }`
  with no total count — page until a short page comes back.
