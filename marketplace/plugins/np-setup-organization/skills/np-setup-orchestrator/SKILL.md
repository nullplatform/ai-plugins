---
name: np-setup-orchestrator
description: Orchestrates the complete configuration of a Nullplatform organization. Use when you need to initialize a project, verify infrastructure/cloud/K8s/API status, diagnose issues, or run tool, cloud, Kubernetes, Nullplatform API, telemetry, and service checks.
---

# Nullplatform Setup Orchestrator

## IMPORTANT RULE: Using np-api

**NEVER use `curl` directly to query the Nullplatform API (`api.nullplatform.com`).**

For ANY query to the Nullplatform API, you MUST use:

- `/np-api fetch-api "<endpoint>"` - For API queries
- `/np-api check-auth` - To verify authentication
- The `np-api` skill - For programmatic operations (invoke via `/np-api`)

**Allowed exceptions (NOT the Nullplatform API):**

- `curl` to deployed application endpoints (`*.nullapps.io`) for health checks
- `curl` to external services (AWS, Azure, GCP)

## Available Commands

| Command | Description |
|---------|-------------|
| `/np-setup-orchestrator` | Checks status, offers to initialize if config is missing |
| `/np-setup-orchestrator init` | Step-by-step initial wizard |
| `/np-setup-orchestrator check-status` | Runs ALL checks |
| `/np-setup-orchestrator check-tools` | Verify installed tools |
| `/np-setup-orchestrator check-cloud` | Verify cloud access |
| `/np-setup-orchestrator check-k8s` | Verify Kubernetes access |
| `/np-setup-orchestrator check-np` | Verify Nullplatform API |
| `/np-setup-orchestrator check-telemetry` | Verify telemetry (logs and metrics) |
| `/np-setup-orchestrator check-services` | List services, offer to diagnose/modify/create |
| `/np-setup-orchestrator check-tf-key` | Verify common.tfvars (np_api_key) |

---

## Command: $ARGUMENTS

---

## If $ARGUMENTS is empty → Check Status and Initialization

### Flow

1. **Check if the project is initialized**

```bash
cat organization.properties 2>/dev/null
ls np-api-skill.key np-api-skill.token 2>/dev/null
ls -d infrastructure/ nullplatform/ nullplatform-bindings/ 2>/dev/null
ls common.tfvars infrastructure/*/terraform.tfvars nullplatform/terraform.tfvars nullplatform-bindings/terraform.tfvars 2>/dev/null
```

2. **If ANY of the base components are MISSING (checks 1-3)** → Use AskUserQuestion: "This repository is not fully configured for Nullplatform. Do you want to initialize?"
   - **Yes, initialize** → Run the `init` flow
   - **No, just show status** → Show summary of what's missing

3. **If EVERYTHING is configured** → Automatically run check-status to gain situational context. The report includes next step recommendations.

---

## If $ARGUMENTS is "init" → Step-by-Step Initial Wizard

### Pre-check

```bash
cat organization.properties 2>/dev/null
ls np-api-skill.key np-api-skill.token 2>/dev/null
ls -d infrastructure/ nullplatform/ nullplatform-bindings/ 2>/dev/null
ls common.tfvars 2>/dev/null
```

**If ALL components exist** → Show that it's already initialized and offer with AskUserQuestion:
- **Run full diagnostic** → `/np-setup-orchestrator check-status`
- **Configure infrastructure** → `/np-infrastructure-wizard`
- **Configure dimensions and scopes** → `/np-nullplatform-wizard`
- **Configure bindings** → `/np-nullplatform-bindings-wizard`

> If `check-status` was already run in the conversation, the first option should say "Re-run full diagnostic".

**If ANY component is MISSING** → Continue with the wizard.

---

### Step 1: Create organization

Check with `cat organization.properties`. If it doesn't exist, use AskUserQuestion:
- **Create a new organization** → Invoke `/np-organization-create`. Generates `organization.properties` automatically.
- **I already have an organization** → Request the NRN (found in Nullplatform UI). Extract the organization_id from the NRN (format: `organization=XXXX`) and create: `echo "organization_id={ORG_ID}" > organization.properties`

### Step 1b: Select or create Nullplatform Account

After having the organization, ask with AskUserQuestion:
- **I already have an account** → Ask for the account ID or NRN
- **I need to create a new account** → Ask for a Bearer token (Nullplatform UI → Profile picture → Copy personal access token), then ask for `name`, `slug`, and `repository_prefix`:

```bash
curl -s -L 'https://api.nullplatform.com/account' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "<account_name>",
    "slug": "<account_slug>",
    "organization_id": '"$ORG_ID"',
    "repository_prefix": "<prefix>",
    "status": "active",
    "repository_provider": "github"
  }'
```

The `repository_provider` defaults to `github` unless the user specifies otherwise.

**Domain**: The default application domain is `{account_slug}.nullapps.io`. Ask the user to confirm: "The application domain will be `{account_slug}.nullapps.io`. Is this correct, or do you want to use a different domain?". Do NOT offer invented alternatives.

Save the account info: `echo "account_id={ACCOUNT_ID}" >> organization.properties`

### Step 2: Configure authentication for skills

Check with `ls np-api-skill.key np-api-skill.token`. If it doesn't exist, guide:

A **single API Key** is used for everything (skills + Terraform). It's saved in `np-api-skill.key` and referenced from `common.tfvars`.

**IMPORTANT:** Do not use root API Keys or keys from other organizations. The key must belong to this organization.

1. Nullplatform UI → Platform Settings → API Keys
2. Create with:
   - **Scope:** Preferably at the **Account** level (more restrictive). Can also be at the Organization level.
   - **Roles:** Assign **these** roles: Admin, Agent, Developer, Ops, SecOps, Secrets Reader
3. `echo 'YOUR_API_KEY' > np-api-skill.key`
4. Export it for the current session so np-api and other skills can use it:
   ```bash
   export NP_API_KEY=$(cat np-api-skill.key)
   ```

Once created, automatically generate `common.tfvars` with the key (if applicable).

Verify that `np-api-skill.key` is in .gitignore. If not, add it.

### Step 3: Create file structure

Check with `ls -d infrastructure/ nullplatform/ nullplatform-bindings/`. If missing, create the structure directly.

Use AskUserQuestion for cloud provider: AWS, Azure (then AKS or ARO), GCP, OCI.

Create the following folder and file structure. The source of truth for each file's content is the `nullplatform/tofu-modules` repository (branch `main`):

```
{output}/
├── infrastructure/{cloud}/     # Cloud infrastructure (VPC, K8s, DNS, etc.)
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── locals.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── nullplatform/               # Central Nullplatform configuration
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── nullplatform-bindings/      # Connects Nullplatform with cloud + code repo
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── data.tf
│   ├── locals.tf
│   └── terraform.tfvars.example
├── common.tfvars.example
└── .gitignore
```

The `main.tf` files are NOT created in this step. They are dynamically generated in:
- `infrastructure/{cloud}/main.tf` → `/np-infrastructure-wizard`
- `nullplatform/main.tf` → `/np-nullplatform-wizard`
- `nullplatform-bindings/main.tf` → `/np-nullplatform-bindings-wizard`

### Step 4: Configure common variables

If `common.tfvars` doesn't exist, create it with default values and then let the user modify what they need.

**Procedure:**

1. Read the plain content of `np-api-skill.key` (use Read, not shell variables)
2. Generate `common.tfvars` with these defaults:

```hcl
nrn               = ""
np_api_key        = "<plain value read from np-api-skill.key>"
organization_slug = ""
tags_selectors = {
  "environment" = "development"
}
```

3. Show the user the generated file and ask with AskUserQuestion:

> I generated `common.tfvars` with default values. I need you to complete:
> - `nrn`: Resource NRN (e.g., `organization=123:account=456`)
> - `organization_slug`: Organization slug

4. Update the file with the values the user provides

| Variable | Default | Notes |
|----------|---------|-------|
| `np_api_key` | Read from `np-api-skill.key` | Auto-completed, do not ask the user |
| `nrn` | Empty | The user must provide it |
| `organization_slug` | Empty | The user must provide it |
| `tags_selectors` | `{ "environment" = "development" }` | Reasonable default, user can change it |

> The full `nrn` may not be available yet if it's a new org. Fill in partially and update later.

### Step 5: Configure cloud infrastructure

Invoke `/np-infrastructure-wizard` to configure the complete infrastructure (VPC, K8s, DNS, agent). Do NOT create terraform.tfvars manually.

### Step 6: Configure dimensions and scopes

Invoke `/np-nullplatform-wizard` to configure dimensions and scopes. Do NOT create terraform.tfvars manually.

### Step 7: Configure bindings

Invoke `/np-nullplatform-bindings-wizard` to configure bindings. Do NOT create terraform.tfvars manually.

### Step 8: Summary

Show a table with the status of all components and suggest `/np-setup-orchestrator check-status`.

---

## If $ARGUMENTS is "check-status" → Full Diagnostic

Runs ALL checks in sequence and generates a consolidated report.

### Sequence

1. check-tools
2. check-tf-key
3. check-cloud → see [references/check-cloud.md](references/check-cloud.md)
4. check-k8s → see [references/check-k8s.md](references/check-k8s.md)
5. check-np → see [references/check-np.md](references/check-np.md)
6. check-telemetry → see [references/check-telemetry.md](references/check-telemetry.md)
7. check-services → see [references/check-services.md](references/check-services.md)
8. Generate consolidated report with summary and suggested next step

### Recommendation Logic

| Condition | Recommendation |
|-----------|----------------|
| No organization.properties | `/np-organization-create` or `/np-setup-orchestrator init` |
| Expired token | Renew token and re-run |
| No cloud infrastructure | `/np-infrastructure-wizard` |
| Missing dimensions/scopes | `/np-nullplatform-wizard` |
| Missing bindings | `/np-nullplatform-bindings-wizard` |
| Last app/scope/deploy failed | `/np-setup-troubleshooting {type} {id}` (most recent) |
| No recent activity | Create application from Nullplatform UI |
| Empty system metrics | Verify agent telemetry configuration |
| Unregistered services | `/np-service-craft register <name>` |
| Services without binding | `/np-service-craft register <name>` (review bindings) |
| No services defined | `/np-service-craft create` to create a new one |
| Everything working | The complete flow is working correctly |

---

## If $ARGUMENTS is "check-tools" → Verify Tools

### Tools to Verify

| Tool | Command | Required |
|------|---------|----------|
| OpenTofu | `tofu version` | Yes (or Terraform) |
| Terraform | `terraform version` | Yes (or OpenTofu) |
| kubectl | `kubectl version --client` | Yes |
| jq | `jq --version` | Yes |

### Flow

```bash
tofu version 2>/dev/null || terraform version 2>/dev/null
kubectl version --client 2>/dev/null
jq --version 2>/dev/null
```

If any tool is missing, indicate how to install it.

---

## If $ARGUMENTS is "check-tf-key" → Verify Terraform API Key

Verify that `common.tfvars` exists and contains a valid `np_api_key`.

### Flow

1. **Verify the file exists**: `ls common.tfvars`. If it doesn't exist, indicate to create from `common.tfvars.example`.

2. **Validate the API Key**: run `${CLAUDE_PLUGIN_ROOT}/skills/np-setup-orchestrator/scripts/check-tf-api-key.sh`. If OK, key is valid. If ERROR, key is invalid: indicate to verify/recreate in UI.

3. **Verify gitignore**: `grep -q "common.tfvars" .gitignore`. If not present, warn (security risk).

### Recommendation Logic

| Condition | Recommendation |
|-----------|----------------|
| File doesn't exist | Create from `common.tfvars.example` |
| Invalid key | Verify/recreate API Key in UI |
| No permissions | Create new key with Administrator role |
| Not in gitignore | Add `common.tfvars` to `.gitignore` |
| All OK | Terraform API Key configured correctly |

---

## If $ARGUMENTS is "check-cloud" → Verify Cloud

See [references/check-cloud.md](references/check-cloud.md) for the complete flow.

---

## If $ARGUMENTS is "check-k8s" → Verify Kubernetes

See [references/check-k8s.md](references/check-k8s.md) for the complete flow.

---

## If $ARGUMENTS is "check-np" → Verify Nullplatform API

See [references/check-np.md](references/check-np.md) for the complete flow.

---

## If $ARGUMENTS is "check-telemetry" → Verify Telemetry

See [references/check-telemetry.md](references/check-telemetry.md) for the complete flow.

---

## If $ARGUMENTS is "check-services" → Verify Services

See [references/check-services.md](references/check-services.md) for the complete flow.
