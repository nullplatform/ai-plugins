---
name: np-service-workflows
description: Use when writing or modifying nullplatform service workflows and scripts — workflow YAML structure, build_context scripts, do_tofu, entrypoints, write_outputs scripts, and execution conventions.
---

# Nullplatform Service Scripts

Conventions for YAML workflows, build_context/do_tofu scripts, and service entrypoints.

## Critical Rules

1. **Always `set -euo pipefail`** in all scripts
2. **VALUES is a FILE PATH** — read with `yaml_value()`, never `echo "$VALUES" | jq`
3. **Merge parameters with attributes** — `(.service.attributes // {}) * (.parameters // {})`
4. **Entrypoint MUST bridge** `NP_API_KEY` → `NULLPLATFORM_API_KEY`
5. **$SERVICE_PATH must be absolute** — resolve relative paths with fallback to `~/.np/`

## Workflow YAML Structure

```yaml
steps:
  - name: build context
    type: script
    file: $SERVICE_PATH/scripts/<provider>/build_context
    output:
      - name: OUTPUT_DIR
        type: environment
      - name: TOFU_MODULE_DIR
        type: environment
      - name: TOFU_INIT_VARIABLES
        type: environment
      - name: TOFU_VARIABLES
        type: environment

  - name: tofu
    type: script
    file: $SERVICE_PATH/scripts/<provider>/do_tofu
    configuration:
      TOFU_ACTION: apply  # or "destroy" for delete workflows
```

Optional post-tofu step for services with export fields:
```yaml
  - name: write service outputs
    type: script
    file: $SERVICE_PATH/scripts/<provider>/write_service_outputs
```

## Standard Workflows

| Workflow | Action | TOFU_ACTION | Extra steps |
|----------|--------|-------------|-------------|
| create.yaml | Provision resource | apply | write_service_outputs (if export fields) |
| delete.yaml | Destroy resource | destroy | - |
| update.yaml | Update resource | apply | write_service_outputs (if export fields) |
| link.yaml | Connect app | apply (permissions) | build_permissions_context + write_link_outputs |
| unlink.yaml | Disconnect app | destroy (permissions) | build_permissions_context |

## Environment Variables by Stage

| Variable | Set by | Available in | Content |
|----------|--------|-------------|---------|
| `NP_API_KEY` | Agent (flag/env) | entrypoint | API key |
| `NULLPLATFORM_API_KEY` | entrypoint (bridge) | np CLI, handlers | Same key, np CLI name |
| `CONTEXT` | np service-action exec | build_context | Notification JSON |
| `VALUES` | np service workflow exec | build_context | **File path** to values.yaml |
| `SERVICE_PATH` | entrypoint | all scripts | Absolute path to service dir |
| `ACTION_SOURCE` | entrypoint | handlers | "service" or "link" |
| `OUTPUT_DIR` | build_context | do_tofu | Temp dir for tofu execution |
| `TOFU_MODULE_DIR` | build_context | do_tofu | Path to deployment/ or permissions/ |
| `TOFU_INIT_VARIABLES` | build_context | do_tofu | Backend config flags |
| `TOFU_VARIABLES` | build_context | do_tofu | `-var=` flags |
| `TOFU_ACTION` | workflow YAML | do_tofu | "apply" or "destroy" |

## Script Conventions

### build_context
- Reads `CONTEXT` (JSON) and `VALUES` (file path)
- Merges `.service.attributes` with `.parameters` (parameters win)
- Reads static config from values.yaml via `yaml_value()`
- Exports: `OUTPUT_DIR`, `TOFU_MODULE_DIR`, `TOFU_INIT_VARIABLES`, `TOFU_VARIABLES`

### do_tofu
- Generic, same for all services
- Copies module to temp dir, runs `tofu init + apply/destroy`

### write_service_outputs / write_link_outputs
- Reads tofu outputs, updates service/link attributes via `np service patch` / `np link patch`
- Only needed if spec has fields with `export: true`

### Entrypoint
- Bridges `NP_API_KEY` → `NULLPLATFORM_API_KEY`
- Resolves `SERVICE_PATH` to absolute (with `~/.np/` fallback)
- Dispatches to `./service` or `./link` handler

For detailed patterns and templates, see:
- `docs/build-context-patterns.md` — yaml_value, merge, provider profiles, permissions context
- `docs/entrypoint-reference.md` — full entrypoint, handler, and output script templates
