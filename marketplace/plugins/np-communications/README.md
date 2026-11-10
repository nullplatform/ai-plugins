# np-communications

Operate Communications through the public API or the CLI: inbox rules (write, validate, dry-run, test, activate), emitting invoked inbox rules from workflows or CI, announcements and banners, and troubleshooting who gets which notification

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-communications

description: Operate nullplatform Communications (formerly the Notification Center) through the public API under /communications or the np communications CLI. Use when the user mentions the dashboard bell or inbox, inbox rules or custom notification types (write, validate, test, turn off, reset a built-in), emitting a notification to people from CI or a workflow, announcements and banners (publish, schedule, close), inbox settings or notification preferences, Slack delivery destinations or email notifications, or why someone did or did not get a notification. Does NOT cover agent notification channels under /notification/channel, which route platform events to agents, webhooks or CI runners (use /np-notification-manager).

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-communications"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-communications
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-communications ~/.claude/plugins/
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
  "Skill(np-communications)",
  "Skill(np-communications:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

