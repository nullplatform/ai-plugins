---
name: np-service-creator
description: This skill should be used when the user asks to "register a service in terraform", "create service_definition module", "create agent binding", "configure terraform for services", or needs to work with terraform modules for nullplatform service registration and agent association.
---

# Nullplatform Service Creator — Terraform Registration

Terraform patterns for registering service definitions and agent bindings in nullplatform.

## Critical Rules

1. **Confirm before `tofu apply`** — explain what will be created and why.
2. **NRN of binding MUST match NRN of service_definition** — mismatch causes "There is not a channel for the given parameters".
3. **tags_selectors MUST match agent tags** — mismatch causes notifications not to route.
4. **For local development**, use `git_provider = "local"` to read specs from the filesystem without needing to push to GitHub.
5. **NEVER hardcode module variables from memory** — always read them from the module source.

## Module Source of Truth

The terraform modules for registering services live in `https://github.com/nullplatform/tofu-modules`:

| Module | Path | Purpose |
|--------|------|---------|
| `service_definition` | `nullplatform/service_definition/` | Creates service_specification + link_specification from JSON specs |
| `service_definition_agent_association` | `nullplatform/service_definition_agent_association/` | Creates notification_channel for agent routing |

## How to Determine Required Variables

**BEFORE generating any terraform block**, clone the repo and read the `variables.tf` of each module:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Read:
- `/tmp/tofu-modules-ref/nullplatform/service_definition/variables.tf` — variables with and without `default`. Those without default are mandatory.
- `/tmp/tofu-modules-ref/nullplatform/service_definition_agent_association/variables.tf` — same.

Also read `main.tf` and `locals.tf` of each module to understand how resources are built internally (e.g., how the agent_association cmdline is constructed).

Do not copy variables from this skill — infer them from the source code each time.

## Two Modes

### Local Mode (development)

Use `git_provider = "local"` + `local_specs_path` pointing to the local service directory. Reads specs from the filesystem without needing to push.

### Remote Mode (production)

Use `git_provider = "github"` (default) or `"gitlab"`. The module reads specs via HTTP from the git repository. Requires specs to be pushed.

## Agent Association: cmdline

The `service_definition_agent_association` module builds the cmdline internally from its variables. Read the module's `main.tf` to understand the exact pattern.

For local dev, set `base_clone_path` to the user's home (`pathexpand("~/.np")`) instead of the default `/root/.np`.

## Apply Order

Always apply in order:
1. `nullplatform/` first (creates service_specification, generates outputs)
2. `nullplatform-bindings/` second (creates notification_channel, reads outputs from step 1)

## Pre-Registration Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | Schema in `attributes.schema` | `jq -e '.attributes.schema.type' specs/service-spec.json.tpl` |
| 2 | No `specification_schema` | `jq -e '.specification_schema' specs/service-spec.json.tpl` must fail |
| 3 | Links use `attributes.schema` | `jq -e '.attributes.schema' specs/links/*.json.tpl` |
| 4 | NRN matches between both modules | Compare nrn values |
| 5 | tags_selectors match agent tags | Compare with `-tags` flag |
| 6 | Scripts are executable | `ls -la entrypoint/ scripts/*/` |
| 7 | JSONs are valid | `jq . specs/*.json.tpl specs/links/*.json.tpl` |
| 8 | Fields with export:true have write_outputs | verify scripts exist |
