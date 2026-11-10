---
name: np-service-craft
description: Create, register, test, and manage nullplatform services end-to-end
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
argument-hint: [create|register|test|modify|list|resend-notification|examples] [service-name]
---

# NullPlatform Service Wizard

Load full documentation:

@.claude/skills/np-service-craft/docs/service-structure.md
@.claude/skills/np-service-craft/docs/execution-modes.md
@.claude/skills/np-service-craft/docs/create-service.md
@.claude/skills/np-service-craft/docs/register-service.md
@.claude/skills/np-service-craft/docs/register-service-ci.md
@.claude/skills/np-service-craft/docs/test-environment.md
@.claude/skills/np-service-craft/docs/execution-flow.md
@.claude/skills/np-service-craft/docs/troubleshooting.md

## Usage

- `/np-service-craft` (no args) — List services and their registration status
- `/np-service-craft create` — Create a new service (from template or guided)
- `/np-service-craft register <name>` — Register the service (agent mode: package + agent channel; CI mode: spec + github channel)
- `/np-service-craft test <name>` — Test E2E (agent mode: local agent; CI mode: captured context + real dispatch)
- `/np-service-craft modify <name>` — Modify an existing service
- `/np-service-craft resend-notification <id> [channel_id]` — Resend notification for retesting
- `/np-service-craft examples` — Show available example templates

## Instructions

Parse `$ARGUMENTS` to determine what to do:

1. **No arguments**: Scan `services/` for service-spec.json.tpl files, show table with registration status.
2. **"create"**: Ask the execution mode (`execution-modes.md`), then follow `create-service.md`. Find a reference service in the docs inventory (see the `np-rules` scope/service catalog) or guided new service.
3. **"register \<name\>"**: Resolve the mode, then follow `register-service.md` (agent: terraform modules and bindings) or `register-service-ci.md` (CI: spec + github channel filtered by slug).
4. **"test \<name\>"**: Follow `test-environment.md`. Agent mode prerequisite: `/np-agent-local-setup`. CI mode: no agent.
5. **"modify \<name\>"**: List service files, ask what to modify, assist with changes.
6. **"resend-notification \<id\> [channel_id]"**: Execute resend script.
7. **"examples"**: List the sample services from the docs inventory (see the `np-rules` scope/service catalog), clone the one the user picks at its resolved ref and summarize its specs.

## Critical Rules

- Never use `curl` directly against `api.nullplatform.com`. Always use `/np-api fetch-api`.
- Confirm before any mutating operation (terraform apply, np service patch, etc.).
- Use `AskUserQuestion` for all user-facing questions.
- For channel operations, delegate to `/np-notification-manager` — including the `github` channel in CI mode.
- A service without a `package` block is not legacy until its channel type is known; never run both modes against one spec.
- Reference specialized skills for conventions: `np-service-specs`, `np-service-workflows`, `np-service-creator`.

### Lazy-loaded docs (read only when needed)

| Doc | When to load |
|-----|-------------|
| `docs/link-provisioning.md` | When working with links (create link, permissions, credentials) |
| `docs/execution-flow.md` | When debugging the execution chain (agent or CI) |
