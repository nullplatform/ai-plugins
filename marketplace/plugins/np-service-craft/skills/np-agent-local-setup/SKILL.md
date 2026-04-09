---
name: np-agent-local-setup
description: This skill should be used when the user asks to "run agent locally", "setup local agent", "install np-agent", "test service locally", "start local agent", "configure local testing environment", or needs to set up a nullplatform controlplane agent on their machine for local development and testing of services or scopes.
---

# np-agent-local-setup

Setup and execution of the nullplatform agent in local mode for iterative development and testing of services and scopes.

## Objective

The result of this skill is **an agent running locally and verified** — connected to the platform, responding to pings, and ready to receive notifications from services/scopes.

## When to Use

- Before testing a new service or scope locally
- When an iterative testing environment is needed (edit script -> trigger -> see logs -> fix -> retry)
- As a prerequisite for `/np-service-craft test`, `/np-scope-craft`, or any flow that needs local agent execution

## Critical Rules

1. **NEVER run the agent in Docker for local testing** — run it directly on the host
2. **The agent MUST be running BEFORE creating entities** (scopes, services, deployments) — if it's not running, notifications don't arrive
3. **NEVER log the API Key in plain text** — use `$NP_API_KEY` in logs and documentation
4. **Confirm with the user before starting the agent** — show the complete command

## Operational Workflow

Claude MUST execute each step, not just document them. The workflow ends when the agent is running and verified.

### Step 0: Verify installation

Run:

```bash
which np-agent && np-agent version
```

If not installed, ask for confirmation and install with:

```bash
curl https://cli.nullplatform.com/agent/install.sh | bash
```

It installs to `~/.local/bin/np-agent`. Verify that `~/.local/bin` is in the PATH.

### Step 1: API Key

Check if it's already set:

```bash
echo "NP_API_KEY: ${NP_API_KEY:-(not set)}"
```

If not set, ask the user to:

1. **Create the API Key in the UI**: Go to nullplatform UI → Settings → API Keys → Create
2. **Paste it in the chat** or export it in their terminal

The key format is `base64.base64` (two segments separated by a dot).

### Step 2: Prepare the repo in ~/.np/

The agent looks for scripts in `~/.np/` (default basepath). Derive org and repo from the project context (git remote, directory name, or ask the user). Create the symlink:

```bash
mkdir -p ~/.np/<org>
ln -sf $(pwd) ~/.np/<org>/<repo-name>
```

If the symlink already exists and points to the correct directory, don't recreate it. Verify:

```bash
ls -la ~/.np/<org>/<repo-name>/
```

**Alternatives** (ask if symlink doesn't apply):

- `-command-executor-command-folders /path/to/parent/folder` — adds search paths without symlinks
- `-command-executor-git-command-repos "https://TOKEN@github.com/org/repo.git#main"` — automatic clone (for CI, not dev)

### Step 3: Verify port 8181 is free

Port 8080 is commonly used by web servers, dev tools, and application frameworks (Spring Boot, Tomcat, webpack-dev-server). The agent defaults to 8080, but we use **8181** to avoid conflicts.

```bash
lsof -i :8181
```

If the port is occupied, inform the user and ask them to free it before continuing.

### Step 4: Create startup script

Check if `scripts/start-agent.sh` already exists in the repo. If it exists, don't recreate it (it may have user customizations). If it doesn't exist, create it with execute permissions. The script should:

- Validate that `NP_API_KEY` is set (exit 1 if not)
- Start np-agent with the correct flags
- Redirect output to `/tmp/np-agent.log` with `tee`

```bash
#!/bin/bash
set -euo pipefail

if [ -z "${NP_API_KEY:-}" ]; then
  echo "ERROR: NP_API_KEY is not set. Export it first:"
  echo "  export NP_API_KEY=\"your-api-key\""
  exit 1
fi

np-agent \
  -api-key "$NP_API_KEY" \
  -runtime host \
  -tags "environment:development" \
  -command-executor-env "NP_API_KEY=\"$NP_API_KEY\"" \
  -command-executor-debug \
  -webserver-enabled \
  -webserver-port 8181 \
  -log-level DEBUG \
  -log-pretty-print \
  2>&1 | tee /tmp/np-agent.log
```

Make it executable: `chmod +x scripts/start-agent.sh`

For scopes, add these additional flags to the script:

```bash
-tags "environment:development,cluster:local"
-command-executor-command-folders /path/to/parent/of/scope
```

### Step 5: Tell the user to start the agent

The agent is a daemon process that runs in a loop (WebSocket + heartbeat). **It CANNOT be run in background from Claude** because the task shell terminates and kills the process.

Tell the user to open **another terminal** and run:

```bash
export NP_API_KEY="<their-api-key>"
./scripts/start-agent.sh
```

Explicitly say: "Run this in another terminal so it doesn't block this session. When you see `Successfully connected to command executor` in the logs, let me know."

Wait for the user to confirm it started before continuing.

### Step 6: Verify connection

Read the logs and verify the agent is connected:

```bash
tail -20 /tmp/np-agent.log
```

Should show:

```
INFO  Agent registered 200 OK
INFO  Agent id: <uuid>
INFO  Successfully connected to command executor
DEBUG Command <id> [ping] executed with response: map[pong:true status:ok ...]
```

If pings respond OK, the agent is ready. Inform the user:
- Agent ID
- Organization ID
- Registered tags
- That the agent is ready to receive notifications

### Step 7: Guide the user to trigger the first action

**MANDATORY** — After confirming the agent is running, guide the user to create the entity and trigger the action. The agent receives notifications when actions are created through the platform (UI or API).

**Recommended: use the UI for the first trigger** — it handles the two-step flow (create entity + create action) transparently.

Tell the user:

> Your agent is running and ready. Now trigger the first action:
>
> **If testing a service:**
> 1. Go to the **Nullplatform UI** (https://app.nullplatform.com)
> 2. Navigate to your application → **Services** → **Add Service**
> 3. Select the service you registered (e.g., "AWS S3")
> 4. Fill in the attributes and create it
>
> **If testing a scope:**
> 1. Go to the **Nullplatform UI** (https://app.nullplatform.com)
> 2. Navigate to your application → **Create Scope**
> 3. Select the scope type and configure dimensions
>
> The platform will send a notification to the local agent, which will execute the workflow.
>
> Monitor the agent logs with: `tail -f /tmp/np-agent.log`
>
> When you see the agent executing scripts (build_context, do_tofu), let me know — I can help troubleshoot if anything fails.

**API/CLI alternative:** Creating via API requires two calls — first create the entity (`POST /service` or `POST /scope`), then create the action instance (`POST /service/{id}/action` or `POST /scope/{id}/action`). Without the second call, the entity stays in `pending` and no notification reaches the agent. See `np-developer-actions` docs/services.md for the full API flow.

### Post-setup: Iterative testing cycle

Once the agent is running and an action has been triggered, the development cycle is:

```
1. Edit script/workflow
2. Trigger action (from UI, API, or resend notification for retesting)
3. View agent logs: tail -f /tmp/np-agent.log
4. If it fails: fix -> resend notification (without recreating the resource)
5. Repeat until it works
```

To resend a notification without recreating the resource:

```
/np-notification-manager resend <notification-id>
```

To find the notification ID:

```
/np-api fetch-api "/notification?nrn=<nrn>&per_page=5"
```

## Flags Reference

| Flag | Default | Usage |
|------|---------|-------|
| `-api-key` | `$NP_API_KEY` | Authentication (mandatory) |
| `-runtime` | - | `host` for local (mandatory) |
| `-tags` | - | Tags for matching with notification channels (`k:v,k2:v2`) |
| `-command-executor-basepath` | `~/.np` | Where to look for scripts |
| `-command-executor-command-folders` | - | Additional search folders |
| `-command-executor-debug` | `false` | Prints stdout of executed scripts |
| `-command-executor-env` | - | Env vars injected into scripts (`K=V,K2=V2`) |
| `-command-executor-git-command-repos` | - | Repos to clone into basepath |
| `-command-executor-disable-known-commands-validate` | `false` | Disables path validation (security bypass) |
| `-log-level` | `ERROR` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `-log-pretty-print` | `false` | Colored logs |
| `-webserver-enabled` | `false` | Enables HTTP health check |
| `-webserver-port` | `8080` | Health check port. Use **8181** for local dev (8080 is often taken by IDEs) |
| `-heartbeat-interval` | `60` | Seconds between heartbeats |

**Note**: `np-agent` uses Go-style flags with **single dash** (`-api-key`), not double dash (`--api-key`). Both work but the canonical style is single dash.

## Gotcha: The agent inherits env vars from the shell

The agent passes **all** environment variables from the shell where it was started to the scripts it executes. If your shell has `AWS_PROFILE=something`, the scripts will use it even if `values.yaml` has a different profile configured.

Scripts (`build_context`) must explicitly override cloud provider variables when `values.yaml` has a value. The correct pattern is:

```bash
# values.yaml always wins (no -z check)
if [ -n "$PROFILE_FROM_VALUES" ]; then
  export AWS_PROFILE="$PROFILE_FROM_VALUES"
fi
```

If a script fails with "profile not found", verify which env vars the agent inherits with `env | grep AWS` in the shell where it runs.

## Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `NP_API_KEY` | np-agent | Agent authentication with the platform |
| `NULLPLATFORM_API_KEY` | np CLI | The `np` CLI expects this variable, NOT `NP_API_KEY` |
| `NP_ACTION_CONTEXT` | Notification payload | JSON with the action context (set by the platform) |

**Critical bridge**: The agent passes `NP_API_KEY` but the `np` CLI expects `NULLPLATFORM_API_KEY`. The service/scope entrypoint must do the bridge:

```bash
if [ -n "${NP_API_KEY:-}" ] && [ -z "${NULLPLATFORM_API_KEY:-}" ]; then
  export NULLPLATFORM_API_KEY="$NP_API_KEY"
fi
```

## Path Resolution

The agent resolves commands like this:

```
cmdline received: "org/repo/services/my-svc/entrypoint/entrypoint"
resolution:       basepath + cmdline = ~/.np/org/repo/services/my-svc/entrypoint/entrypoint
```

If the file is not found in any of the basepaths + command-folders, the agent returns: `"command not found in any allowed paths"`.

Verify the path exists:

```bash
ls -la ~/.np/<org>/<repo>/services/<service>/entrypoint/entrypoint
```

And has execute permissions:

```bash
chmod +x ~/.np/<org>/<repo>/services/<service>/entrypoint/entrypoint
```

Symlinks are valid but the target must resolve within the basepaths.

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| FATAL "bind: address already in use" | Port occupied by another process (8080 is commonly used by IDEs/dev servers) | Use `-webserver-port 8181` or another free port |
| Agent prints help and exits | Missing `-runtime host` | Add the flag |
| "Malformed API key" | Key doesn't have `base64.base64` format | Verify the key in the UI |
| "command not found in any allowed paths" | Script not in basepath | Verify symlink/clone in `~/.np/` |
| "symlink points outside allowed paths" | Symlink target outside basepaths | Add folder with `-command-executor-command-folders` |
| Notification arrives but script doesn't run | Agent tags don't match the channel selector | Compare agent `-tags` with channel selector |
| "please login first" | `NULLPLATFORM_API_KEY` not set | Add bridge NP_API_KEY -> NULLPLATFORM_API_KEY in entrypoint |
| Entrypoint fails silently (exit 1, no output) | Relative `SERVICE_PATH` doesn't resolve | Resolve absolute path in the entrypoint (see np-service-craft docs/troubleshooting.md) |
| WebSocket disconnects | Network, expired token | The agent reconnects automatically (backoff 1s-20s) |
| Heartbeat 404 | Server evicted the agent | The agent re-registers automatically |
| Cloud credentials error when running tofu | No active cloud provider session | `aws sso login --profile <name>` or `az login` before starting the agent |

## Stopping the agent

```bash
# If running in foreground: Ctrl+C
# If running in background:
kill $(pgrep np-agent)
```

The agent does cleanup on SIGINT/SIGTERM: marks itself as inactive in the API.
