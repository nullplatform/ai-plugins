# `set_norm` — the exact contract

```json
{"owner": "org" | "<account|namespace>" | "<nrn>",
 "key": "stable-kebab-identity",
 "nature": "norm" | "knowledge" | "instruction",
 "applies_to": { "kinds": ["app"], "uses_lib": "np-api-js", "slug_prefix": "svc:postgres", "has_facet": "endpoint-authz" },
 "title": "one sentence", "body": "prose with file:line evidence, English",
 "checks": ["norm only: machine-checkable statements"]}
```

- `owner` = **where it is defined** and how far it reaches (the hierarchy is implicit: namespace lore never touches another account). Pick the level by the REAL scope of the fact, not by where you discovered it.
- Same `owner` + `key` = versioned upsert (history of 10 kept). There is no delete: retract beats delete; if really needed it is a curator operation.
- Every piece of lore IS a component: the page `lore:<key>` (kind `lore`) is created and synced automatically; long detail goes afterwards with `upsert_doc {component: "lore:<key>"}`; suggestions point at it. In `get_hierarchy`: `§` = norm, `◆` = knowledge, `▶` = instruction.
- Reading: `get_norms {component}` (norms and knowledge resolved through the chain), `get_instructions {ref}` (instructions), `get_component` (`applicable knowledge`, `instructions_applicable`), `plan_work`, `deploy_checklist` (only norms gate deploys).

## The `applies_to` selector — CLOSED dimensions

| Dimension | Example | Semantics |
|---|---|---|
| `kinds` | `["app", "service"]` | by component type |
| `uses_lib` | `"np-api-js"` | only components with an edge to that library |
| `slug_prefix` | `"svc:postgres"` | one family by identity |
| `has_facet` | `"endpoint-authz"` | only components carrying that facet |

All dimensions are AND, always within the owner's hierarchy. Without `applies_to` the lore applies
to the owner's whole level. If the set is "the consumers of X" and no dimension captures it:
record the fact as a facet on provider X (findable via `who_consumes`) and, if projection is
warranted, request the new dimension as a suggestion.

## After registering: make the catalog incorporate it

Lore is projected at query time; the books, facets and findings of the affected apps do not
change until a re-analysis runs. Use a **focus** (→ Ver `/np-kb-extend`): `catalog-refocus`
(`wf_xkhqycojQ-bd`) with `focus_kind: lore`, `focus_refs: <key>`, an `intent` such as "The org
adopted the norm <key>; check whether each application follows it and record violations as
findings", `applications` empty for every app with a book. The scope is mechanical (the book
claims sharing terms with the lore text, their subsystems first); ≈ 3 min and ~1.2M agent
tokens per app, against 10–15 min and 6–8M for a deep-dive.
