# Create Service Flow

## Path A: From Reference Example

Use the reference repository defined in `np-service-guide` (Reference Repository section).

1. **Clone/update reference repo**:
   ```bash
   git clone https://github.com/nullplatform/services /tmp/np-services-reference 2>/dev/null \
     || (cd /tmp/np-services-reference && git pull)
   ```
2. **List available examples** (dynamically):
   ```bash
   find /tmp/np-services-reference -name "service-spec.json.tpl" -not -path "*/.git/*" | \
     xargs -I{} sh -c 'echo "---"; dirname {} | sed "s|/tmp/np-services-reference/||"; jq "{name, slug, selectors}" {}'
   ```
3. **AskUserQuestion**: offer found examples + "Other (create new service)"
4. **Copy structure** from reference to local repo:
   ```bash
   cp -r /tmp/np-services-reference/<path-to-example>/ services/<new-slug>/
   ```
5. **AskUserQuestion — Credential strategy** (if the service has links on a cloud provider):
   Ask how linked applications should authenticate to the provisioned resource:
   - **IAM User (access keys) (Default)**: Creates a dedicated IAM user per link, exporting `access_key_id` + `secret_access_key` as env vars. Works across any compute environment (not tied to Kubernetes). Uses `aws_iam_user` + `aws_iam_access_key` in `permissions/`.
   - **IAM Role (IRSA)**: Creates an IAM role per link with OIDC trust policy for the app's Kubernetes service account. More secure (no static credentials), but **only works if the scope infrastructure creates a dedicated K8s ServiceAccount per app** with an associated IAM role (i.e., `app_role_name` must be populated in the scope/entity attributes). Requires EKS + OIDC provider. If the scope doesn't manage per-app ServiceAccounts, this strategy will fail silently.
   - **Keep both as options**: Adds an `auth_method` field (e.g., `iam_user` or `iam_role`) to the link spec schema, allowing users to choose per-link. Both `build_permissions_context` and `permissions/main.tf` must include conditional logic to handle both strategies based on this field's value. This is a proposed convention — no existing infrastructure supports it yet.
   This is a **mandatory question** — never default to one strategy without asking. The choice affects: `permissions/` (and `permissions/variables.tf`), `specs/links/connect.json.tpl`, `scripts/<provider>/build_permissions_context`, `scripts/<provider>/write_link_outputs`, `workflows/<provider>/link.yaml`, `workflows/<provider>/link-update.yaml`, `workflows/<provider>/unlink.yaml`, and `values.yaml`.
   > **Note**: For Azure providers, the equivalent choice is Service Principal keys vs Managed Identity. For GCP, it is Service Account keys vs Workload Identity. Apply the same question pattern adapted to the cloud provider.
6. **Adapt files**:
   - `specs/service-spec.json.tpl`: change name, slug, adjust schema
   - `specs/links/connect.json.tpl`: adjust selectors and credential fields based on auth strategy
   - `values.yaml`: update config values (add `eks_oidc_provider_arn` or `eks_cluster_name` if IRSA)
   - `entrypoint/service` and `entrypoint/link`: verify provider path
   - `deployment/main.tf`: adjust resources for chosen variants
   - `permissions/main.tf` and `permissions/variables.tf`: IAM user or IAM role based on credential strategy
   - `workflows/<provider>/link.yaml`, `link-update.yaml`: adjust steps (IRSA may not need `write_link_outputs`)
7. **Show summary** and suggest `/np-service-craft register <slug>`

## Path B: New Service (Research-First Guided Discovery)

The flow investigates first and proposes smart defaults. The user confirms or adjusts instead of designing from scratch.

### Phase 1: What is the service?

AskUserQuestion: "Describe what service you want to create" (free text)

### Phase 2: Research

**BEFORE asking more questions**, investigate:

1. **Clone reference repo** (see np-service-guide, Reference Repository) and search for a service similar to what the user described. Read its spec, deployment, and workflows to understand the pattern.

2. **Search for relevant terraform provider documentation** (via web if necessary) to understand what resources exist, what parameters they have, and what are reasonable defaults.

3. **Build a proposal** with:
   - Suggested slug and name
   - Inferred provider and category
   - List of spec fields with types, defaults, and whether they're required
   - Which fields are output (post-provisioning) vs input (user chooses)
   - If it has links, what access levels and what credentials it exposes
   - What terraform resources it will create

### Phase 3: Propose and Confirm

Present the complete proposal to the user with AskUserQuestion. Each question should have a **pre-researched default**. Example:

> Based on AWS S3 documentation and the reference service `azure-cosmos-db`, I propose:
>
> **Name**: AWS S3 Bucket | **Slug**: `aws-s3-bucket` | **Provider**: AWS | **Category**: Storage
>
> **Spec fields (what the user sees when creating)**:
> - `bucket_name` (string, required) - Bucket name
> - `region` (enum: us-east-1, us-west-2, eu-west-1, default: us-east-1)
> - `versioning` (boolean, default: true)
> - `encryption` (boolean, default: true)
>
> **Output fields (auto-populated post-creation)**:
> - `bucket_arn` (export: true)
> - `bucket_region` (export: true)
>
> **Link (connect)**: access levels read / write / read-write
> - Credentials: determined by auth strategy (next question)
>
> Do you want to adjust anything?

The user only says "yes" or tweaks what they need. They don't have to design anything from scratch.

**After confirming the proposal**, AskUserQuestion for **credential strategy** (if the service has links on a cloud provider):
- **IAM User (access keys) (Default)**: Creates a dedicated IAM user per link, exporting `access_key_id` + `secret_access_key` as env vars. Works across any compute environment (not tied to Kubernetes). Uses `aws_iam_user` + `aws_iam_access_key` in `permissions/`.
- **IAM Role (IRSA)**: Creates an IAM role per link with OIDC trust policy for the app's Kubernetes service account. More secure (no static credentials), but **only works if the scope infrastructure creates a dedicated K8s ServiceAccount per app** with an associated IAM role (i.e., `app_role_name` must be populated in the scope/entity attributes). Requires EKS + OIDC provider. If the scope doesn't manage per-app ServiceAccounts, this strategy will fail silently.
- **Keep both as options**: Adds an `auth_method` field (e.g., `iam_user` or `iam_role`) to the link spec schema, allowing users to choose per-link. Both `build_permissions_context` and `permissions/main.tf` must include conditional logic to handle both strategies based on this field's value. This is a proposed convention — no existing infrastructure supports it yet.

This is a **mandatory question** — never default to one strategy without asking. The choice affects: `permissions/` (and `permissions/variables.tf`), `specs/links/connect.json.tpl`, `scripts/<provider>/build_permissions_context`, `scripts/<provider>/write_link_outputs`, `workflows/<provider>/link.yaml`, `workflows/<provider>/link-update.yaml`, `workflows/<provider>/unlink.yaml`, and `values.yaml`.

> **Note**: For Azure providers, the equivalent choice is Service Principal keys vs Managed Identity. For GCP, it is Service Account keys vs Workload Identity. Apply the same question pattern adapted to the cloud provider.

### Phase 4: Generate Files

With the confirmed proposal, generate all files using `np-service-specs` and `np-service-workflows` for conventions. Use the reference service as a base for templates (workflows, scripts, entrypoint) adapting to the specific provider and resources.

**Critical: Instance name fallback** — In `build_context`, the `INSTANCE_NAME` used for cloud resource naming MUST have a fallback to `SERVICE_ID` when `.service.name` sanitizes to empty. See `np-service-workflows` docs/build-context-patterns.md "Instance Name Sanitization". If the service has a user-provided name parameter (e.g., `bucket_name_suffix`), prefer that over `.service.name`.

### Phase 7: Validate

```bash
SLUG="<slug>"
# Schema in attributes.schema
jq -e '.attributes.schema.type' services/$SLUG/specs/service-spec.json.tpl
# No specification_schema
jq -e '.specification_schema' services/$SLUG/specs/service-spec.json.tpl && echo "ERROR" || echo "OK"
# Links use attributes.schema
for f in services/$SLUG/specs/links/*.json.tpl; do jq -e '.attributes.schema' "$f"; done
# Valid JSON
jq . services/$SLUG/specs/*.json.tpl services/$SLUG/specs/links/*.json.tpl
# Scripts executable
chmod +x services/$SLUG/entrypoint/* services/$SLUG/scripts/*/
# Entrypoint has bridge
grep -q "NULLPLATFORM_API_KEY" services/$SLUG/entrypoint/entrypoint || echo "ERROR: missing bridge"
# build_context merges parameters
grep -q 'parameters' services/$SLUG/scripts/*/build_context || echo "WARNING: missing parameters merge"
```

Show summary and suggest `/np-service-craft register <slug>`.
