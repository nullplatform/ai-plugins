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

### 2. Check not already registered

```bash
grep -c "service_definition_<slug>" nullplatform/main.tf
```

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
