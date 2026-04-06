---
name: np-service-craft
description: This skill should be used when the user asks to "manage services", "list services", "register a service", "test a service", "modify a service", "resend service notification", or needs to orchestrate the full nullplatform service lifecycle — creation, Terraform registration, and testing.
allowed-tools: Bash(.claude/skills/np-service-craft/scripts/*.sh), AskUserQuestion
---

# Nullplatform Service Wizard

Orquestador para crear, listar, registrar y testear servicios de Nullplatform.

## Critical Rules

1. **Never use `curl` directly** against `api.nullplatform.com`. Always use `/np-api fetch-api`.
2. **Confirm before any mutating operation**. Explain WHAT and WHY, then ask to proceed.
3. **Use `AskUserQuestion`** for all user-facing questions.
4. **Reference specialized skills** for detailed conventions:
   - `np-service-specs` — spec file authoring (service-spec.json.tpl, link specs, values.yaml)
   - `np-service-workflows` — workflow YAML structure, build_context, entrypoints
   - `np-service-creator` — terraform registration patterns
   - `np-agent-local-setup` — local agent setup for testing
   - `np-notification-manager` — channel operations

## Reference Documentation

@.claude/skills/np-service-craft/docs/service-structure.md
@.claude/skills/np-service-craft/docs/create-service.md
@.claude/skills/np-service-craft/docs/register-service.md
@.claude/skills/np-service-craft/docs/test-environment.md
@.claude/skills/np-service-craft/docs/execution-flow.md
@.claude/skills/np-service-craft/docs/troubleshooting.md

### Lazy-loaded docs (read only when needed)

| Doc | When to load |
|-----|-------------|
| `docs/link-provisioning.md` | When working with links (create link, permissions, credentials) |

## Available Commands

| Command | Description |
|---------|-------------|
| `/np-service-craft` | List services and their registration status |
| `/np-service-craft create` | Create service (from template or guided new) |
| `/np-service-craft modify <name>` | Modify existing service |
| `/np-service-craft register <name>` | Generate terraform to register service |
| `/np-service-craft test <name>` | Setup local testing with agent |
| `/np-service-craft resend-notification <id> [channel_id]` | Resend notification for retesting |
| `/np-service-craft examples` | Show available example templates |

## Command: List Services (no args)

1. Scan `services/` for `specs/service-spec.json.tpl`
2. For each: read spec, check registration in `nullplatform/main.tf`, check binding in `nullplatform-bindings/main.tf`
3. Show table: Service | Slug | Category | Provider | Registered | Binding

## Command: create

See `docs/create-service.md`. Two paths:
- **Path A**: From reference example (clone `nullplatform/services` repo, copy, adapt)
- **Path B**: New service (guided discovery, delegates to `np-service-specs` and `np-service-workflows` for conventions)

## Command: modify <name>

1. Verify `services/<name>/` exists
2. List files with their roles
3. AskUserQuestion: what to modify (spec, link, deployment, workflows, entrypoints, values)
4. Read and assist with the modification

## Command: register <name>

See `docs/register-service.md`. Generates terraform modules for service_definition + agent_association.

## Command: test <name>

See `docs/test-environment.md`. Prerequisite: `/np-agent-local-setup`.

## Command: resend-notification <id> [channel_id]

```bash
.claude/skills/np-service-craft/scripts/resend_notification.sh <notification_id> [channel_id]
```

Find notification IDs: `/np-api fetch-api "/notification?nrn=<nrn>&source=service"`
Check result: `/np-api fetch-api "/notification/<id>/result"`

## Command: examples

Clone reference repo (`nullplatform/services`), list available examples with spec summary.
