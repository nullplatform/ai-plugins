# np-service-craft

Tools for developing nullplatform services

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-service-guide

description: Use when the user asks about creating, understanding, or working with nullplatform services. This is the entry point for all service development tasks — it provides the architecture overview and routes to specialized skills for specs, scripts, terraform, and testing.

### np-service-specs

description: Use when working with nullplatform service spec files — service-spec.json.tpl, link specs (connect.json.tpl), values.yaml, attribute schemas, export configuration, and spec authoring conventions.

### np-service-workflows

description: Use when writing or modifying nullplatform service workflows and scripts — workflow YAML structure, build_context scripts, do_tofu, entrypoints, write_outputs scripts, and execution conventions.

### np-service-craft

description: This skill should be used when the user asks to "manage services", "list services", "register a service", "test a service", "modify a service", "resend service notification", or needs to orchestrate the full nullplatform service lifecycle — creation, Terraform registration, and testing.

### np-service-creator

description: This skill should be used when the user asks to "register a service in terraform", "create service_definition module", "create agent binding", "configure terraform for services", or needs to work with terraform modules for nullplatform service registration and agent association.

### np-agent-local-setup

description: This skill should be used when the user asks to "run agent locally", "setup local agent", "install np-agent", "test service locally", "start local agent", "configure local testing environment", or needs to set up a nullplatform controlplane agent on their machine for local development and testing of services or scopes.

### np-notification-manager

description: This skill should be used when the user asks to "create a notification channel", "debug notifications", "resend a notification", "check channel configuration", "inspect notification delivery", or needs to manage nullplatform notification channels, agent routing, and test notification delivery.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-service-craft"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-service-craft
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-service-craft ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-service-craft/scripts/resend_notification.sh:*)",
  "Skill(np-agent-local-setup)",
  "Skill(np-agent-local-setup:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-notification-manager)",
  "Skill(np-notification-manager:*)",
  "Skill(np-service-craft)",
  "Skill(np-service-craft:*)",
  "Skill(np-service-creator)",
  "Skill(np-service-creator:*)",
  "Skill(np-service-guide)",
  "Skill(np-service-guide:*)",
  "Skill(np-service-specs)",
  "Skill(np-service-specs:*)",
  "Skill(np-service-workflows)",
  "Skill(np-service-workflows:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

