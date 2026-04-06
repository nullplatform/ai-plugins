# Test Environment Setup

## Prerequisites

### Local Agent

Run `/np-agent-local-setup` first. This ensures np-agent is installed, API key configured, repo symlinked in `~/.np/`, and agent running locally.

Do NOT duplicate agent installation instructions here. The agent-local-setup skill handles everything.

### Application activa en nullplatform

Para un test E2E completo (create service + link) se necesita una aplicacion activa en nullplatform. El servicio se crea "dentro" de una app, y el link conecta esa app al recurso cloud.

Preguntar al usuario con AskUserQuestion:

> Tenes una aplicacion activa en nullplatform donde crear el servicio? Necesito el nombre o NRN de la app.

Sin una app activa:
- Podes testear el **create** del servicio (crea el recurso cloud)
- NO podes testear **links** (requieren una app a la cual conectar el servicio)

## Flow

### 1. Verify service is registered

```bash
grep -c "service_definition_<name>" nullplatform/main.tf
```

If not registered, suggest `/np-service-craft register <name>` first.

### 2. Verify service spec exists in API

```bash
/np-api fetch-api "/service_specification?nrn=organization=<org_id>&show_descendants=true&limit=50"
```

If not found, apply terraform first: `cd nullplatform && tofu init && tofu apply`

### 3. Verify agent is running

```bash
tail -5 /tmp/np-agent.log
```

Must show recent heartbeat or ping. If not running, instruct user to start it.

### 4. Verify tags match

Read binding tags from `nullplatform-bindings/main.tf` and compare with agent's `--tags`. They must match for notifications to route.

### 5. Cloud provider credentials and permissions

**ANTES de crear una instancia del servicio**, preguntar al usuario con AskUserQuestion:

> El servicio que vas a testear va a crear recursos en la nube (ej: buckets S3, instancias RDS, IAM users, etc). Para que funcione:
>
> 1. Tenes una sesion activa del cloud provider? (ej: `aws sso login`, `az login`)
> 2. El usuario/role con el que estas logueado tiene los permisos necesarios para crear los recursos que define el servicio?
>
> Revisá `deployment/main.tf` y `permissions/main.tf` del servicio para ver que recursos terraform va a crear y que permisos necesita.

Si el usuario confirma, verificar la sesion:

**AWS**: `aws sts get-caller-identity` (debe mostrar el account/role correcto)
**Azure**: `az account show` (debe mostrar la subscription correcta)

Si el servicio usa un profile especifico, verificar que esta configurado en `values.yaml` (`aws_profile`, etc) y que la sesion esta activa para ese profile.

### 6. Step-by-step testing

```
1. Apply terraform (if not done):
   cd nullplatform && tofu init && tofu apply
   cd nullplatform-bindings && tofu init && tofu apply

2. Create service instance from UI:
   Nullplatform UI -> Applications -> choose app -> Services -> Add Service
   Select the service, configure parameters, Create

3. Watch agent logs:
   tail -f /tmp/np-agent.log

4. Verify execution:
   /np-api fetch-api "/notification?nrn=<app_nrn>&source=service&per_page=5"
   /np-api fetch-api "/notification/<id>/result"

5. If failed: fix script, then resend:
   /np-service-craft resend-notification <notification_id>
```

### 7. Testing links

Requires service in `active` state first.

1. Create link: UI -> App -> Services -> click active service -> Add Link
2. If link stays `pending` without action, create action instance manually:
   ```bash
   /np-api fetch-api "/action_specification?link_specification_id=<link_spec_id>"
   # Find the "create" spec, then:
   # POST /link/<link_id>/action with {"specification_id": "<create_spec_id>"}
   ```
3. Watch agent logs for link execution
4. Verify permissions applied and link outputs written

### 8. Diagnostic

- **Notification delivered but no execution**: check tags match
- **exitCode 1, empty output**: SERVICE_PATH resolution failed (see troubleshooting.md)
- **Resend without recreating**: `/np-service-craft resend-notification <id>`
- **Check notification result**: `/np-api fetch-api "/notification/<id>/result"`

> A notification status `success` does NOT mean the script succeeded. It means the dispatch to the agent was successful. The actual exit code is in `/notification/<id>/result`.
