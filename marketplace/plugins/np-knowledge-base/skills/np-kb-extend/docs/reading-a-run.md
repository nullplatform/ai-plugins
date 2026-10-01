# Reading a run: `summary.json` and the diagnosis table

Every mode returns `summary` (the parsed `summary.json`), `progress_log` (`[n]` milestones),
`bundle`, `findings`, `facets`, and for focus `book_patch`.

| Field | What it says |
|---|---|
| `external_tools.declared / rejected / warnings` | which tools the agent saw and why one was rejected (no `read_only`, secret in `fixed_inputs`, schema not read; "exposed with free inputs" is not an error) |
| `external_tool_calls` | how many times it used them |
| `instructions_chars` | instruction text that arrived (0 = no applicable instruction, or its author is not curator/product) |
| `contract.facets / finding_categories / rejected` | what the org declared and which declaration was rejected (reason in the "contract" milestone) |
| `agent_facets.entries / merged_by_key / dropped / partial / schema_invalid / undeclared` | the merge: `merged_by_key` dedup; `dropped` no verified anchors; `partial` some anchor unverified (facet `IA`); `schema_invalid` / `undeclared` stopped by the contract |
| `verification.facts_verified / edges_verified / findings_verified / external_sources / external_sources_unreachable` | what passed the verifier; unreachable = tool down or no `resolves` |
| `unverified` | items that did NOT get in: `unjudged`, `verifier_did_not_run`, `no_tool_for_scheme`, `external_source_unreachable` |
| `write.facetas.fusionadas` | (delta / focus) facets merged into the existing one instead of replacing it |
| `write.facetas_nodos.nodos / aristas / rechazadas` | nodes and edges derived through `node`; `rechazadas` = a curated edge left as a suggestion |
| `write.findings.creados / existentes / resueltos / recategorizados` | `recategorizados` = undeclared category → `catalog-findings` |
| focus: `scope` | `subsystems` with `hits`, `claims_touched / claims_total`, `facets_to_produce`, `rationale` (why the scope is what it is) |
| focus: `tracks.grouping / groups` | how the subsystems were grouped into tracks |
| focus: `book_patch.replaces / appends / anchors_outside_verified / error` | the sections replaced or appended; `error` when the writer failed (facets, edges and findings were written anyway) |
| `recommendation` | `delta is enough` / `deep-dive` (the wrapper dispatches full) / `focus applied` |

## "No section patched" vs "writer failed"

- `book_patch.sections` empty and the progress log says "the writer found no section to add or change": neither facts nor facet entries justified one. Check `agent_facets.entries` and `verification`.
- `book_patch.error` present: the writer call failed (`finish_reason`, usage and body head inside). Re-run; the rest of the run was written.
- The book is `human:curated`: nothing patched, a suggestion carries the sections (→ Ver `/np-kb-curate`).
