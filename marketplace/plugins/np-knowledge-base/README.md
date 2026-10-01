# np-knowledge-base

Navigate, curate, extend and re-analyse the organizational knowledge base built on the nullplatform catalog: answer questions with provenance through the np-catalog MCP server, keep it healthy (merges, suggestions, tombstones), register cross-cutting lore (norms, knowledge, investigation instructions), plug external sources in (tools, contract, instruction) and run full / delta / focus analyses on the engine (catalog-ia-analysis, catalog-refocus)

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-workflow

description: Build, publish, run, and debug workflows on the Nullplatform workflow engine via REST API. Use when the user asks to "create a workflow", "publish a workflow", "list workflow plugins", "trigger a webhook", "check an execution", "manage workflow secrets", "scaffold a workflow YAML", or any workflow-engine task. Requires NP_TOKEN or NP_API_KEY (same as np-api); NP_WORKFLOW_URL only for self-hosted engines (defaults to api.nullplatform.com).

### np-catalog

description: The nullplatform catalog — building it and reading it. Building — specifications, instances (entities), relations (belongs_to, has_one, has_many, many_to_many), interceptors, events, custom actions, authorization, modeling an org's data as a graph, ingesting repos, docs, runbooks or services into a knowledge base, semantic fields and embeddings. Reading — any question answerable from records already in the catalog — analysing, reporting on, counting, comparing, auditing or explaining deployments, releases, services, applications, incidents or documents. Covers "give me the deployment analysis", "what shipped last month", "what changed across our services", "how many X by Y", "is this field trustworthy". Use it whenever a question could be answered from catalog data, even if the user never says "catalog", never names the API, and only asks for an analysis, summary or report. Also use when a spec change or ingest misbehaves. Requires NP_TOKEN or NP_API_KEY (same auth as np-api).

### np-kb-navigate

description: Answer questions from the organizational knowledge base (the nullplatform catalog built by the KB pipeline) through the nullplatform MCP (`np_kb_read`, `np_kb_propose`) or the `np-catalog` MCP server — "what is X", "who uses X", "what breaks if X goes down", "how does X work", "which docs describe X", "which apps does this doc page affect", "how do I connect to X", "what findings does X have" — and how to behave when catalog_search returns empty, a node looks bare, a count contradicts another source, or a fact must be cited with its provenance.

### np-kb-curate

description: Keep the organizational knowledge base healthy through the `np-catalog` MCP server — merge duplicate nodes, enrich bare core/infra pages, handle a contradiction with human-curated content, retract or repoint edges, review the suggestions a focus re-analysis files against a curated book, manage the suggestion cycle, delete instances safely, or explain why a DELETE seemed to succeed while the data persists (tombstones, partitions, id conventions).

### np-kb-lore

description: Register or consult cross-cutting organizational knowledge (lore) in the knowledge base — norms (how things SHOULD be), knowledge (how they ARE) and instructions (how to investigate them) — through the `np-catalog` MCP `set_norm` tool; decide between set_norm, upsert_facet, add_edge or create_suggestion; choose the owner level and an applies_to selector; distill norm candidates from aggregate data; and run a focus re-analysis so the catalog incorporates the new lore.

### np-kb-extend

description: Extend and re-analyse the organizational knowledge base — plug an external source into the catalog (a wiki, a CMDB, a documentation site, monitors, runbooks, any read-only API) by declaring an engine workflow as an agent tool, writing the org contract (facets with JSON Schema, keys, node derivation, finding categories) and an investigation instruction; launch a deep-dive, a delta or a focus (re-analyze with an intent after a new tool, lore, facet or question); choose focus vs delta vs deep-dive; fan a focus out over the org (catalog-refocus); and diagnose why a facet, node, edge, finding or book section did not appear (rejected declaration, undeclared facet, schema failure, unverified anchors, recategorized finding, empty book patch).

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-knowledge-base"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-knowledge-base
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-knowledge-base ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-context.sh:*)",
  "Bash(./.claude/skills/np-catalog/scripts/catalog-api.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/execution.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/ping.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/plugins.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/publish.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/run.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/scaffold.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/trigger.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/workflow-api.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/workflows.sh:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-catalog)",
  "Skill(np-catalog:*)",
  "Skill(np-kb-curate)",
  "Skill(np-kb-curate:*)",
  "Skill(np-kb-extend)",
  "Skill(np-kb-extend:*)",
  "Skill(np-kb-lore)",
  "Skill(np-kb-lore:*)",
  "Skill(np-kb-navigate)",
  "Skill(np-kb-navigate:*)",
  "Skill(np-workflow)",
  "Skill(np-workflow:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

