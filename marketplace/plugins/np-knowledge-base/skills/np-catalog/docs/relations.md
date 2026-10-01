# Relations

Relations are declared in the **source** specification's `schema.relations`, keyed by
an internal relation key:

```json
{
  "relations": {
    "application": { "type": "belongs_to", "target": "application", "alias": "application_id" },
    "builds":      { "type": "has_many",   "target": "build",       "alias": "builds" },
    "tags":        { "type": "many_to_many", "target": "tag",       "alias": "tags" }
  },
  "requiredRelations": ["application"]
}
```

Fields: `type` (required), `target` (slug) or `targetId` (uuid) — one required,
`alias`, `strict` (default true: target must resolve), `onDelete`
(`cascade`|`restrict`|`set_null`), `onUpdate` (`cascade`|`restrict`).
Note: `onDelete`/`onUpdate` cascades are declared but **not implemented yet** —
unlink manually before deleting a linked instance.

**Inline-FK types** (`belongs_to`, `has_one`) auto-create a backing property under the
relation's key carrying the target's id, sharing the relation's alias. That shared
alias is by design, not a collision — but it means the relation's alias must not
clash with any OTHER property alias at the same level. Changing the relation's alias
later re-aligns the backing property too, so the FK is always readable and writable
under the alias the spec declares (on older
deployments the property kept its original alias and reads silently served the FK
under the old key while writes accepted the new one).

## `target` vs `targetId` — slug in, id stored

Both address the relation's target, but they are an **input form** and a **storage
form**, not interchangeable synonyms:

| | `target` (slug) | `targetId` (uuid) |
|---|---|---|
| Role | authoring input | what is persisted |
| Unknown value | **creates a stub specification** for that slug | rejected (`targets a specification that does not exist`) |
| Stability | mutable — a rename moves the slug | stable |
| After resolution | dropped from the stored schema | kept |

Because the slug auto-creates a stub, it is the only way to declare a **forward
reference** — name a target that does not exist yet, then fill it in. An id cannot do
that.

Reads **synthesize** `target` back onto the response from the stored `targetId`, so a
`GET` hands you both keys even though only one is stored. Since relation objects
merge-patch recursively, a read-modify-write — or even a partial patch of one
attribute — sends both back. When both arrive, the stable id wins:

- slug resolves to the SAME spec → agreement, nothing to decide
- slug resolves to a DIFFERENT spec → `400 ... which are different specifications`
- slug resolves to nothing → treated as a stale echo; the id is kept and **no stub is
  created**

To re-point a relation deliberately, send the new `targetId`, or clear it with
`targetId: null` alongside the new slug. (On older deployments the slug won
silently, so a stale one re-pointed the relation or spawned a stub.)

## Choosing a type

| | `belongs_to` | `has_one` | `has_many` | `many_to_many` |
|---|---|---|---|---|
| Cardinality | N:1 (child → parent) | 1:1 | 1:N (parent → children) | M:N |
| FK lives on | source instance data | target instance data | target side (as belongs_to) | join rows only |
| `GET .../:relation` returns | single instance (404 if none) | single instance (404 if none) | paginated list | paginated list |
| `POST .../:relation` | creates target + links + sets FK on source | creates target + links + sets FK on target | creates target + links | **links existing only**: body `[{"id": "<targetId>"}]` |
| `DELETE .../:relatedId` | unlinks + clears FK + soft-deletes target | same | same | unlinks only (target survives) |
| Uniqueness enforced | 1 target per source | 1 target per source | none | no duplicate pairs |

`has_one`/`has_many` are stored internally as `belongs_to` from the target's
perspective — declaring Deployment `has_many` Builds means each Build carries the FK.

**Storage is shared, but TRAVERSAL is per-declaration.** A spec can only be
traversed through relation keys its OWN schema declares: a Build's `belongs_to`
gives you `GET /instances/build/:id/deployment`, but `GET /instances/deployment/:id/builds`
only exists once the Deployment spec declares `builds: has_many` itself. To walk
both directions, declare both sides. The two keys are independent names — and
create/delete through the parent's `has_many` endpoint still syncs the child's
inline `belongs_to` FK (set on link, nulled on unlink).

**Mutual references can't both be created up front** (strict target resolution):
create spec A without the relation → create spec B with its `belongs_to` A →
PATCH A with its `has_many` B. (`strict: false` on the relation is the alternative
when stub/forward references are acceptable.)

## Operating on relations

```bash
# Read the related side (shape depends on type — see table)
catalog-api.sh GET '/instances/deployment/<id>/builds?limit=100'

# Create-and-link a child (belongs_to / has_one / has_many): body is the NEW instance's data
catalog-api.sh POST /instances/deployment/<id>/builds '{"build_number": 42, "status": "ok"}'

# Link EXISTING instances (many_to_many only): array of ids
catalog-api.sh POST /instances/service/<id>/tags '[{"id": "<tagId>"}, {"id": "<tagId2>"}]'

# Read / update / unlink one related instance
catalog-api.sh GET    /instances/deployment/<id>/builds/<buildId>
catalog-api.sh PATCH  /instances/deployment/<id>/builds/<buildId> '{"status": "failed"}'
catalog-api.sh DELETE /instances/deployment/<id>/builds/<buildId>
```

- `:relation` in the URL is the relation's **key** as declared in
  `schema.relations` — NOT its alias (the alias names the inline FK field in instance
  data; using it in the URL returns "Relationship not found").
- IDs accept the external identity value for UUID_V5 targets everywhere EXCEPT
  `many_to_many` linking (known gap — pass the internal uuid there, obtained from a
  read/list of the target).
- The has_many list endpoint accepts the full query dialect (filters/sort/facets).

## Filtering by relation

`belongs_to` FKs are filterable when indexed: `GET '/instances/deployment?application_id=<appId>'`
converts external ids to internal uuids automatically.

## Pitfalls

- **Distinct relation keys per source spec**: two different source specs pointing at
  the same target with the SAME relation key can mix each other's children in
  inverse lookups (known gap). Name keys specifically (`incident_affected_service`,
  not `service`).
- **requiredRelations at create**: create children through the parent's relation
  endpoint, or include the inline FK value in the create payload.
- **Removing a relation from the schema does NOT remove its backing FK property**
  (verified): after `{"relations": {"key": null}}` (or nulling the section) the
  auto-created property survives as a plain field — null it under `properties` too
  if you want it gone.
- **Removing a `belongs_to` strands its inverse `has_many`** (verified): the
  parent's `has_many` traversal then 400s with "Reverse belongs_to relation not
  defined in target". Remove (or re-point) the parent's `has_many` in the same
  breath.
- **A relation's alias can be changed in place**, but its backing property is created
  once — on older deployments the two diverge silently and
  the only repair is to drop the relation *and* its backing property
  (`{"relations": {"k": null}, "properties": {"k": null}}`, nulling the whole
  `relations` section when it is the last entry) and recreate it with the alias you
  want. Check `schema.properties.<relationKey>.alias` matches
  `schema.relations.<relationKey>.alias` if a FK reads back `null`.
- Deleting a spec does not cascade to instances or relations — clean up instances first.
- **A spec referenced by another spec's relation cannot be deleted** (400 naming the
  referencing relation). For mutually referencing specs this deadlocks both deletes:
  first remove one side's relation (`{"schema": {"relations": {"k": null}},
  "allow_destructive": true}` — relation removal is a destructive change), then
  delete in dependency order.
