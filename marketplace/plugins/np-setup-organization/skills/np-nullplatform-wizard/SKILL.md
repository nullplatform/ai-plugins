---
name: np-nullplatform-wizard
description: This skill should be used when the user asks to "configure nullplatform resources", "setup dimensions", "create service definitions", "configure scope types", or needs to configure core nullplatform resources including scopes, dimensions, service definitions and governance checklists/workflows via Terraform.
---

# Nullplatform Config Wizard

Configures Nullplatform resources: scopes, dimensions, service definitions and, optionally, governance cases (approval checklists + workflows).

## Critical Rules

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/rules/iac-rule.md

## Scope and service repositories

Each scope and service lives in its own repo, so every catalog entry in this layer needs its
`repository_org`, `repository_name`, `version` and `service_path`:

@${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md

## When to Use

- Configuring scope definitions (deployment targets)
- Creating environment dimensions (dev/staging/prod)
- Registering service definitions
- Configuring metadata schemas and policies
- Adding governance cases (approval checklists + workflows)

## Prerequisites

1. Verify that `organization.properties` exists and has the organization_id
2. Invoke `/np-api check-auth` to verify authentication

## Reference Templates

Templates are in `nullplatform/example/` - **NOT APPLIED DIRECTLY**.

```text
nullplatform/
├── example/                    # Reference templates
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── *.tf                        # Your actual implementation (when created)
```

## What Gets Created

### Scope Definitions

Defines how applications are deployed on Kubernetes:

| Scope | Description | Actions |
| ----- | ----------- | ------- |
| **K8s Containers** | Standard containers | create, delete, deploy, rollback |
| **Scheduled Tasks** | Periodic jobs | create, delete, deploy, trigger |

### Dimensions

Environment classification for scopes:

| Dimension | Description |
| --------- | ----------- |
| `development` | Development environments |
| `staging` | Pre-production |
| `production` | Real traffic |

### Service Definitions

Templates for creating cloud services:

| Service | Type | Description |
| ------- | ---- | ----------- |
| Endpoint Exposer | dependency | Exposes application endpoints |
| (Custom services) | dependency | Can be added in second iteration |

### Governance cases (Optional)

Approval checklists (and the workflow that resolves them, when needed), applied by `tofu apply`
through `workflow_checklist.tf`. The user picks which ones in step 5:

| Case | Rule |
| ---- | ---- |
| `prod_deploy_gate` | Checks before a production deploy, each one gate or informational: release running in lower environments, allowed source branch, minimum code coverage, no critical vulnerabilities |
| `nonprod_sizing` | Non-prod scopes: autoscaling off, max 128 MB, max 1 instance |

### Metadata Schemas (Optional)

Metadata specifications picked by the user in step 4: application fields shown when creating and
editing an application (Owner, Business Unit, SLA, Environment) and build results reported by CI
(Coverage, Security). Generated as `metadata.tf` + `metadata.json`.

## Wizard Workflow

### 1. Verify no configuration exists

```bash
ls nullplatform/*.tf 2>/dev/null || echo "No configuration exists - proceed"
```

### 2. Copy templates (except main.tf and metadata.tf)

```bash
# Copy all templates EXCEPT main.tf (generated dynamically) and metadata.tf (generated in step 4)
for f in nullplatform/example/*.tf; do
  case "$(basename "$f")" in main.tf|metadata.tf) continue ;; esac
  cp "$f" nullplatform/
done
```

> **Note**: Templates include the optional file `policies.tf` - Approval policies (requires
> `nrn_namespace`, not account). If you don't need it or it causes errors, rename it:
> ```bash
> mv nullplatform/policies.tf nullplatform/policies.tf.disabled
> ```

### 3. Generate or customize main.tf

The nullplatform `main.tf` is generated dynamically following [references/nullplatform-generation.md](references/nullplatform-generation.md).

1. **Check if `nullplatform/main.tf` exists**

   ```bash
   ls nullplatform/main.tf 2>/dev/null
   ```

   - **If it does NOT exist** -> Read [references/nullplatform-generation.md](references/nullplatform-generation.md) and follow its complete flow (user questions, module patterns, outputs mapping, validation)
   - **If it exists** -> Ask with AskUserQuestion:
     - **Regenerate from scratch** -> Delete the current one, read [references/nullplatform-generation.md](references/nullplatform-generation.md) and follow its flow
     - **Customize the existing one** -> Read the current main.tf and ask what changes to make
     - **Leave it as is** -> Go to step 4

2. After generating/modifying, validate:

   ```bash
   cd nullplatform
   tofu init -backend=false
   tofu validate
   ```

3. If `tofu validate` fails, fix BEFORE continuing with step 4.

### 4. Metadata

Ask whether to add metadata and which specifications, and generate `metadata.tf` +
`metadata.json` following [references/metadata.md](references/metadata.md). If the user picks
"No metadata", skip this step: no file is copied.

### 5. Governance cases (workflows + checklists)

Ask which governance cases to add and generate them following
[references/governance-cases.md](references/governance-cases.md). If the user picks "None",
skip this step: no file is copied.

### 6. Customize variables

The wizard helps you configure:

- `organization_id` (from organization.properties)
- `environments` (list of dimensions)
- `tags_selectors` (for matching)

### 7. Apply

```bash
cd nullplatform
tofu init
tofu apply
```

## Required Variables

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `organization_id` | Organization ID | organization.properties |
| `np_api_key` | Nullplatform API key | NP_API_KEY/np-api-skill.key (recommended) |
| `environments` | List of dimensions | terraform.tfvars |
| `tags_selectors` | Tags for matching | terraform.tfvars |
| `governance_cases` | Governance cases to apply (optional, default none) | terraform.tfvars |
| `governance_nrn` | Where governance cases are created (optional, default `nrn`) | terraform.tfvars |

## Outputs

After applying, these values are exported for use in bindings:

```hcl
# K8s Scope
service_specification_id           # Service spec ID
service_slug                       # Service spec slug

# Scheduled Task Scope
service_specification_id_scheduled_task
service_slug_scheduled_task

# Endpoint Exposer
service_specification_slug_endpoint_exposer
service_specification_id_endpoint_exposer
```

## Validation

Verify that resources were created:

Invoke `/np-api` to query:

| Required information | Entity to query |
|---------------------|-----------------|
| Service specifications | service_specifications of the organization |
| Configured dimensions | dimensions of the organization |

## Troubleshooting

### Service Spec doesn't appear

- Verify `organization_id` in organization.properties
- Verify authentication with check_auth.sh

### Dimension doesn't get created

- Verify that a dimension with the same name doesn't already exist
- Review terraform logs

## Next Step

Once Nullplatform is configured, connect with external services:

**Tell Claude**: "Let's configure the bindings"

Or invoke directly: `/np-nullplatform-bindings-wizard`
