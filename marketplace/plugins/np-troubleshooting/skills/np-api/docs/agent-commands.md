# Agent Commands

Remote command execution on agents via control plane.

## @endpoint POST /controlplane/agent_command

Executes a command on agents selected by selector.

### Method
POST (only endpoint that is not GET)

### Request Body
```json
{
  "selector": {
    "cluster": "runtime"
  },
  "command": {
    "type": "exec",
    "data": {
      "cmdline": "nullplatform/scopes/k8s/troubleshooting/dump-status",
      "arguments": ["--deployment-id", "1850350294", "--k8s-namespace", "nullplatform"]
    }
  }
}
```

### Fields
- `selector`: Matches with `channel_selectors` of agents
  - `cluster`: runtime (K8s agents)
  - `provisioner`: services (Service agents)
- `command.type`: `exec`
- `command.data.cmdline`: Script/command to execute
- `command.data.arguments`: Array of arguments

### Known Commands
| Command | Purpose |
|---------|---------|
| `nullplatform/scopes/k8s/troubleshooting/dump-status` | K8s state dump of a deployment |
| `nullplatform/scopes/k8s/kubectl_get` | Read-only `kubectl get`. Secret `data`/`stringData` stripped from output. |
| `nullplatform/scopes/k8s/kubectl_logs` | Read-only `kubectl logs`. Streaming (`-f`/`--follow`) blocked. |

### Selector → Agent Channel Mapping
```
selector: {cluster: runtime}      →  K8s agents (Channel ~848305398)
selector: {provisioner: services} →  Service agents (Channel ~1540233609)
```

### Example
```bash
# This is a POST, requires direct curl or special script
curl -X POST "https://api.nullplatform.com/controlplane/agent_command" \
  -H "Authorization: Bearer $NP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {"cluster": "runtime"},
    "command": {
      "type": "exec",
      "data": {
        "cmdline": "nullplatform/scopes/k8s/troubleshooting/dump-status",
        "arguments": ["--deployment-id", "1850350294", "--k8s-namespace", "nullplatform"]
      }
    }
  }'
```

### Example: kubectl_get (targeted by service selector)

```bash
curl -X POST "https://api.nullplatform.com/controlplane/agent_command" \
  -H "Authorization: Bearer $NP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {"service": "sync-ad"},
    "command": {
      "type": "exec",
      "data": {
        "cmdline": "nullplatform/scopes/k8s/kubectl_get",
        "arguments": ["pods", "-n", "nullplatform"]
      }
    }
  }'
```

Response carries stdout in `.executions[].results.stdOut` (pod list). Use the `agent-kubectl.sh` helper instead of raw curl whenever possible.

### Example: kubectl_logs (runtime cluster)

```bash
curl -X POST "https://api.nullplatform.com/controlplane/agent_command" \
  -H "Authorization: Bearer $NP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "selector": {"cluster": "runtime"},
    "command": {
      "type": "exec",
      "data": {
        "cmdline": "nullplatform/scopes/k8s/kubectl_logs",
        "arguments": ["my-pod", "--tail", "200", "--previous"]
      }
    }
  }'
```

`--follow` / `-f` are rejected by the agent wrapper to keep the call bounded.

### Helper Scripts

There are scripts in `scripts/` for simplification:

**deploy-agent-dump.sh** - Deployment dump:
```bash
./scripts/deploy-agent-dump.sh <deployment_id>
```

**scope-agent-dump.sh** - Scope dump:
```bash
./scripts/scope-agent-dump.sh <scope_id>
```

**agent-kubectl.sh** - Read-only kubectl via agent:
```bash
# get: pods in a namespace (default selector cluster=runtime, default nrn organization=4)
./scripts/agent-kubectl.sh get -- pods -n nullplatform

# get: target a specific service agent
./scripts/agent-kubectl.sh get --selector service=sync-ad -- pods -n nullplatform

# logs: last 200 lines of previous container (CrashLoopBackOff triage)
./scripts/agent-kubectl.sh logs --selector cluster=runtime -- my-pod --tail 200 --previous
```
Verbs are limited to `get` and `logs`. See the script header for full flag reference.

### Notes
- Executes directly on the client's K8s infrastructure
- Useful when API info is insufficient
- Requires the agent to be active and reachable
