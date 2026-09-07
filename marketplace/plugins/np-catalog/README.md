# np-catalog

Manage the nullplatform catalog: entity specifications, entity instances, relations, search/facets, interceptors/events, custom actions and authorization

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-catalog

description: The nullplatform catalog — building it and reading it. Building — specifications, instances (entities), relations (belongs_to, has_one, has_many, many_to_many), interceptors, events, custom actions, authorization, modeling an org's data as a graph, ingesting repos, docs, runbooks or services into a knowledge base, semantic fields and embeddings. Reading — any question answerable from records already in the catalog — analysing, reporting on, counting, comparing, auditing or explaining deployments, releases, services, applications, incidents or documents. Covers "give me the deployment analysis", "what shipped last month", "what changed across our services", "how many X by Y", "is this field trustworthy". Use it whenever a question could be answered from catalog data, even if the user never says "catalog", never names the API, and only asks for an analysis, summary or report. Also use when a spec change or ingest misbehaves. Requires NP_TOKEN or NP_API_KEY (same auth as np-api).

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-catalog"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-catalog
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-catalog ~/.claude/plugins/
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
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-catalog)",
  "Skill(np-catalog:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

