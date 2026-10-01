# Surfaces: the `np-catalog` MCP server and the hosted workflows

## The MCP server

The knowledge base ships an MCP server (`np-catalog`). Register it in the workspace `.mcp.json`
(the server command is provided by the knowledge-base installation; `NP_API_KEY` reads, and
`NP_CATALOG_ACTOR` travels with every write):

```json
{
  "mcpServers": {
    "np-catalog": {
      "command": "node",
      "args": ["<path-to-the-knowledge-base-mcp>/server.mjs"],
      "env": { "NP_API_KEY": "...", "NP_CATALOG_ACTOR": "your-name" }
    }
  }
}
```

Restart Claude Code and check with `/mcp` that `np-catalog` shows up. An actor `curador:<name>`
writes as `human:curated`, which the pipeline never overwrites.

### Read tools

| Tool | What it answers |
|---|---|
| `catalog_search` | natural-language semantic search over docs and facets; the entry point |
| `list_components` | nodes by namespace, account, text or kind |
| `get_component` | a component's card: identity, hierarchy, criticality, facets and docs index, `edges_out`, applicable lore and instructions |
| `get_facet` | the full content of one facet (partitions reassembled) |
| `get_doc` | a complete markdown document (`overview`, `book`, `runbook`, `recent-changes`, …) |
| `get_hierarchy` / `org_index` | the org tree with counts; aggregated indexes computed live from the edges |
| `get_norms` | effective norms of a component (org → account → namespace → app) |
| `get_instructions` | effective investigation instructions (lore `nature: instruction`, curator/product only) |
| `who_consumes` | inverse index: who breaks if I move this (edges with `via` and evidence) |
| `blast_radius` | multi-hop impact radius (`direction: inbound | outbound`, `depth`) |
| `plan_work` | briefing for a feature or bug: norms + context + graph in one call |
| `deploy_checklist` | a component's effective norms evaluated before a deploy |
| `list_findings` | findings (governance action items) with `categoria`, severity, status, evidence |
| `list_questions` | open questions the pipeline asked the organization, with evidence |
| `list_suggestions` | open suggestions about the catalog |

### Write tools (every write carries the actor)

`create_node`, `upsert_facet`, `upsert_doc`, `add_edge`, `retract_edge` (tombstone, never a delete), `repoint_edge`, `set_norm` (lore: `norm | knowledge | instruction`), `create_suggestion`, `ask_question`, `answer_question`. → Ver `/np-kb-curate` and `/np-kb-lore`.

## The hosted workflows

The same reads and writes exist as engine workflows for agents that have no MCP: `catalog-query`
(`wf_1Qv9G_ZdAAmH`) and `catalog-update` (`wf_LR7qzZ2PWfCq`). Run them with → Ver `/np-workflow`
(`run.sh <id> --input command=<tool> --input args='<json>'`). Analyses are launched the same
way (→ Ver `/np-kb-extend`).

## Credentials

- `NP_API_KEY` (organization API key with catalog grants): every read and the pipeline's writes; never expires. Same auth as `/np-api`.
- `NP_TOKEN` (personal, 1 h): needed only for spec changes and deletes. Expired = opaque 401 → `unset NP_TOKEN`.
