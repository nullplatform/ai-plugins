---
name: np-kb-lore
description: Register or consult cross-cutting organizational knowledge (lore) in the knowledge base — norms (how things SHOULD be), knowledge (how they ARE) and instructions (how to investigate them) — through the `np-catalog` MCP `set_norm` tool; decide between set_norm, upsert_facet, add_edge or create_suggestion; choose the owner level and an applies_to selector; distill norm candidates from aggregate data; and run a focus re-analysis so the catalog incorporates the new lore.
---

# np-kb-lore

Skill for the **upper ground** of the knowledge base: knowledge that belongs to no particular
component, defined once at a level of the hierarchy and projected downwards.

## Critical Rules

1. **Lore is projected, never copied**: defined once (`owner` = where it is defined and how far it reaches) and shown in `get_component`, `plan_work`, `get_norms`, `deploy_checklist` of every component it reaches, resolved at query time.
2. **Three natures**: `norm` (prescriptive, violation = finding, may carry `checks`), `knowledge` (descriptive), `instruction` (how to investigate: where the docs live, which tool to use, what to compare). **`instruction` only from an actor `curador:<name>` or `product`**; an agent gets `blocked: "instruction"` and proposes it with `create_suggestion`.
3. **Curated lore is never overwritten**: what a `curador:*` defined blocks an agent's update and turns it into a suggestion.
4. **The `applies_to` selector has CLOSED dimensions** (`kinds`, `uses_lib`, `slug_prefix`, `has_facet`, all AND). There is no `slugs` list: inventing one projects the lore to nobody.
5. **Registering lore does not re-analyse anything.** Finish with a **focus** over the affected apps (→ Ver `/np-kb-extend`, `catalog-refocus` with `focus_kind: lore`, `focus_refs: <key>`).
6. **English** for everything entering the catalog.

## Where each thing goes

| The fact is… | Write |
|---|---|
| about ONE component | a **facet** on it (`upsert_facet`), not lore |
| an observed dependency with point evidence | an **edge** (`add_edge`); lore never replaces edges |
| cross-cutting and descriptive (how it IS) | `set_norm` with `nature: "knowledge"` |
| how to investigate (external sources, tools, comparisons) | `set_norm` with `nature: "instruction"` (curator/product), else `create_suggestion` |
| cross-cutting and prescriptive (how it SHOULD be) | `set_norm` with `nature: "norm"`, with machine-checkable `checks` if any |
| contradicting or impoverishing something `human:curated` | `create_suggestion` pointing at the existing lore |

Before creating: `list_components {kind: "lore"}` + `get_component {ref: "lore:<candidate>"}` — it may already exist with more nuance.

## Reference

- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-lore/docs/set-norm.md — the exact `set_norm` contract, the `applies_to` dimensions, the `lore:<key>` page, versioning
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-lore/docs/instructions.md — instructions vs the org contract, the three trust blocks the agent sees, writing a good instruction
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-lore/docs/distilling.md — distilling org-level norm candidates from aggregate data, and the approval flow

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| The norm projects to nobody | `applies_to` uses a dimension that does not exist (`slugs`, `components`) | use `kinds` / `uses_lib` / `slug_prefix` / `has_facet`; or record the fact as a facet on the provider (findable via `who_consumes`) |
| `set_norm` returns `blocked: "instruction"` | the actor is not `curador:*` / `product` | propose it with `create_suggestion`; a curator registers it |
| The lore exists but the deep-dive ignored it | `get_instructions` only counts curator/product authors; `instructions_chars: 0` in the run summary | re-register as curator |
| The instruction asks for a facet the run drops | the facet or category is not in the org contract | name facets and categories exactly as the contract declares them (→ Ver `/np-kb-extend`) |
| I registered the lore and the catalog did not change | lore is projected, not applied | run a focus with `kind: lore` over the affected apps |
