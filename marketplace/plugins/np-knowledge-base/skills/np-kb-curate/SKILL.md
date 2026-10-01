---
name: np-kb-curate
description: Keep the organizational knowledge base healthy through the `np-catalog` MCP server — merge duplicate nodes, enrich bare core/infra pages, handle a contradiction with human-curated content, retract or repoint edges, review the suggestions a focus re-analysis files against a curated book, manage the suggestion cycle, delete instances safely, or explain why a DELETE seemed to succeed while the data persists (tombstones, partitions, id conventions).
---

# np-kb-curate

Skill to **maintain** the organizational knowledge base with the write tools of the
`np-catalog` MCP server. Reading is → Ver `/np-kb-navigate`; lore is → Ver `/np-kb-lore`.

## Critical Rules

1. **Actor `curador:<name>` writes land as `human:curated`**: the pipeline and the agents NEVER overwrite them. An overwrite attempt is blocked, audited and turned into a suggestion. Curators overwrite curators (peers).
2. **An agent writes `IA` / `IA:deep` / `IA:verified`** by how it obtained the fact: `IA:verified` only if verified against the source, never if inferred. `observed:*` and `joined` belong to the pipeline.
3. **Contradiction with curated content → `create_suggestion`**, carrying the exact statement contradicted, the `file:line` evidence with commit/date, and the proposed wording. Never overwrite.
4. **Never delete knowledge: retract.** `retract_edge` leaves `config_status: "refuted"`, a visible tombstone. Only a `full` deep-dive retracts edges it no longer sees; delta and focus write partial bundles and never retract nor resolve.
5. **Every write goes through the MCP** so the actor travels with it. No raw `curl` against the catalog.

## Runbooks

| Task | Steps |
|---|---|
| Merge duplicate nodes | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-curate/docs/runbooks.md § Merging |
| Enrich a bare core/infra node | same doc § Enriching |
| Review a focus book patch on a curated book | same doc § Focus patches on curated books |
| Suggestions (HITL cycle) | same doc § Suggestions |
| Delete instances without losing data | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-curate/docs/delete-pitfalls.md |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| DELETE returns 404 but the item is still there | two id conventions coexist: `slug~name` and `slug~name~p0` | GET both forms first; GET again after deleting |
| Delete refused with the API key | the API key has no delete grant nor spec access | a personal `NP_TOKEN` (1 h) |
| Child docs/facets vanished from a page after deleting the component | delete does not cascade; children keep a null FK | list what hangs from a component BEFORE deleting |
| A re-added edge does not show up | the retract tombstone wins | re-add with an explicit `config_status` |
| A new field is not stored (200, no data) | fields not declared in the spec are dropped silently | check with GET after the first write; extend the spec (→ Ver `/np-catalog`) |
| An integrity sweep reports missing items while a run writes | pagination is unstable under concurrent writes | confirm each suspect with a direct GET |
| A focus run "did not patch the book" of an app | the book is `human:curated`: the sink filed a suggestion instead | `list_suggestions` → apply or reject (docs/runbooks.md) |
