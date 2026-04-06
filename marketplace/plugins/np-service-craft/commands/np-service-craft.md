---
name: np-service-craft
description: Create, register, test, and manage nullplatform services end-to-end
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
argument-hint: [create|register|test|modify|list|resend-notification|examples] [service-name]
---

# NullPlatform Service Wizard

Load full documentation:

@.claude/skills/np-service-craft/docs/service-structure.md
@.claude/skills/np-service-craft/docs/create-service.md
@.claude/skills/np-service-craft/docs/register-service.md
@.claude/skills/np-service-craft/docs/test-environment.md
@.claude/skills/np-service-craft/docs/execution-flow.md
@.claude/skills/np-service-craft/docs/troubleshooting.md

## Usage

- `/np-service-craft` (no args) — List services and their registration status
- `/np-service-craft create` — Create a new service (from template or guided)
- `/np-service-craft register <name>` — Generate terraform to register service in nullplatform
- `/np-service-craft test <name>` — Setup local agent and test E2E
- `/np-service-craft modify <name>` — Modify an existing service
- `/np-service-craft resend-notification <id> [channel_id]` — Resend notification for retesting
- `/np-service-craft examples` — Show available example templates

## Instructions

Parse `$ARGUMENTS` to determine what to do:

1. **No arguments**: Scan `services/` for service-spec.json.tpl files, show table with registration status.
2. **"create"**: Follow `create-service.md`. Clone reference repo (`nullplatform/services`) for examples or guided new service.
3. **"register \<name\>"**: Follow `register-service.md`. Generate terraform modules and bindings.
4. **"test \<name\>"**: Follow `test-environment.md`. Prerequisite: `/np-agent-local-setup`.
5. **"modify \<name\>"**: List service files, ask what to modify, assist with changes.
6. **"resend-notification \<id\> [channel_id]"**: Execute resend script.
7. **"examples"**: Clone reference repo (`nullplatform/services`), list available examples with specs.

## Critical Rules

- Never use `curl` directly against `api.nullplatform.com`. Always use `/np-api fetch-api`.
- Confirm before any mutating operation (terraform apply, np service patch, etc.).
- Use `AskUserQuestion` for all user-facing questions.
- For channel operations, delegate to `/np-notification-manager`.
- Reference specialized skills for conventions: `np-service-specs`, `np-service-workflows`, `np-service-creator`.

### Lazy-loaded docs (read only when needed)

| Doc | When to load |
|-----|-------------|
| `docs/link-provisioning.md` | When working with links (create link, permissions, credentials) |
| `docs/execution-flow.md` | When debugging agent execution chain |
