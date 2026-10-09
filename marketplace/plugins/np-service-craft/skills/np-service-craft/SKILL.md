---
name: np-service-craft
description: This skill should be used when the user asks to "manage services", "list services", "register a service", "test a service", "modify a service", "resend service notification", or needs to orchestrate the full nullplatform service lifecycle — creation, Terraform registration, and testing.
allowed-tools: Bash(.claude/skills/np-service-craft/scripts/*.sh), AskUserQuestion
---

# Nullplatform Service Wizard

Orchestrator to create, list, register, and test Nullplatform services.

## Critical Rules

1. **Never use `curl` directly** against `api.nullplatform.com`. Always use `/np-api fetch-api`.
2. **Confirm before any mutating operation**. Explain WHAT and WHY, then ask to proceed.
3. **Use `AskUserQuestion`** for all user-facing questions.
4. **Services ship as an OCI image, packaged.** `service_definition` publishes a package
   revision pinning the specs and the image; the agent association emits a package-exec
   channel with `worker_orchestrator = true`. Packaging is a **mode of those modules**, not a
   replacement — both layers still apply, in order. The legacy git-clone flow still works for
   services that have not moved.
5. **The package model itself lives in `/np-package-builder`** — worker-bridge image
   contract, agent/worker architecture, `allowedRegistries`, artifact forms, the
   `np package` CLI, the SDK, legacy migration. Reference it; never restate it here.
6. **Reference specialized skills** for detailed conventions:
   - `np-package-builder` — the package model, worker-bridge image, agent workers
   - `np-service-specs` — spec file authoring (service-spec.json.tpl, link specs, values.yaml)
   - `np-service-workflows` — workflow YAML structure, build_context, entrypoints
   - `np-service-creator` — terraform registration patterns
   - `np-agent-local-setup` — local agent setup for testing
   - `np-notification-manager` — channel operations

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md

## Reference Documentation

@.claude/skills/np-service-craft/docs/service-structure.md
@.claude/skills/np-service-craft/docs/create-service.md
@.claude/skills/np-service-craft/docs/register-service.md
@.claude/skills/np-service-craft/docs/test-environment.md
@.claude/skills/np-service-craft/docs/execution-flow.md
@.claude/skills/np-service-craft/docs/troubleshooting.md

### Registering a service as a package

Service-specific; the model behind it is `/np-package-builder`.

@${CLAUDE_PLUGIN_ROOT}/skills/np-service-creator/docs/packaged-service.md

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
2. For each: read the spec, find its `service_definition` module in `nullplatform/main.tf`
   and whether it carries a `package` block, check its association in
   `nullplatform-bindings/main.tf` for `worker_orchestrator = true`, and check whether its
   slug appears in the agent's `worker_orchestrated_packages`
3. Show table: Service | Slug | Category | Package version | Worker channel | Worker wired
4. A service whose `service_definition` has no `package` block is on the legacy git-clone
   flow — mark it as legacy in the table

## Command: create

See `docs/create-service.md`. Two paths:
- **Path A**: From reference example (resolve the repo in the scope/service catalog, clone it at its ref, copy, adapt)
- **Path B**: New service (guided discovery, delegates to `np-service-specs` and `np-service-workflows` for conventions)

## Command: modify <name>

1. Verify `services/<name>/` exists
2. List files with their roles
3. AskUserQuestion: what to modify (spec, link, deployment, workflows, entrypoints, values)
4. Read and assist with the modification

## Command: register <name>

See `docs/register-service.md`. Tags, builds and pushes the image, adds the `package` block
to `service_definition`, sets `worker_orchestrator` on the association, and wires the worker.

## Command: test <name>

See `docs/test-environment.md`. Prerequisite: `/np-agent-local-setup`.

## Command: resend-notification <id> [channel_id]

```bash
.claude/skills/np-service-craft/scripts/resend_notification.sh <notification_id> [channel_id]
```

Find notification IDs: `/np-api fetch-api "/notification?nrn=<nrn>&source=service"`
Check result: `/np-api fetch-api "/notification/<id>/result"`

## Command: examples

List the base services from the scope/service catalog
(`${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`), then clone the repo of
the one the user picks and summarize its specs. `nullplatform/services` is an index — cloning it
yields no implementations.
