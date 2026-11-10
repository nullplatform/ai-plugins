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
4. **Decide the execution mode first** (`docs/execution-modes.md`). The channel decides who runs
   an action, and nothing below `np service-action exec` changes between modes:
   - **Agent mode** — services ship as an OCI image, packaged. `service_definition` publishes a
     package revision pinning the specs and the image; the agent association emits a
     package-exec channel with `worker_orchestrator = true`. Packaging is a **mode of those
     modules**, not a replacement — both layers still apply, in order. The legacy git-clone
     flow still works for services that have not moved.
   - **CI mode** — a `github` (or `gitlab`) channel dispatches the action to a workflow in a
     repository the client owns; the runner checks the code out and runs it. No image, no
     package, no agent. Registration is spec + channel (`docs/register-service-ci.md`).
   A service with no `package` block is **not** legacy until you have checked which channel
   filters on its spec. Never run both modes against the same spec.
5. **The package model itself lives in `/np-package-builder`** — worker-bridge image
   contract, agent/worker architecture, `allowedRegistries`, artifact forms, the
   `np package` CLI, the SDK, legacy migration. Reference it; never restate it here.
6. **Reference specialized skills** for detailed conventions:
   - `np-package-builder` — the package model, worker-bridge image, agent workers
   - `np-service-specs` — spec file authoring (service-spec.json.tpl, link specs, values.yaml)
   - `np-service-workflows` — workflow YAML structure, build_context, entrypoints
   - `np-service-creator` — terraform registration patterns
   - `np-agent-local-setup` — local agent setup for testing
   - `np-notification-manager` — channel operations; owns the `github` channel flow
     (`docs/github-channel.md`) that CI mode relies on

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md

## Reference Documentation

@.claude/skills/np-service-craft/docs/service-structure.md
@.claude/skills/np-service-craft/docs/execution-modes.md
@.claude/skills/np-service-craft/docs/create-service.md
@.claude/skills/np-service-craft/docs/register-service.md
@.claude/skills/np-service-craft/docs/register-service-ci.md
@.claude/skills/np-service-craft/docs/test-environment.md
@.claude/skills/np-service-craft/docs/execution-flow.md
@.claude/skills/np-service-craft/docs/troubleshooting.md

### Registering a service as a package (agent mode)

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
| `/np-service-craft register <name>` | Register the service: package + agent channel, or spec + github channel |
| `/np-service-craft test <name>` | Local testing: with the agent, or with a captured context (CI mode) |
| `/np-service-craft resend-notification <id> [channel_id]` | Resend notification for retesting |
| `/np-service-craft examples` | Show available example templates |

## Command: List Services (no args)

1. Scan `services/` (or `<slug>/specs/` at the repo root) for `specs/service-spec.json.tpl`
2. For each: read the spec, find its `service_definition` module in `nullplatform/main.tf`
   and whether it carries a `package` block, check its association in
   `nullplatform-bindings/main.tf` for `worker_orchestrator = true`, and check whether its
   slug appears in the agent's `worker_orchestrated_packages`
3. For a service with **no** `package` block or **no** association, resolve its mode from
   the API before labelling it (`docs/execution-modes.md`, "Detecting the mode"): a `github`
   channel filtering on its slug or id means **CI mode**, an `exec` agent channel means
   legacy, no channel means not registered
4. Show table: Service | Slug | Category | Mode | Package version / `owner/repo@ref · workflow` | Worker wired
5. Mark **legacy** only a service whose channel is an `exec` agent channel

## Command: create

See `docs/create-service.md`. Ask the **execution mode** first (`docs/execution-modes.md`),
then two paths:
- **Path A**: From reference example (resolve the repo in the scope/service catalog, clone it at its ref, copy, adapt)
- **Path B**: New service (guided discovery, delegates to `np-service-specs` and `np-service-workflows` for conventions)

## Command: modify <name>

1. Verify `services/<name>/` exists
2. List files with their roles
3. AskUserQuestion: what to modify (spec, link, deployment, workflows, entrypoints, values)
4. Read and assist with the modification

## Command: register <name>

Resolve the mode first (`docs/execution-modes.md`: ask, or detect it from the NRN's channels).

- **Agent mode** — `docs/register-service.md`. Tags, builds and pushes the image, adds the
  `package` block to `service_definition`, sets `worker_orchestrator` on the association, and
  wires the worker.
- **CI mode** — `docs/register-service-ci.md`. Creates the spec, creates a `github` channel
  filtered by the spec **slug** (delegating to `/np-notification-manager` for the channel
  questions and validations), and checks the client's workflow handles the slug.

## Command: test <name>

See `docs/test-environment.md`. Agent mode: prerequisite `/np-agent-local-setup`. CI mode:
no agent — run the handler with a captured `NP_ACTION_CONTEXT`, then verify a real dispatch
with `gh run list`.

## Command: resend-notification <id> [channel_id]

```bash
.claude/skills/np-service-craft/scripts/resend_notification.sh <notification_id> [channel_id]
```

Find notification IDs: `/np-api fetch-api "/notification?nrn=<nrn>&source=service"`
Check result: `/np-api fetch-api "/notification/<id>/result"`

## Command: examples

List the sample services from the **Samples** table of the public docs' Sample services page (one row per service, with its `repo/path`), read as explained in
the catalog (`${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`), then clone the
repo of the one the user picks at its resolved ref and summarize its specs. Never clone
`nullplatform/services` for this — it is a legacy index.
