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

### Notes
- Executes directly on the client's K8s infrastructure
- Useful when API info is insufficient
- Requires the agent to be active and reachable
