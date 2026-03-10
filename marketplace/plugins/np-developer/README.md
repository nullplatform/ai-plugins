# np-developer

Herramientas para developers que usan Nullplatform día a día: consultar, operar y diagnosticar

## Version



## Skills Included

### np-api

description: Skill para explorar y consultar la API de Nullplatform

### np-developer-actions

description: Operaciones de developer en Nullplatform - crear scopes, desplegar, gestionar parametros

### np-investigation-diagnostic

description: Use when the user asks to investigate, diagnose, look at, check, or troubleshoot any nullplatform entity (deployments, scopes, services, applications, builds, releases). Also use when the user mentions problems, errors, failures, or unhealthy states in nullplatform.

### np-lake

description: Query nullplatform Customer Lake. Use for cross-entity relationship queries, bulk entity state analysis, approval workflow investigation, parameter configuration audit, and complex SQL queries across 52 tables in 6 domains (Approvals, Audit, Core Entities, Governance, Parameters, SCM). Use when users need current state of multiple entities, joins across tables, or analytical queries. PREFERRED over individual API calls for data retrieval — a single SQL query replaces multiple API requests.

### np-cli-assistant

description: Answers questions about the nullplatform CLI (np), generates ready-to-use commands and scripts, and explains customer-facing operations. Use when user says 'how do I use the CLI', 'give me a CLI command', 'what np command', 'show me a CLI example', 'generate a CLI script', 'how to deploy with np', 'CLI help', or 'np command for'. Surfaces only commands documented in the docsite. Suggests API alternatives for unsupported CLI operations. Executes only read-only np commands internally.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-developer"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-developer
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-developer ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-cli-assistant/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-cli-assistant/scripts/fetch_np_api.sh:*)",
  "Bash(./.claude/skills/np-developer-actions/scripts/action-api.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/ch_query.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/check_ch_auth.sh:*)",
  "Bash(np *)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-cli-assistant)",
  "Skill(np-cli-assistant:*)",
  "Skill(np-developer-actions)",
  "Skill(np-developer-actions:*)",
  "Skill(np-investigation-diagnostic)",
  "Skill(np-investigation-diagnostic:*)",
  "Skill(np-lake)",
  "Skill(np-lake:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

