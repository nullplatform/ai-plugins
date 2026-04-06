# Agent Commands

Ejecución de comandos remotos en agents via control plane.

## @endpoint POST /controlplane/agent_command

Ejecuta un comando en agents seleccionados por selector.

### Método
POST (único endpoint que no es GET)

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

### Campos
- `selector`: Matchea con `channel_selectors` de agents
  - `cluster`: runtime (K8s agents)
  - `provisioner`: services (Service agents)
- `command.type`: `exec`
- `command.data.cmdline`: Script/comando a ejecutar
- `command.data.arguments`: Array de argumentos

### Comandos Conocidos
| Comando | Propósito |
|---------|-----------|
| `nullplatform/scopes/k8s/troubleshooting/dump-status` | Dump estado K8s de un deployment |

### Selector → Agent Channel Mapping
```
selector: {cluster: runtime}      →  K8s agents (Channel ~848305398)
selector: {provisioner: services} →  Service agents (Channel ~1540233609)
```

### Ejemplo
```bash
# Este es un POST, requiere curl directo o script especial
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

### Scripts Helper

Existen scripts en `scripts/` para simplificar:

**deploy-agent-dump.sh** - Dump de deployment:
```bash
./scripts/deploy-agent-dump.sh <deployment_id>
```

**scope-agent-dump.sh** - Dump de scope:
```bash
./scripts/scope-agent-dump.sh <scope_id>
```

### Notas
- Ejecuta directamente en infraestructura K8s del cliente
- Útil cuando info de API es insuficiente
- Requiere que el agent esté activo y alcanzable
