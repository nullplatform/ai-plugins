# Create Service Flow

## Orientation: what gets generated, and where you change it

For the repo layout see `service-structure.md`, loaded alongside this file.

| To change… | Edit |
|---|---|
| The fields a developer sees | `service-spec.json.tpl` → `attributes.schema.properties` |
| How those fields are laid out | same file → `attributes.schema.uiSchema` |
| Which are mandatory | → `attributes.schema.required` |
| What the application receives as env vars | the property's `export: { target: "DB_HOST" }` |
| Category / provider in the catalogue | → `selectors` |
| Which cloud resource is created | `deployment/main.tf` |
| Which actions exist | `use_default_actions: true` generates them; `workflows/<provider>/*.yaml` implements them |
| What an action does | that action's YAML plus the scripts it calls |
| How inputs reach tofu | `scripts/<provider>/build_context` |
| What flows back to nullplatform | `deployment/outputs.tf` + `scripts/<provider>/write_service_outputs` |
| Permissions granted on link | `permissions/main.tf` |
| Region, profiles, fixed names | `values.yaml` |

### Two propagation paths — the distinction that bites

**Specs are read from the repository (or `local_specs_path`) on every `apply`.** Change the
schema, the uiSchema, the selectors or the links and a `tofu apply` is enough — no rebuild.

**Everything else lives inside the image**: `scripts/`, `workflows/`, `deployment/`,
`permissions/`, `values.yaml`. Change any of those and you need rebuild → new digest → bump
`package.version` → apply.

Edit a script and only run `apply` and nothing happens: the worker keeps executing what is
baked in. It is the easiest mistake to make and the most confusing to diagnose.

**CI mode has one path only**: the runner checks the repo out at the channel's `reference`,
so a push (or a re-pointed tag) changes scripts, workflows and Terraform at once, and the
spec changes with whatever registered it (Terraform or API). Nothing is baked anywhere.

Existing service instances never move — each is bound for life to the revision it was born
with, so a new version applies only to instances created after it.

To iterate quickly, use `git_provider = "local"` with `local_specs_path`: register and test
without pushing a repo or minting a token.

## Before the code: execution mode, then repository

**Execution mode first** (`execution-modes.md`): look at the NRN's agents and channels, then
ask with `AskUserQuestion` — **Agent** (image + package + agent channel) or **CI** (the
client's workflow, `github` channel). It decides whether a `Dockerfile` is generated, which
`register` flow follows, and how `test` works. In CI mode also read the client's workflow to
learn the repository layout it expects before copying any reference.

Then the repository. Ask it (`AskUserQuestion`). If nullplatform will publish the service, it gets its own
`services-<slug>` repo from `nullplatform/templates-services`:

1. Create the application from that template with **Repository visibility = public** in the
   form. It defaults to private and can't be changed later from nullplatform — patching the
   metadata does not touch GitHub; a private repo needs an org admin.
2. Scaffold the slug (template README, "Start here"): `git mv my-service <slug>`, replace
   `my-service` everywhere, set the display name and the `selectors` (`category`,
   `sub_category`, `provider`) in the service **and** link specs — the template's
   `Other` / `Other` / `AWS` is what the catalog and the docs page would show — and check `image_name` in `release.yml`,
   `beta.yml` (`beta/` + the same) and `trivy.yml`. Commit it as `chore:`. The repo name
   must start with `services-` — the docs index finds repos by that prefix.
3. Publishing setup (Public ECR service, `NP_ARTIFACT_NRN`, betas): → `/np-package-builder`,
   `docs/worker-bridge.md`, "nullplatform's own agent plugins".
4. **Catalog-ready check, before the first `feat:`/`fix:` release.** What the docs index and
   the nullplatform catalog show comes from this repo, so confirm every item and fix the gaps
   with the user (`AskUserQuestion` for the values only they can decide):

   | Item | Where | Check |
   |---|---|---|
   | Repo public | GitHub | `gh api repos/nullplatform/<repo> --jq .visibility` → `public` |
   | Name | GitHub | starts with `services-` |
   | Name, slug | `<slug>/specs/service-spec.json.tpl` | not `My Service` / `my-service`; the slug never changes after release |
   | Selectors | service spec **and** `specs/links/*.json.tpl` | real `category` / `sub_category` / `provider`, not `Other` |
   | Path | repo layout | the directory holding `specs/` — it is the `service_path` the docs table will show |
   | `image_name` | `release.yml`, `beta.yml`, `trivy.yml` | aligned, no `my-service` |
   | Publishing | repo settings | `AWS_ROLE_ARN_ECR_PUSH` (Public ECR service) and `NP_ARTIFACT_NRN` set |

   The template's release preflight runs the same placeholder checks
   (`python3 .github/scripts/check-scaffold.py`); run it locally first so CI doesn't find them.

Then write the code with Path A or B **inside the scaffolded `<slug>/`** — keep the
template's CI, don't copy a reference repo's over it. Customer or local-only services skip
this section.

## Path A: From Reference Example

Each sample service lives in its own repo. See the Reference Repositories section in
`np-service-guide` for the resolution flow.

1. **Pick the reference from the docs table**, not by crawling repos: read the **Samples**
   table of Sample services as the catalog explains (`${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`) and
   offer the closest rows with `AskUserQuestion` (name — it carries the platform —, category) + "Other (create new
   service)". Each row's Repository cell gives `repo/path` of that service.
2. **Clone only that repo, at its resolved tag** (catalog, notes 3–3a):
   ```bash
   git clone --depth 1 --branch <tag> https://github.com/nullplatform/<repo>.git /tmp/np-<repo>-reference
   ```
3. **Read its specs at the row's path**: `/tmp/np-<repo>-reference/<path>/specs` (`.` = repo root).
4. **Copy structure** from reference to local repo:
   ```bash
   cp -r /tmp/np-<repo>-reference/<path>/ services/<new-slug>/
   ```
5. **AskUserQuestion — Credential strategy** (if the service has links on a cloud provider):
   Ask how linked applications should authenticate to the provisioned resource:
   - **IAM User (access keys) (Default)**: Creates a dedicated IAM user per link, exporting `access_key_id` + `secret_access_key` as env vars. Works across any compute environment (not tied to Kubernetes). Uses `aws_iam_user` + `aws_iam_access_key` in `permissions/`.
   - **IAM Role (IRSA)**: Creates an IAM role per link with OIDC trust policy for the app's Kubernetes service account. More secure (no static credentials), but **only works if the scope infrastructure creates a dedicated K8s ServiceAccount per app** with an associated IAM role (i.e., `app_role_name` must be populated in the scope/entity attributes). Requires EKS + OIDC provider. If the scope doesn't manage per-app ServiceAccounts, this strategy will fail silently.
   - **Keep both as options**: Adds an `auth_method` field (e.g., `iam_user` or `iam_role`) to the link spec schema, allowing users to choose per-link. Both `build_permissions_context` and `permissions/main.tf` must include conditional logic to handle both strategies based on this field's value. This is a proposed convention — no existing infrastructure supports it yet.
   This is a **mandatory question** — never default to one strategy without asking. The choice affects: `permissions/` (and `permissions/variables.tf`), `specs/links/connect.json.tpl`, `scripts/<provider>/build_permissions_context`, `scripts/<provider>/write_link_outputs`, `workflows/<provider>/link.yaml`, `workflows/<provider>/link-update.yaml`, `workflows/<provider>/unlink.yaml`, and `values.yaml`.
   > **Note**: For Azure providers, the equivalent choice is Service Principal keys vs Managed Identity. For GCP, it is Service Account keys vs Workload Identity. Apply the same question pattern adapted to the cloud provider.
6. **Adapt files**:
   - `specs/service-spec.json.tpl`: change name, slug, adjust schema — **and the `uiSchema`
     inside `attributes.schema`**. It is a separate JSONForms structure whose `Control`
     entries point at properties by path (`#/properties/<name>`). Change the properties and
     leave it alone and it references fields that no longer exist: terraform applies, the API
     accepts the spec, and the failure surfaces only in the UI, to the end user, as
     "Unknown field #/properties/…". No `tofu validate` or `jq` check catches it. Rewrite it
     to match the new properties, or drop it and let the renderer lay the form out itself.
   - `specs/links/connect.json.tpl`: adjust selectors and credential fields based on auth strategy
   - `values.yaml`: update config values (add `eks_oidc_provider_arn` or `eks_cluster_name` if IRSA)
   - `entrypoint/service` and `entrypoint/link`: verify provider path
   - `deployment/main.tf`: adjust resources for chosen variants
   - `permissions/main.tf` and `permissions/variables.tf`: IAM user or IAM role based on credential strategy
   - `workflows/<provider>/link.yaml`, `link-update.yaml`: adjust steps (IRSA may not need `write_link_outputs`)
   - `Dockerfile` **at the repo root** (agent mode only — CI mode ships no image): built on
     `public.ecr.aws/nullplatform/scopes/worker-bridge`, installing the tools this service
     needs, then `COPY . /app/pkg` and the three `NP_*` env vars. If the reference service
     predates the package model it has no Dockerfile — take the template and the image
     contract from `/np-package-builder`, set the slug, and install only the tools this
     service's `scripts/<provider>/` actually calls.
7. **Show summary** and suggest `/np-service-craft register <slug>`

> Note: a reference service may still be built for the legacy command-executor flow, where
> the agent cloned its repo. Copy its structure and logic, not that assumption — a new
> service in agent mode ships as an image. → `@${CLAUDE_PLUGIN_ROOT}/skills/np-service-creator/docs/packaged-service.md`
> In CI mode the same structure is checked out by the runner; keep the entrypoint (the bridge
> is harmless there) so the service can move between modes without code changes.

## Known bugs in the reference implementations

Verified in `services-rds` (now `services-postgresql-rds`). Copying a reference inherits these — fix them in your copy.

**`entrypoint/link` does not map `update`.** Its `case` handles `custom`, `create` → `link`
and `delete` → `unlink`, so `update` falls through unmapped and runs `workflows/<provider>/update.yaml`
— the **service's** update workflow, which re-applies the `deployment` module instead of the
link's permissions. Add an `"update") ACTION_TO_EXECUTE="link-update" ;;` case.

**`delete.yaml` never declares `TFSTATE_BUCKET`.** The workflow has a "cleanup tfstate
bucket" step and the `delete_tfstate_bucket` script exists, but the build-context step's
`output:` block omits the variable. The script sees it empty, prints "skipping" and exits 0,
leaving an orphaned bucket behind every delete. Declare it in that `output:` block.

**A workflow step's `output:` block is the propagation boundary, not the script's `export`.**
`build_context` exports `TOFU_MODULE_DIR="$SERVICE_PATH/deployment"`, but the link workflows
deliberately leave it out of that step's `output:` — only `build_permissions_context`
propagates it, pointing at `permissions`. Add `TOFU_MODULE_DIR` to a link workflow's
build-context output and a later `tofu destroy` on unlink inherits the **deployment** module
and destroys the real resource. Leaving it undeclared makes `do_tofu` fail loudly on an
unbound variable instead, which is the intended behaviour.

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

### Phase 5: Validate

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
# Entrypoint has bridge (required in agent mode; harmless and still recommended in CI mode)
grep -q "NULLPLATFORM_API_KEY" services/$SLUG/entrypoint/entrypoint || echo "ERROR: missing bridge"
# build_context merges parameters
grep -q 'parameters' services/$SLUG/scripts/*/build_context || echo "WARNING: missing parameters merge"
# name, slug and selectors must be filled: the nullplatform catalog and the docs
# Sample services page show them, and the docs sync skips or flags a spec without them.
for f in $(find services/$SLUG -path '*/specs/service-spec.json.tpl'); do
  for k in name slug category sub_category provider; do
    grep -qE "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$f" || echo "ERROR $f: $k is missing or empty"
  done
  grep -qE '"name"[[:space:]]*:[[:space:]]*"My (Service|Scope)"' "$f" && echo "ERROR $f: name is still the template's"
  grep -qE '"category"[[:space:]]*:[[:space:]]*"Other"' "$f" && grep -qE '"sub_category"[[:space:]]*:[[:space:]]*"Other"' "$f" \
    && echo "ERROR $f: selectors are still the template's (Other / Other)"
done
for f in $(find services/$SLUG -path '*/specs/links/*.json.tpl'); do
  grep -q '"selectors"' "$f" || echo "WARNING $f: link without selectors (use the service's)"
done
```

Any `ERROR` from the last block blocks the service: ask the user for the missing value with
`AskUserQuestion` (name, category, sub-category, provider) — never invent one and never leave
the template's. This applies to every path (template, A and B) and to `modify` too.

Show summary and suggest `/np-service-craft register <slug>` — it follows
`register-service.md` or `register-service-ci.md` according to the mode chosen above.
