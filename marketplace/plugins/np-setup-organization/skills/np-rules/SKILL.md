---
name: np-rules
description: Shared rule and reference files consumed by other nullplatform skills via `@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/{rules,references}/*.md`. This skill is a dependency container, not a user-facing skill — other skills auto-load its files through `@` file inclusion. Do not invoke directly from user intent.
---

# np-rules — Shared Rule and Reference Files

This skill is a **dependency container**. It holds content that applies across multiple nullplatform skills, so the text lives in exactly one place and consumer skills reference it via `@` inclusion.

Two kinds of shared file, in two directories:

- **`rules/`** — normative blocks that go inline in a consumer's `## Critical Rules` section.
- **`references/`** — lookup data that consumers read while generating code.

## Available shared files

| File | Consumers | Purpose |
|------|-----------|---------|
| `rules/iac-rule.md` | `np-infrastructure-wizard`, `np-setup-orchestrator`, `np-nullplatform-wizard`, `np-nullplatform-bindings-wizard`, `np-scope-craft`, `np-service-craft`, `np-service-creator` | "Infrastructure changes only via IaC" — forbids cloud / TF-modeled entity mutation outside of Terraform code; lists allowed read-only operations; defines the carve-out for workflow-managed entities (scopes, deployments, parameters, etc.). |
| `references/scopes-services-catalog.md` | `np-infrastructure-wizard`, `np-nullplatform-wizard`, `np-nullplatform-bindings-wizard` (via `@`); `np-service-guide`, `np-service-craft`, `np-scope-guide`, `np-scope-craft` (read on demand) | Single source of truth for scope/service repos, refs, `service_path`, requirements module paths and IAM selectors. `nullplatform/services` is an index now, so the three setup layers need one catalog they all derive from. |

## How to consume a shared file from another skill

In the consumer's `SKILL.md`, add a single line where the content should appear:

```markdown
@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md
```

The `@` directive causes Claude Code to inline the file's content into context when the consumer skill is triggered (same semantics documented in the repo's `CLAUDE.md` under "Referencias a archivos y ejecución en skills y commands"). The included file starts with its own heading (`### Rule: ...` / `### Reference: ...`), so the consumer does not need to add one.

**When to use `@` and when to cite the path instead.** `@` inlines on every trigger of the consumer skill, so the token cost is paid whether the content is needed or not. Use `@` when the consumer needs the content in essentially every run (a rule that gates its behavior, a catalog it generates from). When the content is only needed in one branch of a longer flow, cite the path in prose and let it be read on demand:

```markdown
Resolve the repo in `${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`.
```

## How to add a shared file

1. Pick the directory: `rules/` for a normative block that goes inline in a consumer's `## Critical Rules`; `references/` for lookup data used while generating.
2. Create the file with its full content, starting with a `###`-level heading (`### Rule: ...` or `### Reference: ...`).
3. In each consumer, add the `@` reference or the path citation, per the guidance above.
4. Update the "Available shared files" table with the consumer list.
5. If any consumer bundle in `bundles.json` does not already include `np-rules`, add it — otherwise the reference resolves to a missing file at runtime (the `install.sh` dependency resolver catches this for manual installs, but bundles are authoritative for the plugin marketplace).
6. Run the repo's `scripts/check-dependencies.sh` to confirm every reference path resolves. Both the `@` form and a bare path citation fail silently at runtime when the path is wrong, so that check is the only place a typo surfaces.

## Not triggered directly

The `description` in this skill's frontmatter intentionally says "do not invoke directly". Skills trigger on description match; `np-rules` is not meant to be triggered by user intent — it is loaded transitively when a consumer resolves its `@` reference. If a shared file needs to be user-facing on its own, put it in a user-facing skill instead.
