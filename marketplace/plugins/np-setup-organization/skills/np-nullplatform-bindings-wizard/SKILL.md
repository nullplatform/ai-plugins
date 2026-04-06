---
name: np-nullplatform-bindings-wizard
description: This skill should be used when the user asks to "connect GitHub", "setup container registry", "bind cloud provider", "configure bindings", "link external service", or needs to connect nullplatform with external services like GitHub, container registries (ECR, ACR, GCR), and cloud providers.
---

# Nullplatform Bindings Wizard

Connects Nullplatform with external services: GitHub, container registry, cloud provider.

## When to Use

- Configuring GitHub integration
- Connecting container registry (ECR/ACR/Artifact Registry)
- Configuring cloud provider in Nullplatform
- Creating channel associations to route to agents

## Prerequisites

> **IMPORTANT**: This wizard REQUIRES that `/np-nullplatform-wizard` has been run first.
> Channel associations depend on the scopes and dimensions created in that step.

1. Verify that `organization.properties` exists and has the organization_id
2. Invoke `/np-api check-auth` to verify authentication
3. Invoke `/np-api` to verify scopes exist (if there are none, run `/np-nullplatform-wizard` first):
   - Query service_specifications of the organization

## Reference Templates

Templates are in `nullplatform-bindings/example/` - **NOT APPLIED DIRECTLY**.

```text
nullplatform-bindings/
├── example/                    # Reference templates
│   ├── main.tf
│   ├── data.tf
│   ├── locals.tf
│   └── variables.tf
└── *.tf                        # Your actual implementation (when created)
```

## What Gets Created

### Code Repository

Connection with GitHub for source code:

| Configuration | Description |
| ------------- | ----------- |
| `git_provider` | `github` |
| `github_organization` | Your GitHub org name |
| `github_installation_id` | Installed GitHub App ID |

### Asset Repository (ECR/ACR/Artifact Registry)

Docker image storage. The `asset_repository` module creates:

**On AWS (ECR):**

| AWS Resource | Name | Purpose |
| ------------ | ---- | ------- |
| IAM Role | `nullplatform-{cluster}-application-role` | Allows Nullplatform to assume role for creating repos |
| IAM Policy | `nullplatform-{cluster}-ecr-manager-policy` | ECR permissions: create/delete repo, push/pull images |
| IAM User | `nullplatform-{cluster}-build-workflow-user` | User for CI/CD pipelines |
| IAM Access Key | (generated) | Credentials for the build user |

**On Nullplatform:**

| Resource | Type | Purpose |
| -------- | ---- | ------- |
| Provider Config | `ecr` | Registers AWS credentials for automatic repo creation |

**Summary by cloud:**

| Cloud | Registry | Variables |
| ----- | -------- | --------- |
| AWS | ECR | Automatic via IAM |
| Azure | ACR | `login_server`, `username`, `password` |
| GCP | Artifact Registry | `login_server`, `username`, `password` |

### Cloud Provider Binding

Links Nullplatform with your cloud. The `cloud_provider` module creates:

**On Nullplatform:**

| Resource | Type | Purpose |
| -------- | ---- | ------- |
| Provider Config | `aws-configuration` / `azure-configuration` / `gcp-configuration` | Configures domain, DNS zones, region |

**Configuration:**

| Configuration | Description |
| ------------- | ----------- |
| `domain_name` | Domain for applications |
| `hosted_public_zone_id` | Public Route53 Zone ID (AWS) |
| `hosted_private_zone_id` | Private Route53 Zone ID (AWS) |
| `resource_group` | Resource group (Azure) |
| `dimensions` | Dimension mapping |

### Channel Associations

Routes deployments to the correct cluster:

| Association | Description |
| ----------- | ----------- |
| K8s Containers | Associates k8s scope with agent |
| Scheduled Tasks | Associates scheduled tasks with agent |
| Endpoint Exposer | Associates endpoint exposer with agent |

### Metrics

Connection with Prometheus for metrics:

| Configuration | Description |
| ------------- | ----------- |
| `prometheus_url` | Prometheus server URL |
| `dimensions` | Dimensions for metrics |

## Wizard Workflow

### 1. Verify no configuration exists

```bash
ls nullplatform-bindings/*.tf 2>/dev/null || echo "No configuration exists - proceed"
```

### 2. Copy templates (except main.tf)

```bash
# Copy all templates EXCEPT main.tf (generated dynamically)
for f in nullplatform-bindings/example/*.tf; do
  [ "$(basename "$f")" = "main.tf" ] && continue
  cp "$f" nullplatform-bindings/
done
```

### 2b. Generate or customize main.tf

The nullplatform-bindings `main.tf` is generated dynamically following [references/bindings-generation.md](references/bindings-generation.md).

1. **Check if `nullplatform-bindings/main.tf` exists**

   ```bash
   ls nullplatform-bindings/main.tf 2>/dev/null
   ```

   - **If it does NOT exist** -> Read [references/bindings-generation.md](references/bindings-generation.md) and follow its complete flow (user questions, module patterns, validation). This layer has no mandatory outputs since there are no downstream layers that consume it.
   - **If it exists** -> Ask with AskUserQuestion:
     - **Regenerate from scratch** -> Delete the current one, read [references/bindings-generation.md](references/bindings-generation.md) and follow its flow
     - **Customize the existing one** -> Read the current main.tf and ask what changes to make
     - **Leave it as is** -> Go to step 3

2. After generating/modifying, validate:

   ```bash
   cd nullplatform-bindings
   tofu init -backend=false
   tofu validate
   ```

3. If `tofu validate` fails, fix BEFORE continuing with step 3.

### 3. Configure Code Repository

Based on the code repository chosen in step 2b (bindings-generation flow):

**GitHub:**
1. Install the GitHub App: **https://github.com/apps/nullplatform-github-integration**
2. Select the organization and repositories
3. Get the Installation ID from: `https://github.com/organizations/YOUR-ORG/settings/installations/XXXXX`

**GitLab:**
1. Obtain an access token with API permissions
2. Configure group path, installation URL, collaborators, repository prefix, and slug

**Azure DevOps:**
1. Obtain a personal access token
2. Configure project name and agent pool

### 4. Apply

```bash
cd nullplatform-bindings
tofu init
tofu apply
```

### 5. Post-Apply Validation (REQUIRED)

After `tofu apply`, verify that bindings work correctly.

#### 5.1 Verify Providers

```bash
# Get organization_id from organization.properties
ORG_ID=$(grep organization_id organization.properties | cut -d= -f2)

# Verify code provider (GitHub)
/np-api fetch-api "/provider?nrn=organization%3D${ORG_ID}&specification_slug=code_repository"

# Verify registry provider (ECR)
/np-api fetch-api "/provider?nrn=organization%3D${ORG_ID}&specification_slug=ecr"
```

#### 5.2 Verify Notification Channels

```bash
# List created channels
/np-api fetch-api "/notification/channel?nrn=organization%3D${ORG_ID}&showDescendants=true"
```

#### 5.3 Verify Channel API Keys

For each `agent` type channel, verify the API key has the correct roles:

```bash
# 1. Get channel details
/np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"

# 2. Search the API key by name (e.g., SCOPE_DEFINITION_AGENT_ASSOCIATION)
/np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# 3. View the API key grants
/np-api fetch-api "/api-key/{api_key_id}"
```

**Required roles for notification channels:**

| Role | Purpose |
|------|---------|
| `controlplane:agent` | Communication with control plane |
| `ops` | Execute commands on the agent |

#### 5.4 Validation Checklist

| Check | Command | Expected |
|-------|---------|----------|
| GitHub provider exists | `/provider?specification_slug=code_repository` | 1+ result |
| ECR provider exists | `/provider?specification_slug=ecr` | 1+ result |
| Channel exists | `/notification/channel?nrn=...` | 1+ result |
| API key has `controlplane:agent` | `/api-key/{id}` → grants | Present |
| API key has `ops` | `/api-key/{id}` → grants | Present |

## Required Variables

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `organization_id` | Organization ID | organization.properties |
| `np_api_key` | Nullplatform API key | NP_API_KEY/np-api-skill.key (recommended) |
| Code repo variables | Depend on chosen provider (github_*, gitlab_*, azure_*) | terraform.tfvars |

## Validation

```bash
# Read organization_id
Invoke `/np-api` to query:

| Required information | Entity to query |
|---------------------|-----------------|
| GitHub providers | `code_repository` type providers of the organization |
| Registry providers | `docker_server` type providers of the organization |
| Notification channels | notification channels of the organization |

## Troubleshooting

### GitHub Connection Fails

- Verify that the GitHub App is installed in the org
- Verify installation_id is correct
- Verify the App has permissions on the repos

### Registry Auth Fails

- Verify credentials haven't expired
- For Azure: regenerate password if needed
- For GCP: verify service account has permissions

### Agent Doesn't Receive Notifications

- Verify `tags_selectors` match between channel and agent
- Verify agent is running: `kubectl get pods -n nullplatform-tools`
- Review agent logs

### Application Fails with "Error creating ECR repository"

This error occurs when an application is created **BEFORE** the container registry binding is configured.

> **IMPORTANT**: Applications that fail for this reason **do NOT recover automatically**
> when bindings are added afterwards. They must be deleted and recreated.

**To resolve:**

1. Verify that `module "asset_repository"` is enabled in `nullplatform-bindings/main.tf`
2. Run `tofu apply` in `nullplatform-bindings/`
3. Verify the ECR provider exists via API:

   ```bash
   np-api fetch "/provider?nrn=organization=XXX:account=YYY&show_descendants=true"
   ```

4. **DELETE** the failed application from the Nullplatform UI
5. **Recreate** the application - it will now work correctly

## Next Step

With bindings configured, your Nullplatform account is ready to deploy applications.

**Options:**

1. Create your first application in the Nullplatform UI
2. Debug or explore: `/np-api`
