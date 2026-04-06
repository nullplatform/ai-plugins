# Terraform Patterns Reference

## Source of Truth

Always clone and read the modules before generating terraform:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Files to read:
- `nullplatform/service_definition/variables.tf` — module variables (those without default are mandatory)
- `nullplatform/service_definition/main.tf` — how resources are created
- `nullplatform/service_definition/locals.tf` — how specs are resolved (HTTP vs file depending on git_provider)
- `nullplatform/service_definition/data.tf` — HTTP data sources (disabled when git_provider = "local")
- `nullplatform/service_definition_agent_association/variables.tf` — binding variables
- `nullplatform/service_definition_agent_association/main.tf` — how the cmdline and channel are built

Do not copy examples from this file as a template — generate the terraform by reading the module variables and adapting to the specific service.

## Local vs Remote

- **Local** (`git_provider = "local"`): uses `file()` to read specs from the filesystem. Does not require push.
- **Remote** (`git_provider = "github"` or `"gitlab"`): uses `data "http"` to read specs from the repo. Requires push.

## Apply Order

```bash
cd nullplatform && tofu init && tofu apply -var-file=common.tfvars
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../nullplatform/common.tfvars
```
