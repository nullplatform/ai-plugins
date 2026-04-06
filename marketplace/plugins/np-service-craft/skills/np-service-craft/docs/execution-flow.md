# Execution Flow

Chain from notification to tofu apply.

## Diagram

```
User creates service in UI
  -> Service API -> SNS/SQS -> infrastructure-service-provisioner (Lambda)
  -> Notification API: creates notification, finds channels by NRN
  -> For agent channel: agents-api finds agent by tags + org + capability
  -> agents-api dispatches via WebSocket to agent
  -> np-agent receives exec command
  -> entrypoint
     |-- Bridge: NP_API_KEY -> NULLPLATFORM_API_KEY
     |-- Clean NP_ACTION_CONTEXT (remove quotes)
     |-- Parse CONTEXT, SERVICE_ACTION, SERVICE_ACTION_TYPE
     |-- Resolve SERVICE_PATH to absolute
     |-- Call: np service-action exec --live-output --live-report --script=<handler>
         -> np service-action exec
            |-- Authenticates with NULLPLATFORM_API_KEY
            |-- Sets CONTEXT env var from notification JSON
            |-- Executes handler script (service or link)
                -> handler (service or link)
                   |-- Maps action type to workflow name
                   |-- Call: np service workflow exec --workflow <path> --values <path>
                       -> np service workflow exec
                          |-- Sets VALUES = FILE PATH (not JSON content)
                          |-- Expands $SERVICE_PATH in YAML paths
                          |-- Executes each step sequentially
                          |-- Step outputs become env vars for next step
                              -> build_context (step 1)
                                 -> do_tofu (step 2)
```

## Key Behaviors

### NP_API_KEY vs NULLPLATFORM_API_KEY

| Component | Variable | Set by |
|-----------|----------|--------|
| np-agent | `NP_API_KEY` | Flag `-api-key` or env |
| np CLI | `NULLPLATFORM_API_KEY` | Env var or flag |

Without the bridge in entrypoint: `np service-action exec` fails with "please login first".

### VALUES is a File Path

`np service workflow exec --values <path>` sets `VALUES=<path>`. Read with `yaml_value()`, never `jq`.

### CONTEXT Merge

`.service.attributes` may be empty on first create. User values are in `.parameters`. Always merge:
```bash
SERVICE_ATTRS=$(echo "$CONTEXT" | jq -r '(.service.attributes // {}) * (.parameters // {})')
```

### Workflow Step Outputs

Steps declare `output` variables that become env vars for subsequent steps.

### $SERVICE_PATH in Workflows

YAML files use `$SERVICE_PATH` in `file:` paths. The workflow executor expands it before running each step.

### CWD Gotcha

Agent child process inherits CWD from where np-agent was started, NOT `~/.np/`. The entrypoint must resolve SERVICE_PATH with fallback to `~/.np/`.

## Variables by Stage

| Variable | Set by | Available in |
|----------|--------|-------------|
| `NP_ACTION_CONTEXT` | Agent (binding env) | entrypoint |
| `NP_API_KEY` | Agent (flag/env) | entrypoint |
| `NULLPLATFORM_API_KEY` | entrypoint (bridge) | np CLI, handlers |
| `CONTEXT` | np service-action exec | build_context, handlers |
| `VALUES` | np service workflow exec | build_context |
| `SERVICE_PATH` | entrypoint | all scripts |
| `ACTION_SOURCE` | entrypoint | handlers |
| `OUTPUT_DIR` | build_context | do_tofu |
| `TOFU_MODULE_DIR` | build_context | do_tofu |
| `TOFU_INIT_VARIABLES` | build_context | do_tofu |
| `TOFU_VARIABLES` | build_context | do_tofu |
| `TOFU_ACTION` | workflow YAML | do_tofu |
