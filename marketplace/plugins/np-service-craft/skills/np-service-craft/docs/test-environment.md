# Test Environment Setup

## Prerequisites

### Local Agent

Run `/np-agent-local-setup` first. This ensures np-agent is installed, API key configured, repo symlinked in `~/.np/`, and agent running locally.

Do NOT duplicate agent installation instructions here. The agent-local-setup skill handles everything.

### Active application in nullplatform

For a complete E2E test (create service + link) an active application in nullplatform is needed. The service is created "inside" an app, and the link connects that app to the cloud resource.

Ask the user with AskUserQuestion:

> Do you have an active application in nullplatform where to create the service? I need the app name or NRN.

Without an active app:
- You can test the service **create** (creates the cloud resource)
- You CANNOT test **links** (they require an app to connect the service to)

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

**BEFORE creating a service instance**, ask the user with AskUserQuestion:

> The service you're going to test will create cloud resources (e.g., S3 buckets, RDS instances, IAM users, etc). For it to work:
>
> 1. Do you have an active cloud provider session? (e.g., `aws sso login`, `az login`)
> 2. Does the user/role you're logged in with have the necessary permissions to create the resources defined by the service?
>
> Review `deployment/main.tf` and `permissions/main.tf` of the service to see what terraform resources will be created and what permissions are needed.

If the user confirms, verify the session:

**AWS**: `aws sts get-caller-identity` (must show the correct account/role)
**Azure**: `az account show` (must show the correct subscription)

If the service uses a specific profile, verify it's configured in `values.yaml` (`aws_profile`, etc) and that the session is active for that profile.

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
