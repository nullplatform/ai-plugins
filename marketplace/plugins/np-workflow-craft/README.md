# np-workflow-craft

Build, publish, run, and debug workflows on the Nullplatform workflow engine via REST

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-workflow

description: Build, publish, run, and debug workflows on the Nullplatform workflow engine via REST API. Use when the user asks to "create a workflow", "publish a workflow", "list workflow plugins", "trigger a webhook", "check an execution", "manage workflow secrets", "scaffold a workflow YAML", or any workflow-engine task. Requires NP_TOKEN or NP_API_KEY (same as np-api); NP_WORKFLOW_URL only for self-hosted engines (defaults to api.nullplatform.com).

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-workflow-craft"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-workflow-craft
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-workflow-craft ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
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
  "Skill(np-workflow)",
  "Skill(np-workflow:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

