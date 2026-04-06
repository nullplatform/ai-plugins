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
5. **Adapt files**:
   - `specs/service-spec.json.tpl`: change name, slug, adjust schema
   - `specs/links/connect.json.tpl`: adjust selectors
   - `values.yaml`: update config values
   - `entrypoint/service` and `entrypoint/link`: verify provider path
   - `deployment/main.tf`: adjust resources for chosen variants
6. **Show summary** and suggest `/np-service-craft register <slug>`

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
> - Credentials: `access_key_id` (export), `secret_access_key` (export secret)
>
> Do you want to adjust anything?

The user only says "yes" or tweaks what they need. They don't have to design anything from scratch.

### Phase 4: Generate Files

With the confirmed proposal, generate all files using `np-service-specs` and `np-service-workflows` for conventions. Use the reference service as a base for templates (workflows, scripts, entrypoint) adapting to the specific provider and resources.

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
