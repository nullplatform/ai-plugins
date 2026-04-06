---
name: np-notification-manager
description: Manage nullplatform notification channels — list, create, inspect, debug channels and resend notifications
allowed-tools: Read, Glob, Grep, Bash
argument-hint: [list|create|inspect|notifications|resend|debug] [id]
---

# NullPlatform Notification Manager

Manage notification channels and notifications.

## Usage

- `/np-notification-manager list` — List active channels for an NRN
- `/np-notification-manager create` — Create a notification channel (guided)
- `/np-notification-manager inspect <channel-id>` — View channel configuration
- `/np-notification-manager notifications <nrn>` — View recent notifications
- `/np-notification-manager resend <notification-id> [channel-id]` — Resend a notification
- `/np-notification-manager debug <channel-id>` — Diagnose delivery problems

## Instructions

Parse `$ARGUMENTS` to determine which sub-command to execute, then follow the corresponding flow in the `np-notification-manager` skill.

Load the full skill reference for detailed command flows:

@${CLAUDE_PLUGIN_ROOT}/skills/np-notification-manager/SKILL.md

## Critical Rules

- Always use `/np-api fetch-api` for API access. Never `curl` directly.
- Confirm before creating or modifying channels.
- Validate selector tags match agent configuration before creating channels.
