# General OpenTofu Patterns

> Applies to all clouds. Per-cloud files (`aws.md`, `azure.md`, etc.) reference this document for shared patterns.

## Contents

1. [How to read module variables](#how-to-read-module-variables)
2. [Module reading flow](#module-reading-flow)
3. [Module source (git ref)](#module-source-git-ref)
4. [Generic provider versions](#generic-provider-versions)
5. [Helm v3 syntax](#helm-v3-syntax)
6. [Agent API Key module](#agent-api-key-module)

## How to read module variables

When reading any module's `variables.tf`:

1. **Variables without `default`**: always include them, they are required
2. **Variables with `default` that have a `validation` block**: read the `error_message` to understand in which context they are required. If the context applies, include them
3. **Variables with `default` without `validation`**: include only if the default needs to be changed

**IMPORTANT**: Do not skip step 2. Variables with conditional `validation` are the most common cause of errors in `tofu plan`. Always review all `validation` blocks before generating code.

## Module reading flow

Before using any module:
1. Read the module's `variables.tf` (prefer `.terraform/modules/{name}/variables.tf` after `tofu init`)
2. Include all variables without default
3. Review `validation` blocks of variables with defaults and add those that apply to the context
4. Variables with default without validation: add only if the default needs to be changed

> Tip: Use `tofu init -backend=false` to download modules without needing backend credentials, then inspect `.terraform/modules/`.

## Module source (git ref)

All nullplatform modules are referenced with git ref:

```hcl
source = "git::https://github.com/nullplatform/tofu-modules.git//{path}?ref={version}"
```

Get the latest version:
```bash
git ls-remote --tags https://github.com/nullplatform/tofu-modules.git | sort -t/ -k3 -V | tail -1
```

## Generic provider versions

Providers shared across all clouds:

```hcl
kubernetes = { source = "hashicorp/kubernetes",  version = "~> 2.0" }
helm       = { source = "hashicorp/helm",        version = "~> 3.0" }
nullplatform = { source = "nullplatform/nullplatform", version = "~> 0.0.74" }
```

Each cloud adds its specific provider (e.g., `aws ~> 6.0`, `azurerm ~> 4.0`).

## Helm v3 syntax

Helm provider v3 changes the `kubernetes` block syntax:

```hcl
# Correct (Helm v3): with "="
provider "helm" {
  kubernetes = {
    host = "..."
  }
}

# Incorrect (Helm v2): without "="
provider "helm" {
  kubernetes {
    host = "..."
  }
}
```

## Agent API Key module

The `agent_api_key` module generates an API key at runtime for the `agent` module. Used across all clouds:

```hcl
module "agent_api_key" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref={version}"
  type   = "agent"
  nrn    = var.nrn
}
```

Then use `module.agent_api_key.api_key` only in the `agent` module (instead of `var.np_api_key` directly). The `base` module still uses `var.np_api_key`.
