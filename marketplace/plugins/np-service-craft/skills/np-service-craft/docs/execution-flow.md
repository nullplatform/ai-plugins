# Execution Flow

Chain from notification to tofu apply.

## Diagram

The chain has two halves. The **outer** half — how the action reaches the service's code —
changed with the package model. The **inner** half — entrypoint through tofu — did not.

```
User creates service in UI
  -> Service API -> SNS/SQS -> infrastructure-service-provisioner (Lambda)
  -> Notification API: creates notification, finds channels by NRN
  -> the service's channel is a PACKAGE-EXEC channel (emitted by the agent
     association with worker_orchestrator = true), not a git-clone exec one
  -> agents-api finds the agent by tags + org + capability
  -> np-agent starts a WORKER POD for the service's package
     |-- pulls the package's OCI image (must match worker.allowedRegistries)
     |-- runs under the agent's ServiceAccount if the package slug is in
     |   worker_orchestrated_packages, else the namespace default
     |-- memory limit = worker_memory_limit (2Gi default; the chart's own
     |   default OOMs mid-tofu-apply)
  -> entrypoint (inside the image)
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

### CWD Gotcha (legacy command-executor only)

Under the legacy flow the agent child process inherited CWD from where np-agent was
started, not `~/.np/`, so the entrypoint had to resolve `SERVICE_PATH` with a fallback.

Under worker orchestration the code lives at a fixed path inside the image and there is no
basepath to resolve against. If you see `SERVICE_PATH` resolution failures on a packaged
service, the cause is the image layout, not the CWD.

### Worker never starts

The package published fine but its first action hangs or fails. In order of likelihood:

1. The image's registry is not in `worker.allowedRegistries` (defaults to
   `public.ecr.aws/nullplatform/*` and nothing else).
2. The package slug is not in `worker_orchestrated_packages`.
3. The channel's entrypoint path does not exist in the image — the association defaults to
   `/app/packages/<slug>/entrypoint` while the reference Dockerfiles bake
   `/app/pkg/<slug>/entrypoint/entrypoint`.
4. `tags_selectors` on the association do not match the agent's tags. Packaging does not
   remove this — the channel still routes by tags.

None of the four is validated at `tofu apply`.

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
