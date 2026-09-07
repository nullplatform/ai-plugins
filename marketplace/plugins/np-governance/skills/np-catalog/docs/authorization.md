# Authorization block

The spec's `schema.authorization` is THE policy document for the specification and
its instances. **If the block does not say it, it is not permitted** — there is no
ambient baseline (the platform keeps only spec creation, role membership, and the
non-overridable admin floor). "Open to everyone" is an explicit `{"type": "*"}` grant.

## Shape

```json
{
  "authorization": {
    "specification": {
      "grants": [
        { "principals": [{"type": "role", "id": 12}], "actions": ["write"] }
      ]
    },
    "entities": {
      "grants": [
        { "principals": [{"type": "*"}], "actions": ["read", "list"] },
        { "principals": [{"type": "user", "id": 55}], "actions": ["create", "write", "delete", "action:reboot"] },
        { "principals": [{"type": "role", "id": 7}], "actions": ["write"], "on": ["/annotations"] }
      ],
      "denials": [
        { "on": ["/secrets"], "deny": ["read", "write"], "except": [{"type": "role", "id": 12}] }
      ]
    }
  }
}
```

Two planes, same grammar:

| Plane | Governs | Action vocabulary |
|-------|---------|-------------------|
| `specification` | this spec document | `read`, `write`, `delete`, `*` |
| `entities` | the instances | `create`, `read`, `write`, `delete`, `list`, `action:<slug>`, `*` |

Per plane (at least one of the two):

- **`grants` ADD** access: `principals` × `actions` × optional `on` (JSON-pointer
  field scopes; omitted `on` = the whole document). `*` actions are only valid
  without `on`. A grant of `write` with no `on` on the specification plane is what
  "owner" means.
- **`denials` SUBTRACT**: `on` pointers × `deny` sides (`read`|`write`) × optional
  `except` (principals exempted; must carry ids, no `*`). Denials bind every
  admitted caller regardless of how they were admitted.

Principals: `{"type": "user"|"role", "id": <int>}` or `{"type": "*"}`.

## Cold start: omitted planes get a materialized default

The no-ambient-baseline rule holds for what is STORED — but at **create**, any
plane you omit is materialized as "org-readable, creator-owned" and written into
the block (auditable, one edit from anything else):

```json
{ "grants": [ { "principals": [{"type": "*"}], "actions": ["read", "list"] },
              { "principals": [{"type": "user", "id": <creator>}], "actions": ["*"] } ] }
```

(the specification plane gets the same shape with `["read"]` / `["*"]`). A plane
you DO declare is stored verbatim — including one that locks you out. So omit
the block entirely for sane defaults; declare it only to say something specific.

## Limits & validation

- Caps per plane: 50 grants, 25 denials; per grant/denial: 25 principals,
  25 actions, 10 `on` pointers, 25 `except` principals.
- `on` pointers must be real field pointers (`/status`, `/profile/contact`) — a bare
  `/` is rejected; the root is expressed by omitting `on`.
- A **scoped** grant (one with `on`) may carry only pointer-scopable actions —
  `entities` plane: `create`/`read`/`write`; `specification` plane: `read`/`write`. A delegate can
  structurally never `delete` or hold `*`.
- **Retention guard**: an update may not strand the spec — removing the last
  unscoped specification-plane write grant 400s with "a specification cannot be
  left with no unscoped write grant; replace it instead".
- Unknown keys anywhere in the block are REJECTED (not stripped) — typos fail loudly.

## Practical notes

- **The block only narrows**: the platform (main-auth-z) must first grant the caller
  the verb (`entity:read`, `entity-specification:write`, ...) at the resource's NRN —
  no grant in the block admits a caller the platform refused.
- Query surfaces are gated too: a filter, sort, facet, or `query` touching a denied
  read pointer → 403 naming the field.
- `list` and `read` are separate: a spec can let callers enumerate summaries without
  opening every field, or read-by-id without appearing in `/search`.
- Field-scoped grants (`on`) compose with denials: effective access =
  union(grants) − union(denials), evaluated per pointer subtree.
- Custom actions need their own `action:<slug>` grant (or `*`).
- Updating only `authorization` is a normal schema merge-patch — but WITHIN the
  block, `grants`/`denials` are ARRAYS, so they replace wholesale: send the full
  new array for the plane you touch, and `"authorization": {"entities": null}` to
  drop a plane.
- Cross-tenant sharing = a grant naming the foreign principal on your spec; there is
  no other path (besides the platform admin floor).
