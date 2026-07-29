# Agent assume-role model (AWS)

From `infrastructure/aws/iam/agent` **v6.0.0** the agent's base IAM role is **assume-only**: it
carries no workload policies, just an `sts:AssumeRole` statement over a list of permissions
role ARNs. Each scope and service contributes its own permissions role, created by a Terraform
module that lives in **that scope's or service's own repo**, and the ARNs are published to
nullplatform keyed by `selector` so the agent's runtime knows which role to assume for a given
workflow.

Repos, refs, requirements module paths and selectors are in the catalog, which
`np-infrastructure-wizard`'s `SKILL.md` already inlines when the skill triggers:
`${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`

## Why this replaces managed policies on the base role

Before v6.0.0 the agent role carried every workload policy it might ever need (Route53, ELB,
EKS, RDS, S3, …) for the union of all enabled scopes. Assume-role narrows each workflow to the
permissions of its own scope, with temporary credentials (1h TTL) instead of a standing grant.

## The module cycle, and who breaks it

`agent_iam` needs the permissions role ARNs for its assume policy, and each requirements module
needs the agent role ARN for its trust policy. That is a module cycle, which `tofu` rejects.

It is broken by deriving the agent role ARN **by naming convention** instead of by module
reference — the name is deterministic given the account ID and cluster name:

```hcl
data "aws_caller_identity" "current" {}

locals {
  cluster_name   = coalesce(var.cluster_name_override, "${var.organization_slug}-cluster")
  agent_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nullplatform-${local.cluster_name}-agent-role"
}
```

**The requirements modules already do this internally.** Their `agent_role_arn` variable defaults
to `""`, and when empty the module derives
`arn:aws:iam::<account>:role/nullplatform-${var.cluster_name}-agent-role` itself. So passing
`agent_role_arn = local.agent_role_arn` is redundant when the agent role uses the default name.

Pass it explicitly when either applies:

- **The agent role name is overridden** (`role_name` on `agent_iam`). Then the module's derivation
  is wrong, and the trust policy will point at a role that does not exist. The failure surfaces as
  `AccessDenied` on the first deploy — **not** as a `tofu` error.
- **You want the coupling visible in the code.** The applied AWS reference setup passes it on every
  requirements module for exactly this reason.

If you do override `role_name`, `local.agent_role_arn` must reflect the override or the whole
model silently breaks.

## `agent_iam` (v6.0.0)

```hcl
module "agent_iam" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/iam/agent?ref=v6.0.0"

  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  agent_namespace                     = var.agent_namespace
  cluster_name                        = local.cluster_name

  assume_role_arns = compact([
    module.scope_requirements_k8s.permissions_role_arn,
    one(module.scope_requirements_static_files[*].permissions_role_arn),
    one(module.scope_requirements_lambda[*].permissions_role_arn),
    one(module.service_requirements_s3[*].permissions_role_arn),
  ])
}
```

Note the first entry has no `one(...)`: Containers is always enabled, so its module has no `count` and
is referenced directly. Everything else is toggled.

| Input | Required | Notes |
|---|---|---|
| `aws_iam_openid_connect_provider_arn` | yes | EKS OIDC provider ARN, for the IRSA trust |
| `agent_namespace` | yes | Namespace the agent runs in |
| `cluster_name` | yes | Drives the role name and policy name prefix |
| `assume_role_arns` | no (`[]`) | Roles the agent may assume. Validated against `arn:aws:iam::<12-digit>:role/<name>` |
| `additional_policies` | no (`{}`) | Extra managed policy ARNs on the base role. Use sparingly — it reintroduces standing grants |
| `permissions_roles` | no (`{}`) | Lets this module create permissions roles from policy ARNs, as an alternative to per-repo requirements modules |
| `service_account_name` | no (`nullplatform-agent`) | K8s SA trusted by IRSA |
| `role_name` | no (derived) | Overriding this requires updating `local.agent_role_arn` — see above |
| `policies_name_prefix` | no (derived) | Defaults to `nullplatform_{cluster_name}` |

Output: `nullplatform_agent_role_arn`.

> `assume_role_arns` has a `validation` block. An empty string in the list fails the plan, which
> is why the example wraps the list in `compact()` — a disabled scope contributes `null`, and
> `compact()` drops it.

## Requirements modules

These do **not** live in `tofu-modules`. Each one lives in the repo of the scope or service it
belongs to, and the path is not derivable — see the catalog for the verified paths and the
`gh api` command to confirm one.

**Containers — always generated, no `count`.** Every setup has this scope, so its requirements module
is unconditional. Omitting it is the most common way to reproduce the exact bug this model exists to
prevent, on the most common scope:

```hcl
module "scope_requirements_k8s" {
  source = "git::https://github.com/nullplatform/scopes.git//k8s/specs/requirements/aws?ref=main"

  cluster_name   = local.cluster_name
  agent_role_arn = local.agent_role_arn
}
```

**Everything else — gated by its toggle:**

```hcl
module "scope_requirements_static_files" {
  source = "git::https://github.com/nullplatform/scopes-static-files.git//static-files/specs/requirements/aws?ref=1.0.0"
  count  = var.enable_static_files ? 1 : 0

  cluster_name   = local.cluster_name
  agent_role_arn = local.agent_role_arn
}
```

The `count` + `one()` pairing is what makes the toggle work: a disabled entry contributes `null`
to `assume_role_arns` and to its output, instead of breaking the reference.

| Input | Required | Notes |
|---|---|---|
| `cluster_name` | yes | Drives the permissions role name |
| `agent_role_arn` | no (`""`) | Trust principal. Derived by convention when empty — see the cycle section |
| `additional_agent_role_arns` | no (`[]`) | Extra principals appended to the trust policy. For a permissions role shared by more than one cluster's agent |
| `role_name` / `permissions_role_name` | no (derived) | **Name differs by repo — see below.** Override to preserve a historical role name across a module rename |
| `policies_name_prefix` | no (derived) | Policy name prefix |
| `iam_create_role` | no (`true`) | Set `false` to attach policies to a pre-existing role instead of creating one |
| `iam_resource_tags_json` | no (`{}`) | Tags on the created IAM resources |

Outputs: `permissions_role_arn`, `permissions_role_name`, `permissions_role_id`.

**The role-name override variable is not named consistently across repos.** Verified against the
upstream `variables.tf` of each:

| Repo | Variable |
|---|---|
| `scopes` (Containers / `k8s`) | `permissions_role_name` |
| `scopes-lambda`, `scopes-static-files`, `services-s-3` | `role_name` |

Passing `role_name` to the `k8s` requirements module is a hard `tofu` error ("Unsupported argument").
Read the module's `variables.tf` before generating an override — do not carry the name over from
another entry.

**`parameters-provider` uses a different contract.** Its requirements modules take an `iam_role`
object and output `iam_role_arn`, not `permissions_role_arn`. Do not assume one contract from the
other.

## Agent repositories

`nullplatform/scopes` needs no toggle here because it is the module default for `agent_repos_scope`
(`https://github.com/nullplatform/scopes.git#main`) — see the catalog note above for why that is not
the same as shipping inside the agent image. Every other repo has to be listed in
`agent_repos_extra`, built by concatenating conditional lists so the toggle governs it:

```hcl
locals {
  agent_repos_extra = concat(
    var.enable_static_files ? ["https://github.com/nullplatform/scopes-static-files.git#1.0.0"] : [],
    var.enable_aws_lambda ? [
      "https://github.com/nullplatform/scopes-lambda.git#1.0.1",
      "https://github.com/nullplatform/scopes-networking.git#main",
    ] : [],
    var.enable_aws_s3_bucket ? ["https://github.com/nullplatform/services-s-3.git#1.0.0"] : [],
  )
}

module "agent" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v5.3.1"

  # … api_key, cluster_name, nrn, tags_selectors, dns_type, aws_iam_role_arn …

  agent_repos_scope = "https://github.com/nullplatform/scopes.git#main"
  agent_repos_extra = local.agent_repos_extra

  depends_on = [module.base]
}
```

The module joins both into `--command-executor-git-command-repos`, and the agent clones each
`<url>#<ref>` into `/root/.np/<org>/<repo>`.

**A repo missing from this list fails silently** — same failure mode as the catalog note above
(`stat: no such file or directory`, scope still shows as active in nullplatform). Every `repo_path`
in the bindings layer must correspond 1:1 with an entry here.

AWS Lambda pulls **two** repos: `scopes-lambda` for the scope itself and `scopes-networking` for
the ALB / API Gateway / Route53 workflow overrides its channel composes in via `enabled_override`.

## Outputs contract

One output per requirements module, named `<catalog_slug>_assume_role_arn`:

```hcl
output "containers_assume_role_arn" {
  description = "ARN of the Containers permissions role; consumed by nullplatform-bindings to publish the AWS IAM provider config."
  value       = module.scope_requirements_k8s.permissions_role_arn
}

output "static_files_assume_role_arn" {
  description = "ARN of the static-files permissions role; consumed by nullplatform-bindings to publish the AWS IAM provider config."
  value       = one(module.scope_requirements_static_files[*].permissions_role_arn)
}
```

Plus `parameter_store_iam_role_arn` and `secrets_manager_iam_role_arn` for the two
`parameters-provider` entries, whose modules output `iam_role_arn`.

**These names are a contract with `nullplatform-bindings/`**, which reads them through
`terraform_remote_state` to build the `identity-access-control` provider config. Renaming one
breaks the bindings layer.

> **Existing setups may use other names.** The `<catalog_slug>_assume_role_arn` convention above is
> what to generate for a new setup. An applied AWS reference setup predates it and exports the two
> parameters-provider ARNs as `iam_role_arn` (unprefixed) and `secret_manager_iam_role_arn` (singular
> "secret"). When extending an existing layer, read its `outputs.tf` rather than assuming these names.

## Verify before generating

1. **The requirements module path** — not derivable, see the catalog's `gh api` command above.
2. **The IAM selector**, which varies by repo and ref — read the scope's workflow to see which key
   it looks up in the provider config. Do not copy a selector from another setup.
