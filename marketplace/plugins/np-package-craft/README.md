# np-package-craft

Build, run, and publish nullplatform packages (scope / service / simple) with the np CLI: init, dev, test, build, run (local agent), publish, and artifact release metadata

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-package-builder

description: Use when the user works with nullplatform PACKAGES or the control-plane runtime around them — "np package init/build/run/publish", "create a scope/service/simple package", "scaffold a plugin", "run a local agent", "publish a package", "register an artifact with a changelog", "np artifact login/create", "how does the agent run workers", "worker bridge image", "migrate a scope to packages", "pin a worker image", "allowedRegistries", "publish a package with terraform/tofu modules", "artifact lookup by tag". Covers the CLI workflow, the agent+workers architecture and its validations, the plugin SDK, the worker-bridge image contract, old-model migration, and the tofu modules.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-package-craft"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-package-craft
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-package-craft ~/.claude/plugins/
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
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-package-builder)",
  "Skill(np-package-builder:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

