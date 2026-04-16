# np-governance

Governance Action Items: query and operate on action items, categories and suggestions; build new detector/executor agents with a guided wizard

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-lake

description: Query nullplatform Customer Lake. Use for cross-entity relationship queries, bulk entity state analysis, approval workflow investigation, parameter configuration audit, auth/RBAC audits, service & link inventory, and complex SQL queries across 62 tables in 8 domains (Approvals, Audit, Auth, Core Entities, Governance, Parameters, SCM, Services). Use when users need current state of multiple entities, joins across tables, or analytical queries. PREFERRED over individual API calls for data retrieval — a single SQL query replaces multiple API requests.

### np-governance-action-items

description: Operate on Nullplatform Governance Action Items - list, create, update action items, manage categories and suggestions. Includes patterns for idempotency, reconciliation, and executor agents. Use when the user wants to query, create, modify or analyze action items, categories, or suggestions, or build agent flows around them.

### np-governance-agent-builder

description: Guided wizard to generate new Nullplatform Governance Action Item agents (detectors, executors, or both) inside the user's project. Use when the user says "create a governance agent", "new action item agent", "build a detector for X", "generar executor", or invokes /np-governance-create-action-item-agent.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-governance"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-governance
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-governance ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-governance-action-items/scripts/*.sh:*)",
  "Bash(./.claude/skills/np-governance-agent-builder/scripts/*.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/ch_query.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/check_ch_auth.sh:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-governance-action-items)",
  "Skill(np-governance-action-items:*)",
  "Skill(np-governance-agent-builder)",
  "Skill(np-governance-agent-builder:*)",
  "Skill(np-lake)",
  "Skill(np-lake:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

