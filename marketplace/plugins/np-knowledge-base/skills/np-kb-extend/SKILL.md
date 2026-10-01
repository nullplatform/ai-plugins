---
name: np-kb-extend
description: Extend and re-analyse the organizational knowledge base — plug an external source into the catalog (a wiki, a CMDB, a documentation site, monitors, runbooks, any read-only API) by declaring an engine workflow as an agent tool, writing the org contract (facets with JSON Schema, keys, node derivation, finding categories) and an investigation instruction; launch a deep-dive, a delta or a focus (re-analyze with an intent after a new tool, lore, facet or question); choose focus vs delta vs deep-dive; fan a focus out over the org (catalog-refocus); and diagnose why a facet, node, edge, finding or book section did not appear (rejected declaration, undeclared facet, schema failure, unverified anchors, recategorized finding, empty book patch).
allowed-tools: AskUserQuestion
---

# np-kb-extend

Skill to **extend** the knowledge base (new sources, new facets, new categories) and to
**re-analyse** applications with the engine's knowledge-base node. Reading is → Ver
`/np-kb-navigate`; lore and instructions are → Ver `/np-kb-lore`; the engine (publish, run,
config entries) is → Ver `/np-workflow`.

## Critical Rules

1. **One node, three modes.** The engine's `np-kb-analyze` node runs `mode: full | delta | focus` through the workflow `catalog-ia-analysis` (hosted `wf_Ktg0o5dvG1zd`); `catalog-ia-codex` (`wf_BzjGzVJxM6RS`, full), `catalog-ia-delta` (`wf_iUVoGXo7PL4-`) and `catalog-ia-focus` (`wf_C4c0OxHp6yth`) are thin wrappers keeping their ids. The node does the pre-reads itself (app, lore, instructions, tools, contract, lake, inventory) and the deployment picks the image: **no YAML names an image, a command or a model**, and the customer never talks to the sandbox provider.
2. **The contract decides what gets in.** The agent can only emit facets declared in `vars.CATALOG_CONTRACT` (JSON Schema per entry, identity `key`, optional `node`) and finding categories listed there; anything else is dropped or recategorized with a warning.
3. **Tools are read-only engine workflows** declared in `vars.CATALOG_TOOLS` with `read_only: true`; secrets live in the tool's own YAML as `${{ secrets.X }}`, **never** in the declaration.
4. **Provenance is set by verification**: every anchor verified → `IA:verified`; any unverified → `IA` (per entry); none → the entry does not get in. External anchors (`docs:`, `wiki:`, `cmdb:`) are re-read through the tool that declares `resolves: {scheme, ref_input}`.
5. **Partial bundles never retract.** Delta and focus merge facets by `key`, add edges and findings, append `recent-changes`, patch the book by section; only `full` rewrites and retracts. `human:curated` content is never overwritten (a suggestion is filed).
6. **Everything entering the catalog is English.** Always send **every** workflow input, even as `""`.

## Which mode, when

| The trigger is… | Mode | Why |
|---|---|---|
| a deploy changed the code | **delta** (`catalog-ia-delta`) | reacts to the diff, judges the affected claims, escalates to `full` above `deep_dive_ratio` |
| the org's context changed: a new tool, lore, contract facet, a question — code unchanged | **focus** (`catalog-ia-focus` / `catalog-refocus`) | catalog as base; only what the intent asks is added or refreshed; cheap enough for the whole org |
| the app has no book, or its book is old or wrong, or the intent asks `depth: deep` | **full** (`catalog-ia-codex`) | rebuilds everything: book, runbook, facets, edges, findings, seal |

## Commands (all through `/np-workflow run <id> --input k=v …`)

| Task | How |
|---|---|
| Plug a source in (tool → declaration → contract → instruction → run) | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-extend/docs/plug-a-source.md |
| Re-analyse with an intent, one app or the whole org | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-extend/docs/focus.md (or the command `/np-kb-focus`) |
| Read a run's `summary.json`, diagnose a missing facet / finding / section | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-extend/docs/reading-a-run.md |
| Real example (nullplatform's public documentation): tools, contract, instruction | @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-extend/docs/examples/README.md |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| the tool does not appear in the agent's kit | declaration without `read_only: true`, missing `workflowId`, duplicate name, or a `fixed_inputs` key that looks like a secret | `summary.json → external_tools.rejected`; fix the declaration in `vars.CATALOG_TOOLS` |
| the facet does not appear | undeclared in the contract, entries fail the schema, or no anchor verified | `summary.json → agent_facets.{undeclared, schema_invalid, dropped}` |
| the facet is `IA`, not `IA:verified` | some entry has unverified anchors (`partial`) | `get_facet` shows per-entry provenance; check the tool declares `resolves` for the scheme |
| the finding landed in `catalog-findings` | its category is not in `finding_categories` | `write.findings.recategorizados`; declare the category (an action item's category cannot change afterwards) |
| an external fact stayed unverified | no tool declares `resolves` for that scheme, or the tool failed | `unverified` (`no_tool_for_scheme` / `external_source_unreachable`) |
| `CONFIG_INVALID_AT_RUNTIME — env.X: must be string` / `focus.kind` | an input did not travel in the execute | send every input, even `""` |
| `Sub-workflow alias not found … /live` | the hosted engine only carries the `latest` alias and `sub-workflow` does not fall back | every sub-workflow reference uses `alias: latest` |
| `NP_KB_TEMPLATE_UNCONFIGURED` | the engine deployment has no `NP_KB_E2B_TEMPLATE` | operator of the engine placement (nullplatform on the hosted engine) |
| the focus patched nothing | neither facts nor facet entries justified a section; or the book is `human:curated` (suggestion filed) | `book_patch.sections` / `book_patch.error`; → Ver `/np-kb-curate` |
| `get_component <prefix>…` shows `edges_in: []` | slug with `/` | use `who_consumes` |
