# Register Service in Terraform

## Prerequisites

- `services/<name>/specs/service-spec.json.tpl` must exist and be valid JSON
- The `nullplatform/` and `nullplatform-bindings/` directories must exist with terraform configured

## Terraform Base Structure

Registration uses two separate terraform directories at the repo root:

- **`nullplatform/`** — Service definitions. Contains the `service_definition` modules (one per service), outputs, variables (`nrn`, `np_api_key`), nullplatform provider, and `common.tfvars` with values.
- **`nullplatform-bindings/`** — Agent associations. Contains the `service_definition_agent_association` modules (one per service), variables (`nrn`, `np_api_key`, `tags_selectors`), nullplatform provider, and a `data.tf` that reads the state from `nullplatform/` via `terraform_remote_state` to access outputs (slug, id).

These are two separate directories because the binding needs the `service_specification_slug` as output from the service_definition. They are applied in order: first `nullplatform/`, then `nullplatform-bindings/`.

If the directories don't exist, create them with the base files (providers.tf, variables.tf, common.tfvars, data.tf). Ask the user for the `nrn` and `np_api_key` if they don't have them.

## Module Source of Truth

The modules live in `https://github.com/nullplatform/tofu-modules`:
- `nullplatform/service_definition` — creates service_specification + link_specification
- `nullplatform/service_definition_agent_association` — creates notification_channel

**BEFORE generating terraform**, clone the repo and read each module's `variables.tf` to determine mandatory and optional variables:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Also read `main.tf` and `locals.tf` to understand how resources are built internally.

## Flow

### 1. Read service spec

```bash
jq '{name, slug, selectors}' services/<name>/specs/service-spec.json.tpl
```

### 2. Check for duplicates and collisions

**2a. Check not already registered in terraform:**

```bash
grep -c "service_definition_<slug>" nullplatform/main.tf
```

**2b. Check for name/slug collisions in the remote repository** (Remote mode only):

Before pushing or registering, verify that no existing service in the remote repo uses the same slug or directory path. This prevents accidental overwrites and confusing slug collisions in nullplatform.

```bash
# Check if the service path already exists in the remote repo
git ls-remote --exit-code origin HEAD -- "services/<slug>/" 2>/dev/null
# Or if repo is already cloned:
git fetch origin main && git ls-tree -r --name-only origin/main | grep "^services/<slug>/"
```

If a collision is found:
- **Same slug exists in remote**: Inform the user that `services/<slug>/` already exists in the remote repository. Ask with AskUserQuestion whether they want to:
  - **Overwrite**: Replace the existing service (confirm this is intentional — the previous version will be lost)
  - **Rename**: Choose a different slug (suggest alternatives like `<slug>-v2`, `<provider>-<slug>`, etc.)
  - **Cancel**: Abort the registration

- **Same service name but different slug**: Warn the user that another service with the same `name` field already exists under a different slug. This can cause confusion in the UI. Ask the user to disambiguate by either renaming the new service or confirming the duplicate name is intentional.

**2c. Check for slug collisions in nullplatform** (both modes):

```bash
# Query existing service specifications to check for slug conflicts
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true" | jq '[.[] | {slug, name}]'
```

If a service specification with the same slug already exists in nullplatform, inform the user and ask them to disambiguate before proceeding.

### 3. Ask user: local or remote

**BEFORE generating terraform**, ask the user with AskUserQuestion:

> How do you want to register the service?
>
> **Local (recommended for testing)**: Reads specs directly from the filesystem. You don't need to push anything to GitHub, you can iterate quickly.
>
> **Remote (for production)**: Reads specs from a GitHub/GitLab repository. Requires the repo to exist and specs to be pushed.

This decision determines the module's `git_provider`:
- **Local** → `git_provider = "local"` + `local_specs_path` pointing to the service directory
- **Remote** → `git_provider = "github"` (default) + `repository_org`, `repository_name`, `repository_branch`. If the repo is private, also `repository_token`.

### 3b. If Remote: Repository visibility (default: Private)

When the user selects **Remote**, the repository **MUST be private by default**. Present the AskUserQuestion with **Private as the first option and marked as Recommended**:

> The repository will be created/used as **private** (recommended). Do you want to change this?
>
> **Private (Recommended)**: Service specs are only accessible with a token. You will need to provide a GitHub/GitLab access token with read permissions. The module passes this token to fetch spec files securely. This is the safe default.
>
> **Public**: Service specs are publicly accessible on the internet. **Warning**: anyone can read your service definitions, attribute schemas, and link configurations. Only use this for open-source services or non-sensitive specs.

**Default behavior**: If the user does not explicitly choose Public, always proceed with Private. Never create or assume a public repository.

Based on the answer:
- **Private (default)** → `repository_token` is **required**. Ask the user for a GitHub Personal Access Token (or GitLab PAT with `read_api` scope). Warn that without the token, tofu apply will fail with a 404 error. If the agent needs to create the repo on behalf of the user (e.g., via GitHub API), always set `"private": true`.
- **Public** → `repository_token` can be omitted (set to `null`). Explicitly confirm with the user: _"Your service specs will be publicly readable by anyone on the internet. Are you sure?"_. Require explicit confirmation before proceeding.

**Important**: If the user needs to push specs to a new repository, remind them to set the repository visibility to **private before pushing**. If the repo was accidentally created as public, immediately help them change it to private via the GitHub/GitLab API or UI before continuing.

For the binding (`service_definition_agent_association`):
- **Local** → `base_clone_path = pathexpand("~/.np")` (points to the local symlink)
- **Remote** → omit `base_clone_path` (uses the default `/root/.np` of the agent in k8s)

### 4. Generate terraform

Read the module variables from `/tmp/tofu-modules-ref/` and generate:

1. **nullplatform/main.tf**: module `service_definition_<slug>` with mandatory module variables + `git_provider = "local"` and `local_specs_path` if in local mode.
2. **nullplatform/outputs.tf**: outputs for `service_specification_slug` and `service_specification_id`.
3. **nullplatform-bindings/main.tf**: module `service_definition_agent_association` with mandatory variables. For local dev, set `base_clone_path = pathexpand("~/.np")`.

For the binding, the module builds the cmdline internally — read the module's `main.tf` to understand the pattern.

### 5. Apply

```bash
cd nullplatform && tofu init && tofu apply -var-file=common.tfvars
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../nullplatform/common.tfvars
```

Verify: `/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"`

For the pre-registration checklist, see `np-service-creator` skill.
