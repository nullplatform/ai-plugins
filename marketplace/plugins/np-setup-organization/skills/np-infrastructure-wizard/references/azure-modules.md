# Azure Module Reference

> Companion to [azure.md](azure.md). Read this when writing or editing `infrastructure/azure/main.tf`.
> For the decision tree see [azure.md](azure.md); for failure modes see [azure-troubleshooting.md](azure-troubleshooting.md).

> **Provenance**: every input, output and `validation` block below was read from
> `nullplatform/tofu-modules` at `v7.1.0`. **If you pinned a different `ref`**, re-read the
> module's `variables.tf` and `outputs.tf` from `.terraform/modules/` before trusting these
> lists. The HCL blocks show the required inputs plus the defaults worth overriding — they
> are not exhaustive dumps of `variables.tf`, per the generation rules.

For source format and versioning see [tofu-modules-patterns.md](tofu-modules-patterns.md#module-source-git-ref). For `agent_api_key` see [tofu-modules-patterns.md](tofu-modules-patterns.md#agent-api-key-module).

All paths below are under `infrastructure/azure/` in `nullplatform/tofu-modules`, except the
`commons/` and `nullplatform/` ones.

## Contents

- [The `local.*` values](#the-local-values-these-blocks-reference)
- [Resource Group](#resource-group-infrastructureazureresource_group)
- [VNet](#vnet-infrastructureazurevnet)
- [AKS](#aks-infrastructureazureaks)
- [AKS Route Table](#aks-route-table-infrastructureazureaks_route_table)
- [ACR](#acr-infrastructureazureacr)
- [DNS (public)](#dns-public-infrastructureazuredns)
- [Private DNS](#private-dns-infrastructureazureprivate_dns)
- [Security](#security-infrastructureazuresecurity)
- [IAM](#iam-infrastructureazureiam)
- [Istio](#istio-infrastructurecommonsistio)
- [Cert Manager](#cert-manager-infrastructurecommonscert_manager)
- [External DNS](#external-dns-infrastructurecommonsexternal_dns)
- [Prometheus](#prometheus-infrastructurecommonsprometheus)
- [Base](#base-azure-defaults-nullplatformbase)
- [Agent](#agent-nullplatformagent)

## The `local.*` values these blocks reference

Every HCL block below references locals. Their values are **not free choices** — the federated
credential's subject is `system:serviceaccount:{namespace}:{service_account_name}` and has to
match what the chart actually creates, or Workload Identity fails **silently**: the pod runs, the
token is rejected, and DNS records simply never appear.

| local | Value | Where it comes from |
|---|---|---|
| `cert_manager_namespace` | `"cert-manager"` | `commons/cert_manager` → `var.cert_manager_namespace` default |
| `cert_manager_ksa_name` | `"cert-manager"` | jetstack chart, `serviceAccount.create = true` with no `name` → chart fullname |
| `external_dns_namespace` | `"external-dns"` | `commons/external_dns` → `var.external_dns_namespace` default |
| `external_dns_public_ksa` | `"external-dns-public"` | release is `external-dns-${var.type}`; the release name already contains the chart name, so fullname == release name |
| `external_dns_private_ksa` | `"external-dns-private"` | same rule, `type = "private"` |
| `public_gateway_name` | `"gateway-public"` | `nullplatform/base` → `var.gateway_public_name` default |
| `private_gateway_name` | `"gateway-private"` | **hardcoded** in `base`'s `templates/nullplatform_base_values.tmpl.yaml` — not a variable |
| `cloud_provider` | `"azure"` | literal |
| `aks_subnet_name` | `var.subnets_definition["aks"].name` | derived — see the `subnet_ids` note under VNet |

> **The two gateway names are load-bearing.** They are preconditions of the `agent` module on
> Azure, and `base.gateway_public_name`'s own description spells out the failure: *"Must match the
> gateway name the nullplatform agent resolves from `container-orchestration.gateway.public_name`
> (e.g. 'internet-facing' on AKS), otherwise HTTPRoutes are created with an unresolvable
> `parentRef`."* Pass both explicitly rather than relying on the defaults lining up.

## Resource Group (`infrastructure/azure/resource_group`)
- Required: `resource_group_name`, `location`, `subscription_id`
- Optional: `tags`
- Outputs: `resource_group_name`, `resource_group_location`

```hcl
module "resource_group" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/resource_group?ref={version}"

  location            = var.azure_location
  resource_group_name = var.resource_group_name
  subscription_id     = var.subscription_id
  tags                = var.tags
}
```

## VNet (`infrastructure/azure/vnet`)
- Required: `vnet_name`, `resource_group_name`, `location`, `address_space`, `subnets_definition`, `subscription_id`
- Optional: `tags`
- Outputs: `vnet_id`, `vnet_name`, `subnet_ids`

```hcl
module "vnet" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/vnet?ref={version}"

  address_space       = var.address_space
  location            = var.azure_location
  resource_group_name = module.resource_group.resource_group_name
  subnets_definition  = var.subnets_definition
  subscription_id     = var.subscription_id
  tags                = var.tags
  vnet_name           = local.vnet_name
}
```

`subnets_definition` is a `map(object({...}))`:

```hcl
subnets_definition = {
  aks = {
    name             = "aks-subnet"
    address_prefixes = ["10.10.1.0/24"]
  }
}
```

> **`OBSERVED` — the subnet range must not overlap `10.0.0.0/16`.** That is AKS's *default
> service CIDR*, and `infrastructure/azure/aks` does not expose `net_profile_service_cidr`,
> `net_profile_dns_service_ip` or `net_profile_pod_cidr` — nothing is passed through to the AVM
> module, whose own defaults are `null`, so AKS picks. There is no way to move the service CIDR
> from the caller; the VNet is what has to move. A `10.0.x.x` VNet fails partway through the
> apply with `ServiceCidrOverlapExistingSubnetsCidr` — see
> [Pattern 10](azure-troubleshooting.md#10-the-vnet-range-collides-with-the-aks-service-cidr).
>
> The object also accepts an **optional `route_table = { id = ... }`**. This is not decoration:
> the underlying AVM submodule always renders the field, so omitting it is an explicit
> *detach*, not an omission. On a kubenet AKS subnet that is the root of the perpetual
> route-table drift — see [Pattern 2](azure-troubleshooting.md#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet).
>
> **`OBSERVED` — `subnet_ids` is keyed by each subnet's `name`, not by the map key.** The
> module's output is
> `{ for k, s in var.subnets_definition : s.name => "...\/subnets\/${s.name}" }`, and its own
> description says *"Map of subnet names to their resource IDs"*. With the example above the key
> is `"aks-subnet"`, **not** `"aks"`. Indexing by the map key is a hard `Invalid index` at plan
> time.
>
> Derive it instead of hardcoding either spelling, so the code survives a rename:
>
> ```hcl
> locals {
>   aks_subnet_name = var.subnets_definition["aks"].name
> }
> # then: module.vnet.subnet_ids[local.aks_subnet_name]
> ```
>
> `aks` needs one subnet **id**, not the map.

## AKS (`infrastructure/azure/aks`)
- Required: `subscription_id`, `resource_group_name`, `location`, `cluster_name`, `vnet_subnet_id`
- **Required in practice** (the module has defaults, but they are stale — see the note under the block): `kubernetes_version`, `system_pool_vm_size`, `user_pool_vm_size`
- Optional (worth knowing): `attach_acr`, `acr_id`, `authorized_ip_ranges`, `private_cluster_enabled`, `user_pool_min_count`, `user_pool_max_count`, `system_pool_node_count`, `node_pool_zones`, `system_pool_zones`, `user_pool_zones`, `additional_network_contributor_subnet_ids`, `prefix`, `environment`, `tags`
- Outputs: `cluster_name`, `host`, `cluster_ca_certificate`, `client_certificate`, `client_key`, `admin_client_certificate`, `admin_client_key`, `admin_cluster_ca_certificate`, `oidc_issuer_url`, `node_resource_group`

```hcl
module "aks" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/aks?ref={version}"

  cluster_name        = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  location            = var.azure_location
  resource_group_name = module.resource_group.resource_group_name
  subscription_id     = var.subscription_id
  vnet_subnet_id      = module.vnet.subnet_ids[local.aks_subnet_name]

  acr_id               = module.acr.acr_id
  attach_acr           = true
  authorized_ip_ranges = var.authorized_ip_ranges
  system_pool_vm_size  = var.system_pool_vm_size
  user_pool_vm_size    = var.user_pool_vm_size
  tags                 = var.tags
}
```

> **`OBSERVED` — three of this module's defaults are stale and each one fails the apply.** They
> are listed as "optional" above because the module declares a default; in practice all three
> are **required on any new setup**, and none of them is caught by `tofu validate` or `plan`.
>
> | Variable | Module default | Why it fails |
> |---|---|---|
> | `kubernetes_version` | `"1.32.7"` | The whole 1.32 line is **LTS-only** now. Fails with `K8sVersionNotSupported`. Bumping the *patch* does not help — the *minor* has to move. |
> | `system_pool_vm_size` | `"Standard_D2s_v5"` | Not enabled in every subscription/region. Fails with `is not allowed in your subscription`. |
> | `user_pool_vm_size` | `"Standard_D2s_v5"` | Same. |
>
> The upstream AVM module defaults `kubernetes_version` to `null`, which means *"the latest
> available in the region"*; this module replaces a default that ages well with one that ages
> badly. Verify all three before the first apply — see
> [Pattern 9](azure-troubleshooting.md#9-stale-module-defaults--kubernetes-version-and-vm-size)
> for the commands and the exact error strings.

> **`attach_acr = true` is required on a greenfield apply** that creates the ACR in the same
> run — see [Pattern 1](azure-troubleshooting.md#1-acrpull-role--for_each-with-an-acr-created-in-the-same-run).
>
> `oidc_issuer_url` is what the IAM modules consume; `node_resource_group` is what
> `aks_route_table` consumes. Both must be exposed if those modules are used.
>
> `authorized_ip_ranges` is a plain **`set(string)`** of CIDRs here. GKE's same-named
> variable is a `list(object({ cidr_block, display_name }))` — do not copy the value across
> clouds.
>
> The four credential outputs are `sensitive`. `admin_*` are wrapped in `try(...)` and are
> `null` unless local admin accounts are enabled — do not wire providers to them.

## AKS Route Table (`infrastructure/azure/aks_route_table`)
- Required: `node_resource_group`, `subnet_id`
- Outputs: `route_table_id`

```hcl
module "aks_route_table" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/aks_route_table?ref={version}"

  node_resource_group = module.aks.node_resource_group
  subnet_id           = module.vnet.subnet_ids[local.aks_subnet_name]
}
```

> Only needed with **kubenet**. It discovers the route table AKS created in the managed
> (`MC_`) resource group and re-associates it with the node-pool subnet on every apply. See
> [Pattern 2](azure-troubleshooting.md#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet).

## ACR (`infrastructure/azure/acr`)
- Required: `location`, `resource_group_name`, `containerregistry_name`
- Optional: `sku`, `zone_redundancy_enabled`, `retention_policy_in_days`, `tags`
- Outputs: `acr_id`, `acr_login_server`, `acr_admin_username`, `acr_admin_password`

```hcl
module "acr" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/acr?ref={version}"

  containerregistry_name = var.containerregistry_name
  location               = var.azure_location
  resource_group_name    = module.resource_group.resource_group_name
  tags                   = var.tags
}
```

> `containerregistry_name` is **globally unique across Azure** and alphanumeric only.
> `acr_login_server` is the image prefix the build pipeline pushes to; it and the admin
> credentials are consumed by the bindings layer — expose them as outputs.
> `acr_id` feeds `aks.acr_id` for the AcrPull role assignment.

## DNS (public) (`infrastructure/azure/dns`)
- Required: `resource_group_name`, `domain_name`
- Optional: `tags`
- Outputs: `dns_zone_name`, `dns_zone_id`, `private_dns_zone_name`, `private_dns_zone_id`, `name_servers`

```hcl
module "dns" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/dns?ref={version}"

  domain_name         = var.domain_name
  resource_group_name = module.resource_group.resource_group_name
  tags                = var.tags
}
```

> **This module creates one resource: a public `azurerm_dns_zone`.** Its
> `private_dns_zone_name` / `private_dns_zone_id` outputs are **aliases of the public zone**,
> not a private zone — wiring anything to them silently points it at the public zone. Use the
> `private_dns` module instead. See
> [Pattern 4](azure-troubleshooting.md#4-the-dns-module-only-creates-a-public-zone).
>
> `name_servers` is what the DNS delegation in step 5 of `SKILL.md` needs. Expose it.

## Private DNS (`infrastructure/azure/private_dns`)
- Required: `resource_group_name`, `domain_name`, `virtual_network_links`
- Optional: `tags`
- Outputs: `private_dns_zone_name`, `private_dns_zone_id`, `virtual_network_link_ids`

```hcl
module "private_dns" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/private_dns?ref={version}"

  domain_name         = var.private_domain_name
  resource_group_name = module.resource_group.resource_group_name
  tags                = var.tags

  virtual_network_links = [
    { vnet_id = module.vnet.vnet_id }
  ]
}
```

> `virtual_network_links` is **required** — a private zone with no VNet link resolves for
> nobody. This is the real private zone; `module.dns`'s private outputs are not.
>
> It is a **list of objects**, and the key is `vnet_id` (not `virtual_network_id`):
> `list(object({ vnet_id = string, registration_enabled = optional(bool, false) }))`.
> `registration_enabled` defaults to `false`, which is what AKS and Private Link want; set it
> to `true` only for VM auto-registration.

## Security (`infrastructure/azure/security`)
- Required: `cluster_name`, `resource_group_name`
- Optional: `gateways_enabled`, `gateway_internal_enabled`, `azure_location`, `network_cidr`
- Outputs: `public_gateway_nsg_id`, `private_gateway_nsg_id`

```hcl
module "security" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/security?ref={version}"

  cluster_name        = module.aks.cluster_name
  resource_group_name = module.resource_group.resource_group_name
}
```

> Optional on Azure: the matching `base` variables (`gateway_public_azure_nsg_id`,
> `gateway_private_azure_nsg_id`) default to `""` and the gateways work without them. Include
> it only when the user wants the gateway health-check port restricted.
> Keep `gateway_internal_enabled` in sync with the same flag on `base`.

## IAM (`infrastructure/azure/iam`)
- Required: `resource_group_name`, `location`, `name`, `oidc_issuer_url`, `namespace`, `service_account_name`, `role_definition_name`, `scope`
- Optional: `tags`
- Outputs: `client_id`, `principal_id`, `id`

One invocation creates **one** user-assigned managed identity, **one** federated identity
credential (subject `system:serviceaccount:{namespace}:{service_account_name}`), and **one**
role assignment. cert-manager and external-dns therefore need one each:

```hcl
module "iam_cert_manager" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/iam?ref={version}"

  location             = var.azure_location
  name                 = local.cert_manager_identity_name
  namespace            = local.cert_manager_namespace
  oidc_issuer_url      = module.aks.oidc_issuer_url
  resource_group_name  = module.resource_group.resource_group_name
  role_definition_name = "DNS Zone Contributor"
  scope                = module.dns.dns_zone_id
  service_account_name = local.cert_manager_ksa_name
}

module "iam_external_dns" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/iam?ref={version}"

  location             = var.azure_location
  name                 = local.external_dns_identity_name
  namespace            = local.external_dns_namespace
  oidc_issuer_url      = module.aks.oidc_issuer_url
  resource_group_name  = module.resource_group.resource_group_name
  role_definition_name = "DNS Zone Contributor"
  scope                = module.dns.dns_zone_id
  service_account_name = local.external_dns_public_ksa
}

# DERIVED, not confirmed on a live apply. The private external-dns instance runs under a
# different KSA and needs a different role on a different resource type, and one invocation
# of this module produces exactly one federated credential and one role assignment — so a
# third invocation is the only way to express it with the module as it stands.
module "iam_external_dns_private" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/azure/iam?ref={version}"

  location             = var.azure_location
  name                 = local.external_dns_private_identity_name
  namespace            = local.external_dns_namespace
  oidc_issuer_url      = module.aks.oidc_issuer_url
  resource_group_name  = module.resource_group.resource_group_name
  role_definition_name = "Private DNS Zone Contributor"
  scope                = module.private_dns.private_dns_zone_id
  service_account_name = local.external_dns_private_ksa
}
```

> `scope` is the resource the role is granted on — the DNS zone id, not the resource group,
> unless the identity must reach several zones.
>
> **Public and private DNS are different resource types on Azure**, so they need different
> roles (`DNS Zone Contributor` vs `Private DNS Zone Contributor`) on different resources.
> Combined with one-role-assignment-per-invocation, that is why the private external-dns
> instance gets its own IAM block rather than reusing the public one. Confirm this against
> the real setup before relying on it — see
> [Pattern 3](azure-troubleshooting.md#3-workload-identity-needs-one-iam-invocation-per-consumer).
>
> `id` (the managed identity's resource id) is what `cert_manager.azure_federated_credential_id`
> and `external_dns.azure_federated_credential_id` expect. `client_id` is what
> `azure_client_id` expects. They are different outputs — passing one where the other belongs
> trips a `validation` block or produces an identity that never binds. See
> [Pattern 3](azure-troubleshooting.md#3-workload-identity-needs-one-iam-invocation-per-consumer).

## Istio (`infrastructure/commons/istio`)

```hcl
module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/istio?ref={version}"

  cloud_provider = local.cloud_provider   # "azure"

  depends_on = [module.aks]
}
```

> `cloud_provider` is validated against `["", "aws", "oci", "azure", "gcp"]`.

## Cert Manager (`infrastructure/commons/cert_manager`)
- Required: `cloud_provider`, `private_domain_name`, `hosted_zone_name`, `account_slug`
- **Also required when `cloud_provider = "azure"`** (all enforced by `precondition`s):
  `azure_client_id`, `azure_subscription_id`, `azure_resource_group_name`, `azure_tenant_id`,
  `azure_hosted_zone_name`, plus **either** `azure_federated_credential_id` (Workload Identity)
  **or** `azure_client_secret`

```hcl
module "cert_manager" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/cert_manager?ref={version}"

  account_slug   = var.organization_slug
  cloud_provider = local.cloud_provider   # "azure"

  hosted_zone_name    = var.domain_name
  private_domain_name = var.private_domain_name

  azure_workload_identity_enabled = true
  azure_client_id                 = module.iam_cert_manager.client_id
  azure_federated_credential_id   = module.iam_cert_manager.id
  azure_hosted_zone_name          = var.domain_name
  azure_resource_group_name       = module.resource_group.resource_group_name
  azure_subscription_id           = var.subscription_id
  azure_tenant_id                 = var.azure_tenant_id

  # cert_manager_config, the module's second helm_release, deploys into the `gateways`
  # namespace that `base` creates -- so this module has to land AFTER base. See Pattern 13.
  depends_on = [module.aks, module.istio, module.iam_cert_manager]
}
```

> `cloud_provider` is validated against `["gcp", "azure", "cloudflare", "aws", "oci"]`.
> `account_slug` is the **module's input name**; the value comes from `var.organization_slug`.
>
> **`azure_hosted_zone_name` is separate from `hosted_zone_name` and both are required.** The
> module puts `hosted_zone_name` at the root of the Helm values and `azure_hosted_zone_name`
> inside the azure block; both carry the **public** zone name. Omitting the azure-specific one is
> a `Resource precondition failed` at plan time.
>
> **`OBSERVED` — there are seven preconditions on Azure, not two.** Two of them govern the auth
> path and are mutually exclusive:
> - `azure_workload_identity_enabled = true` → `azure_federated_credential_id` is **required**
>   (error message explicitly says to pass `module.iam.id`)
> - `azure_workload_identity_enabled = false` → `azure_client_secret` is **required**
>
> Prefer Workload Identity; the secret path means a long-lived credential in state.

## External DNS (`infrastructure/commons/external_dns`)
- Required: `domain_filters`, `dns_provider_name`

> **`OBSERVED` — two instances are NOT implementable on Azure at `v7.1.0`.** Two independent
> blockers, neither with a workaround from the caller:
>
> 1. **`secret.tf` hardcodes `name = "external-dns-azure-config"`.** It does not vary by
>    `var.type` and there is no variable to override it, so the second instance fails with
>    `secrets "external-dns-azure-config" already exists`. It cannot simply be shared either:
>    the two instances need *different* `azure_client_id`s, and the public identity has no
>    `Private DNS Zone Contributor`. Expressing it would need one managed identity with two
>    federated credentials, which `infrastructure/azure/iam` cannot produce (one identity + one
>    credential + one role assignment per invocation — see
>    [Pattern 3](azure-troubleshooting.md#3-workload-identity-needs-one-iam-invocation-per-consumer)).
> 2. **`azure_config` has no `extraArgs`, so `--label-filter` is never emitted.** Only
>    `route53_config` builds it. `label_filter` and `zone_type` are computed into
>    `local.effective_label_filter` and then silently dropped on the Azure path. With split
>    horizon that label is the only thing separating the two instances, so the public one reads
>    the private DNSEndpoints and publishes public records pointing at internal IPs.
>
> **Until the module changes, generate the public instance only** and say so explicitly. A
> one-line module fix unblocks blocker 1 (`external-dns-azure-config-${var.type}`); blocker 2
> needs `extraArgs` added to `azure_config`. See
> [Pattern 14](azure-troubleshooting.md#14-external-dns-split-horizon-is-not-supported-on-azure).

Azure uses the **shared** module (unlike GCP). The public instance:

```hcl
module "external_dns_public" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"

  dns_provider_name = "azure"
  domain_filters    = var.domain_name
  type              = "public"
  txt_owner_id      = var.external_dns_txt_owner_id

  azure_workload_identity_enabled = true
  azure_client_id                 = module.iam_external_dns.client_id
  azure_federated_credential_id   = module.iam_external_dns.id
  azure_resource_group            = module.resource_group.resource_group_name
  azure_subscription_id           = var.subscription_id
  azure_tenant_id                 = var.azure_tenant_id

  depends_on = [module.aks, module.iam_external_dns]
}

```

### The private instance — DO NOT GENERATE YET

Kept here as the target shape for when the module is fixed. **Generating it today breaks the
apply** for the two reasons above. If the user asks for split horizon, say that it is not
supported on Azure yet and generate the public instance only.

```hcl
# BLOCKED at v7.1.0 -- see the note above and Pattern 10.
module "external_dns_private" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"

  create_namespace  = false
  dns_provider_name = "azure-private-dns"
  domain_filters    = var.private_domain_name
  type              = "private"
  txt_owner_id      = "${var.external_dns_txt_owner_id}-private"

  azure_workload_identity_enabled = true
  azure_client_id                 = module.iam_external_dns_private.client_id
  azure_federated_credential_id   = module.iam_external_dns_private.id
  azure_resource_group            = module.resource_group.resource_group_name
  azure_subscription_id           = var.subscription_id
  azure_tenant_id                 = var.azure_tenant_id

  depends_on = [module.aks, module.external_dns_public]
}
```

> `dns_provider_name` is validated against
> `["cloudflare", "aws", "oci", "azure", "azure-private-dns"]`. The two Azure values share
> the same auth, secret mount and ServiceAccount wiring — only the external-dns
> `provider.name` differs. That shared secret is exactly what blocks the two-instance pattern
> above; it is not a feature.
>
> **`txt_owner_id` must be set, and unique per cluster.** It is the owner tag external-dns
> writes into its TXT registry records to know which entries are its own. The module default is
> the generic literal **`"external_dns"`**, and `policy` defaults to `"sync"` — so two setups
> (or two instances) sharing a zone with that default each treat the other's records as stale
> and delete them. Derive it from the setup slug (`txt_owner_id = "acme-prod"`), never leave the
> default. Same rule as
> [GCP](gcp-modules.md#external-dns-infrastructurecommonsexternal_dns).
> `type` controls the Helm release name (`external-dns-{type}`).
> The private instance needs `create_namespace = false` and a `depends_on` on the public one,
> or both race to create the shared namespace.
> Note the variable names differ between the two modules: cert_manager takes
> `azure_resource_group_name`, external_dns takes `azure_resource_group`.

## Prometheus (`infrastructure/commons/prometheus`)

```hcl
module "prometheus" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/prometheus?ref={version}"

  depends_on = [module.aks]
}
```

## Base (Azure defaults) (`nullplatform/base`)
- Required: `np_api_key`, `k8s_provider`

```hcl
module "base" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref={version}"

  np_api_key   = module.agent_api_key.api_key
  k8s_provider = "aks"

  metrics_server_enabled = false

  # Azure's only supported schema is Istio + Gateway API, and BOTH of these default to
  # false. commons/istio does NOT install the Gateway API CRDs, so base has to.
  gateway_api_enabled      = true
  gateway_api_crds_install = true

  gateway_enabled          = true
  gateway_public_enabled   = true
  gateway_internal_enabled = true
  gateways_enabled         = true
  gateway_public_name      = local.public_gateway_name

  gateway_public_azure_nsg_id  = module.base_security.public_gateway_nsg_id
  gateway_private_azure_nsg_id = module.base_security.private_gateway_nsg_id

  prometheus_enabled = true

  depends_on = [module.aks, module.istio, module.base_security]
}
```

> **Pass the gateway flags explicitly — Azure was the only cloud whose block omitted them.**
> AWS sets three of them literally and GCP wires them from one object so they cannot drift.
> Leaving them to the defaults is not neutral: `base.gateway_internal_enabled` defaults to
> `true` while `security.gateway_internal_enabled` defaults to `false`, so `base` creates an
> internal gateway whose NSG was never created. Keep the two in sync — the same drift has a
> symptom row on GCP
> ([gcp-troubleshooting.md](gcp-troubleshooting.md#4-order-is-gke--security--base)).
>
> **`gateway_api_enabled` and `gateway_api_crds_install` both default to `false`.** On AKS
> nothing else installs the Gateway API CRDs (`commons/istio` has no reference to them), so
> without these two the HTTPRoutes the agent creates have no CRD to bind to.

> `k8s_provider` is validated against `["eks", "gke", "aks", "oke", "aro"]` — use `"aks"`.
>
> **`base` takes no `nrn`.** The variable does not exist on the module at `v7.1.0` (nor on
> `main`); the chart derives its scope from the API key. Passing it is a hard
> `Unsupported argument` at plan time.
>
> Azure-specific optionals, all defaulting to `""`: `gateway_public_azure_nsg_id`,
> `gateway_private_azure_nsg_id` (from `module.security`) and
> `gateway_public_azure_load_balancer_subnet`. Pass them only when needed — the gateways work
> without them.
>
> The AWS gateway-naming rule (`gateway_public_aws_name` / `gateway_internal_aws_name`, see
> [resources-by-cloud.md](resources-by-cloud.md#base-module--gateway-nlb-naming--mandatory))
> is AWS-only. Passing those on an AKS setup is a no-op that reads like configuration.

## Agent (`nullplatform/agent`)
- Required: `api_key`, `cluster_name`, `nrn`, `tags_selectors`, `image_tag`, `cloud_provider`
- **Also required when `cloud_provider = "azure"` — eight `precondition`s, none of them
  conditional on `dns_type`**: `azure_client_id`, `azure_client_secret`,
  `azure_subscription_id`, `azure_resource_group`, `azure_tenant_id`, `private_hosted_zone_rg`,
  `private_gateway_name`, `public_gateway_name`

```hcl
module "agent" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref={version}"

  agent_repos_scope = var.agent_repos_scope
  api_key           = module.agent_api_key.api_key
  cloud_provider    = local.cloud_provider   # "azure"
  cluster_name      = module.aks.cluster_name
  image_tag         = var.agent_image_tag
  nrn               = var.nrn
  tags_selectors    = var.tags_selectors

  dns_type       = var.dns_type
  domain         = var.domain_name
  private_domain = var.private_domain_name

  # The eight Azure preconditions. Azure is the ONLY cloud whose cloud_config map reads
  # PUBLIC_GATEWAY_NAME -- aws, gcp and oci pass the private one only.
  azure_client_id        = var.agent_azure_client_id
  azure_client_secret    = var.agent_azure_client_secret
  azure_resource_group   = module.resource_group.resource_group_name
  azure_subscription_id  = var.subscription_id
  azure_tenant_id        = var.azure_tenant_id
  private_hosted_zone_rg = module.resource_group.resource_group_name
  private_gateway_name   = local.private_gateway_name
  public_gateway_name    = local.public_gateway_name

  # Without these three the agent falls back to plain Ingress templates.
  blue_green_ingress_path = var.agent_blue_green_ingress_path
  initial_ingress_path    = var.agent_initial_ingress_path
  service_template        = var.agent_service_template

  depends_on = [module.base]
}
```

> `cloud_provider` is validated against `["aws", "gcp", "azure", "oci"]`.
> Unlike `base`, the agent **does** take `nrn`, and it is required (no default).
>
> **`OBSERVED` — the eight Azure variables above are NOT optional.**
> `terraform_data.cross_variable_validation` in the module carries one `precondition` per
> variable, all of the shape `var.cloud_provider != "azure" || var.<x> != null`. **`dns_type`
> does not appear in any of them**, so "with external-dns owning the records the agent does not
> need credentials" is false as far as the plan is concerned — the service principal has to
> exist even when nothing uses it. See
> [Pattern 12](azure-troubleshooting.md#12-the-agent-needs-a-service-principal-on-azure) for how
> to create it.
>
> **The error you actually see first is worse than the preconditions.** The module's
> `templatefile` interpolates `"${value}"` over every entry of `config_values`, so a `null`
> blows up before any precondition is evaluated:
>
> ```
> Invalid template interpolation value; The expression result is null.
> Cannot include a null value in a string template.
>   nullplatform_agent_values.tmpl.yaml:22,16-21
> ```
>
> That message names neither the variable nor the module input. If you see it on Azure, one of
> the eight is missing.
> The three HTTPRoute template variables are mandatory under Istio — see
> [resources-by-cloud.md](resources-by-cloud.md#agent-httproute-templates-istio-schema--mandatory).
> Extra scope/service repos go in `agent_repos_extra`; see the catalog referenced from `SKILL.md`.
