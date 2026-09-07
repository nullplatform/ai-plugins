---
name: np-setup-orchestrator
description: Orchestrates the complete configuration of a Nullplatform organization. Use when you need to initialize a project, verify infrastructure/cloud/K8s/API status, diagnose issues, or run tool, cloud, Kubernetes, Nullplatform API, telemetry, and service checks.
---

# Nullplatform Setup Orchestrator

## Critical Rules

### Rule: Using np-api

**NEVER use `curl` directly to query the Nullplatform API (`api.nullplatform.com`).**

For ANY query to the Nullplatform API, you MUST use:

- `/np-api fetch-api "<endpoint>"` - For API queries
- `/np-api check-auth` - To verify authentication
- The `np-api` skill - For programmatic operations (invoke via `/np-api`)

**Allowed exceptions:**

- `curl` to deployed application endpoints (`*.nullapps.io`) for health checks
- `curl` to external services (AWS, Azure, GCP)
- **Account and API-key creation** (step 1b below, and `/np-organization-create`). These run
  before `NP_API_KEY` exists — there is no key for `/np-api` to authenticate with yet, so they
  are the one place a direct `curl` to `api.nullplatform.com` is correct. Everything after that
  point goes through `/np-api`.

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/ask-dont-infer-rule.md

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

## Dispatch

**Raw input**: `$ARGUMENTS`

Route on the **first whitespace-delimited token** of that input, not on the whole string. The
subcommand is one of: `init`, `check-status`, `check-tools`, `check-cloud`, `check-k8s`,
`check-np`, `check-telemetry`, `check-services`, `check-tf-key`.

- **No input** → the *empty* branch below.
- **First token is one of the subcommands** → that branch. Anything after it is free-text
  context (a target directory, a cloud, an NRN) — carry it into the flow, do not try to match it.
- **First token is anything else** → treat the whole input as context and take the *empty*
  branch, which starts by checking what is already configured. Say which branch you picked before
  running it.

> The branch headings below are literal. Do not expect them to contain the caller's input.

---

## Subcommand: (none) → Check Status and Initialization

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

## Subcommand: `init` → Step-by-Step Initial Wizard

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

**The domain is asked in step 4**, not here — it is needed on both paths of this step (existing
account and new account), and step 4 is where `common.tfvars` is written.

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

Create the folder structure below. **Create the directories only** — do not try to source the
`.tf` files from anywhere. `tofu-modules` holds modules, not layer scaffolding: it has no
layer-level `variables.tf`, `provider.tf` or `backend.tf` to copy, and its only `templates/`
directories belong to `nullplatform/agent` and `nullplatform/base`.

Each layer's `.tf` files are **generated** by that layer's wizard from the module contracts it
reads out of `.terraform/modules/` after `tofu init -backend=false` — which is what rule 3 of
`np-infrastructure-wizard`'s `references/infrastructure-generation.md` requires, and why the
generated code matches the pinned module version instead of a snapshot in a document.

The file names below are the expected end state, not files to create now:

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
nrn                 = ""
np_api_key          = "<plain value read from np-api-skill.key>"
organization_slug   = ""
domain_name         = ""
private_domain_name = ""
tags_selectors = {
  "environment" = "development"
}
```

3. Ask the user for the empty ones with AskUserQuestion. **Ask — do not fill any of them in from
   the environment or from the account slug.** For the two domains, offer the convention as a
   default the user confirms or replaces:

> `nrn` — Resource NRN, e.g. `organization=123:account=456`
>
> `organization_slug` — the slug as it exists in the nullplatform API, not a free-form label
>
> `domain_name` — the **public** application domain. For an internal PoC the convention is
> `{account_slug}.nullapps.io`; offer that as a default. A client that owns its own domain uses
> theirs instead. **This is also what the DNS delegation in the infrastructure layer depends on**,
> so a wrong value here surfaces much later, as a certificate that never issues.
>
> `private_domain_name` — the **private** domain backing the internal gateway. The right value is
> cloud-dependent, so read the cloud's reference before suggesting one: GCP wants the *same value*
> as `domain_name` (split horizon), and on Azure it has to sit inside the public zone. If the setup
> has no internal gateway, say so and leave it empty rather than inventing a value.

4. Update the file with the values the user provides

| Variable | Default | Notes |
|----------|---------|-------|
| `np_api_key` | Read from `np-api-skill.key` | Auto-completed, do not ask the user |
| `nrn` | Empty | **Ask.** Never read it from `~/.np` or a cached session |
| `organization_slug` | Empty | **Ask.** Never infer it from the only org the caller can see |
| `domain_name` | Empty | **Ask**, offering `{account_slug}.nullapps.io` as a default to confirm |
| `private_domain_name` | Empty | **Ask.** Cloud-dependent — check the cloud's reference first |
| `tags_selectors` | `{ "environment" = "development" }` | Reasonable default, user can change it |

> **Both domains are read by all three layers**, which is why they live here. And the values must
> exist before `/np-infrastructure-wizard` runs: its DNS step and its `cert_manager` wiring both
> consume them, so an empty `domain_name` fails the layer rather than prompting again.

> The full `nrn` may not be available yet if it's a new org. Fill in partially and update later.

### Step 5: Configure cloud infrastructure

Invoke `/np-infrastructure-wizard` to configure the complete infrastructure (VPC, K8s, DNS, agent). Do NOT create terraform.tfvars manually.

### Step 6: Configure dimensions and scopes

Invoke `/np-nullplatform-wizard` to configure dimensions and scopes. Do NOT create terraform.tfvars manually.

### Step 7: Configure bindings

Invoke `/np-nullplatform-bindings-wizard` to configure bindings. Do NOT create terraform.tfvars manually.

> **The scope/service selection is made once and governs all three layers.** It is captured in Step 5
> (`/np-infrastructure-wizard`) as `enable_<catalog_slug>` toggles in `common.tfvars`, and steps 6 and 7
> read them from there — do not ask again, and do not let a layer keep its own copy.
>
> Each layer contributes a different piece for the same entry: `infrastructure/` creates its
> permissions role and clones its repo into the agent; `nullplatform/` registers its spec;
> `nullplatform-bindings/` routes its channel and publishes its IAM selector. Changing the selection
> later means re-applying all three, in order —
> `infrastructure/` → `nullplatform/` → `nullplatform-bindings/` — because each layer's outputs feed
> the next. Applying only one leaves a scope that registers cleanly and fails on its first deploy.

### Step 8: Summary

Show a table with the status of all components and suggest `/np-setup-orchestrator check-status`.

---

## Subcommand: `check-status` → Full Diagnostic

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

## Subcommand: `check-tools` → Verify Tools

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

## Subcommand: `check-tf-key` → Verify Terraform API Key

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

## Subcommand: `check-cloud` → Verify Cloud

See [references/check-cloud.md](references/check-cloud.md) for the complete flow.

---

## Subcommand: `check-k8s` → Verify Kubernetes

See [references/check-k8s.md](references/check-k8s.md) for the complete flow.

---

## Subcommand: `check-np` → Verify Nullplatform API

See [references/check-np.md](references/check-np.md) for the complete flow.

---

## Subcommand: `check-telemetry` → Verify Telemetry

See [references/check-telemetry.md](references/check-telemetry.md) for the complete flow.

---

## Subcommand: `check-services` → Verify Services

See [references/check-services.md](references/check-services.md) for the complete flow.
