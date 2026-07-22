---
name: np-rules
description: Shared rule files referenced by other nullplatform skills via `@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/*.md`. This skill is a dependency container, not a user-facing skill — other skills auto-load its files through `@` file inclusion. Do not invoke directly from user intent.
---

# np-rules — Shared Rule Files

This skill is a **dependency container**. It holds rule blocks that apply across multiple nullplatform skills, so the text lives in exactly one place and consumer skills reference it via `@` inclusion.

## Available rules

| File | Consumers | Purpose |
|------|-----------|---------|
| `rules/iac-rule.md` | `np-infrastructure-wizard`, `np-setup-orchestrator`, `np-nullplatform-wizard`, `np-nullplatform-bindings-wizard`, `np-scope-craft`, `np-service-craft`, `np-service-creator` | "Infrastructure changes only via IaC" — forbids cloud / TF-modeled entity mutation outside of Terraform code; lists allowed read-only operations; defines the carve-out for workflow-managed entities (scopes, deployments, parameters, etc.). |

## How to consume a rule from another skill

In the consumer's `SKILL.md`, add a single line where the rule should appear:

```markdown
@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md
```

The `@` directive causes Claude Code to inline the file's content into context when the consumer skill is triggered (same semantics documented in the repo's `CLAUDE.md` under "Referencias a archivos y ejecución en skills y commands"). The included file starts with its own heading (`### Rule: ...`), so the consumer does not need to add one.

## How to add a new shared rule

1. Create `rules/<name>.md` with the full rule content, starting with a `###`-level heading.
2. In each consumer `SKILL.md`, add `@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/<name>.md` at the correct point.
3. Update the "Available rules" table above with the consumer list.
4. If any consumer bundle in `bundles.json` does not already include `np-rules`, add it — otherwise the `@` reference will resolve to a missing file at runtime (the `install.sh` dependency resolver catches this for manual installs, but bundles are authoritative for the plugin marketplace).

## Not triggered directly

The `description` in this skill's frontmatter intentionally says "do not invoke directly". Skills trigger on description match; `np-rules` is not meant to be triggered by user intent — it is loaded transitively when a consumer resolves its `@` reference. If a rule block needs to be user-facing on its own, put it in a user-facing skill instead.
