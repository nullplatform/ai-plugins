# np-troubleshooting

Investigation and diagnosis of nullplatform issues

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-investigation-diagnostic

description: Use when the user asks to investigate, diagnose, look at, check, or troubleshoot any nullplatform entity (deployments, scopes, services, applications, builds, releases). Also use when the user mentions problems, errors, failures, or unhealthy states in nullplatform.

### np-lake

description: Query nullplatform Customer Lake. Use for cross-entity relationship queries, bulk entity state analysis, approval workflow investigation, parameter configuration audit, auth/RBAC audits, service & link inventory, and complex SQL queries across 64 tables in 8 domains (Approvals, Audit, Auth, Core Entities, Governance, Parameters, SCM, Services). Use when users need current state of multiple entities, joins across tables, or analytical queries. PREFERRED over individual API calls for data retrieval — a single SQL query replaces multiple API requests.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-troubleshooting"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-troubleshooting
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-troubleshooting ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/ch_query.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/check_ch_auth.sh:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
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

