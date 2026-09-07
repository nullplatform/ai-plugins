# Decision Tree - Azure Infrastructure

> Invoked from step 4 of the main wizard (`SKILL.md`).
> **Global input**: `infrastructure/azure/` with original .tf files
> **Global output**: Customized .tf files, `existing-resources.properties` (if applicable), new variables in `terraform.tfvars`

> For general OpenTofu patterns (module source, Helm v3, agent_api_key) see [tofu-modules-patterns.md](tofu-modules-patterns.md).

> **This file is the entrypoint.** Azure reference material is split in three:
>
> | File | What lives there | Read it when |
> |---|---|---|
> | `azure.md` (this one) | Decision tree (steps 1–6), variables, provider blocks | Always |
> | [azure-modules.md](azure-modules.md) | Module contracts and HCL blocks | Writing or editing `main.tf` |
> | [azure-troubleshooting.md](azure-troubleshooting.md) | Critical patterns + symptom table | Before a greenfield apply, or when something fails |

> **Provenance — read this before trusting the contracts.** Every module input, output and
> `validation` block referenced here was read from `nullplatform/tofu-modules` at `v7.1.0`.
> The **failure modes marked `OBSERVED`** in `azure-troubleshooting.md` come from real
> applies; the ones marked `DERIVED` were reasoned from module source and have **not** been
> confirmed on a live apply. Treat `DERIVED` as a strong hint, not as settled fact, and
> re-read the module from `.terraform/modules/` if you pinned a different `ref`.
>
> Azure has less field coverage than AWS, which is the reference implementation used in
> production. When Azure and AWS disagree, assume AWS is right and Azure's doc is stale.

## Contents

0. [Azure prerequisites](#step-0-azure-prerequisites)
1. [Module Classification](#step-1-module-classification)
2. [Ask about Cloud components](#step-2-ask-about-each-cloud-component)
3. [Resolve excluded dependencies](#step-3-resolve-excluded-module-dependencies)
4. [Ask about Commons components](#step-4-ask-about-commons-components)
5. [Apply changes to .tf](#step-5-apply-changes-to-tf-files)
6. [Validate .tf files](#step-6-validate-tf-files)
7. [Azure Variables](#azure-variables)
8. [Provider Configuration](#provider-configuration)
9. [Azure Module Reference](azure-modules.md)
10. [Critical Azure Patterns](azure-troubleshooting.md#critical-azure-patterns)
11. [Troubleshooting](azure-troubleshooting.md#troubleshooting)

> **No schema decision on Azure.** Unlike AWS (which has an Istio schema and an ACM/Ingress
> schema — see [aws.md](aws.md) step 0), Azure has a single supported schema: **Istio +
> Gateway API + cert-manager + external-dns**. There is no Azure-native certificate path
> equivalent to ACM in the modules. Do not ask the user to pick a schema.

## Step 0: Azure prerequisites

Four things have to be true **before** the first apply. None of them is caught by
`tofu validate` or `tofu plan`, and each one fails the apply on its own.

**1. Confirm the active subscription matches `terraform.tfvars`.**

```bash
az account show --query '{sub:name, id:id, tenant:tenantId}' -o json
```

The `azurerm` backend and provider both use the ambient Azure CLI login — there is no `profile`
equivalent to the S3 backend's.

**2. A service principal for the agent.** Required on Azure whatever `dns_type` is, because the
`agent` module's preconditions demand it — [Pattern 12](azure-troubleshooting.md#12-the-agent-needs-a-service-principal-on-azure).

```bash
az ad sp create-for-rbac --name np-agent-<setup> --role Reader \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>
```

Feed `appId` → `agent_azure_client_id` and `password` → `agent_azure_client_secret`.

**3. A Kubernetes version and VM sizes the subscription actually accepts.** Both module defaults
are stale — [Pattern 9](azure-troubleshooting.md#9-stale-module-defaults--kubernetes-version-and-vm-size).

```bash
# support plan is NOT in `-o table`
az aks get-versions --location <loc> -o json \
  | jq -r '.values[] | "\(.version) \(.capabilities.supportPlan | join(","))"'

az vm list-skus --location <loc> --resource-type virtualMachines \
  --query "[?name=='<sku>'].restrictions"

az vm list-usage --location <loc> \
  --query "[?contains(localName,'Total Regional vCPUs')]" -o table
```

**4. Check the resource providers are registered.** A virgin subscription starts with the ones
AKS needs `NotRegistered`. Whether `azurerm` registers them itself is an
[open question](azure-troubleshooting.md#known-gaps) — check rather than assume:

```bash
for p in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Network \
         Microsoft.Storage Microsoft.ManagedIdentity Microsoft.OperationalInsights \
         Microsoft.Compute; do
  printf '%-38s %s\n' "$p" "$(az provider show -n $p --query registrationState -o tsv)"
done
# register any that come back NotRegistered:
#   az provider register -n <namespace>
```

## Step 1: Module Classification

> **Input**: `infrastructure/azure/main.tf`
> **Output**: Modules classified by category

Read `main.tf` dynamically and classify:

### Cloud (askable)

| Module | Question |
|--------|----------|
| `resource_group` | Do you already have a Resource Group? |
| `vnet` | Do you already have a VNet? |
| `aks` | Do you already have an AKS cluster? |
| `acr` | Do you already have an Azure Container Registry? |
| `dns` | Do you already have a public DNS Zone? |
| `private_dns` | Do you already have a private DNS Zone? |
| `security` | Do you already have NSGs for the gateways? |

> The `security` block is often named `base_security` in existing `main.tf` files (the module
> path is `infrastructure/azure/security` either way). Match whatever the file uses; do not
> rename it as part of a customization pass.

**IAM modules** (askable, depend on the AKS OIDC issuer):

| Module | Question |
|--------|----------|
| `iam_cert_manager` + `iam_external_dns*` | Do you already have managed identities and federated credentials for cert-manager and external-dns? |

> Treat these as a **single** question but expect **two or three** module blocks. Each
> invocation of `infrastructure/azure/iam` creates one user-assigned managed identity, one
> federated identity credential bound to a specific `namespace` + `service_account_name`, and
> one role assignment — so consumers cannot share one. cert-manager needs one; external-dns
> needs one per instance if the private zone is in play, because public and private DNS are
> different Azure resource types with different roles. See
> [Pattern 3](azure-troubleshooting.md#3-workload-identity-needs-one-iam-invocation-per-consumer).

### Nullplatform (always included, don't ask)

- `agent_api_key`, `base`, `agent`

Always remove: `scope_notification_api_key`, `service_notification_api_key`

#### The `base` block on Azure

```hcl
module "base" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref={version}"
  np_api_key   = module.agent_api_key.api_key
  k8s_provider = "aks"   # "aro" on Azure ARO — see azure-aro.md

  metrics_server_enabled = false

  gateway_public_azure_nsg_id  = module.base_security.public_gateway_nsg_id
  gateway_private_azure_nsg_id = module.base_security.private_gateway_nsg_id

  depends_on = [module.aks, module.istio]
}
```

> **`metrics_server_enabled = false` is mandatory on Azure and is written as a literal.**
> AKS and ARO both ship metrics-server as a managed component, so `true` tries to install a
> second one and the `base` release fails at apply on the same `APIService v1beta1.metrics.k8s.io`
> ownership conflict documented for GKE in
> [gcp-modules.md](gcp-modules.md#metrics_server_enabled-must-be-false-on-gke). AWS takes the
> opposite value for the opposite reason (EKS ships no Metrics API) — see
> [generation rule 35](infrastructure-generation.md#35-metrics_server_enabled-depends-on-cloud-provider).
> Never route it through a tfvars variable and never ask the user.
>
> **`base` takes no `nrn`.** Same as on AWS: the module does not declare it and passing it is a
> hard `Unsupported argument` at plan time. `nrn` is still required by `agent` and `agent_api_key`.
>
> The NSG ids come from `module.base_security` (the `infrastructure/azure/security` module,
> outputs `public_gateway_nsg_id` / `private_gateway_nsg_id`). Only pass them when
> `base_security` is included; if the user already has NSGs, resolve them per
> [Step 3](#step-3-resolve-excluded-module-dependencies).

### Commons (askable)

| Module | Question |
|--------|----------|
| `cert_manager` | Do you already have cert-manager installed? |
| `istio` | Do you already have Istio installed? |
| `external_dns_public` | Do you already have external-dns configured? (public instance only — see the note below) |
| `prometheus` | Do you already have Prometheus installed? |

> Azure uses the **shared** `infrastructure/commons/external_dns` module (unlike GCP), with
> `dns_provider_name = "azure"` for the public zone and `"azure-private-dns"` for the private
> one. Both values are in the module's `validation` block.
>
> **Generate the public instance only.** Two instances are not implementable on Azure at
> `v7.1.0` — the module gives both a single fixed-name secret they cannot share, and it never
> emits `--label-filter` on the Azure path. If the user asks for split horizon, say so rather
> than generating a layer that fails the apply:
> [Pattern 14](azure-troubleshooting.md#14-external-dns-split-horizon-is-not-supported-on-azure).

## Step 2: Ask about each Cloud component

> **Input**: List of Cloud modules
> **Output**: List of modules to keep vs exclude

For each Cloud module, ask: **"Do you already have a {resource} or do you need it created?"**

- **Create new** → Keep the module block
- **I already have one** → Add to excluded list, resolve dependencies in step 3

### Question order (respect dependencies)

1. `resource_group` (many depend on this)
2. `vnet` (depends on resource_group)
3. `aks` (depends on resource_group, vnet — takes `vnet_subnet_id`, a single subnet id)
4. `acr` (depends on resource_group)
5. `dns` (depends on resource_group)
6. `private_dns` (depends on resource_group **and** vnet — it needs `virtual_network_links`)
7. `security` (depends on resource_group and `aks.cluster_name`)
8. `iam_cert_manager` + `iam_external_dns` (depend on `aks.oidc_issuer_url`)

> If the user creates `resource_group`, don't ask about its dependencies in other modules.

## Step 3: Resolve excluded module dependencies

> **Input**: List of excluded modules, `main.tf`
> **Output**: Replacement values for each referenced output

When the user says "I already have" a resource:

1. Find all `module.{excluded_module}.{output}` references in maintained modules
2. Ask the user for the real value of each found reference
3. Save the values (used in step 5)

### Dynamic detection

```bash
grep -oP 'module\.{excluded_module}\.\w+' infrastructure/azure/main.tf | sort -u
```

### Data sources for existing resources

When a resource already exists, prefer data sources over redundant variables.

**Existing Resource Group**:
```hcl
variable "resource_group_name" { type = string }

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}
```

**Existing VNet + subnet**:
```hcl
variable "vnet_name"   { type = string }
variable "subnet_name" { type = string }

data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "aks" {
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}
```

> `aks` takes `vnet_subnet_id` — a **single subnet id**, not a list. Feed it
> `data.azurerm_subnet.aks.id`.

**Existing AKS cluster**:
```hcl
variable "cluster_name" { type = string }

data "azurerm_kubernetes_cluster" "existing" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}
```

> Outputs to map: `kube_config[0].host` (replaces `module.aks.host`),
> `kube_config[0].cluster_ca_certificate`, `kube_config[0].client_certificate`,
> `kube_config[0].client_key`, plus `oidc_issuer_url` and `node_resource_group`, which the
> IAM modules and `aks_route_table` need respectively.

**Existing DNS zones**:
```hcl
variable "public_zone_name"  { type = string }
variable "private_zone_name" { type = string }

data "azurerm_dns_zone" "public" {
  name                = var.public_zone_name
  resource_group_name = var.resource_group_name
}

data "azurerm_private_dns_zone" "private" {
  name                = var.private_zone_name
  resource_group_name = var.resource_group_name
}
```

> These are **two different resource types** in Azure (`azurerm_dns_zone` vs
> `azurerm_private_dns_zone`) and the modules mirror that split. Do not reuse the public
> zone's values for the private one — see
> [Pattern 4](azure-troubleshooting.md#4-the-dns-module-only-creates-a-public-zone).

### Examples

**Resource Group excluded** → ask: RG name, location (if referenced)

**VNet excluded** → ask: subnet ID for AKS, VNet ID

**security excluded** → ask: public NSG ID, private NSG ID

> **Keep `gateways_enabled` / `gateway_internal_enabled` identical on `security` and `base`.**
> Their defaults do **not** match (`base` has `gateway_internal_enabled = true`, `security` has
> `false`), so leaving both to their defaults gives you an internal gateway whose NSG was never
> created. Pass them explicitly on both modules — see the `base` block in
> [azure-modules.md](azure-modules.md#base-azure-defaults-nullplatformbase).

## Step 4: Ask about Commons components

> **Input**: List of Commons modules
> **Output**: List of Commons modules to keep vs exclude

For each Commons module: **"Do you already have {component} installed or should we install it?"**

- **Install** → Keep the module block
- **I already have it** → Remove (generally no outputs referenced by other modules)

> Exception on Azure: excluding `cert_manager` or `external_dns` does **not** make the `iam`
> modules unnecessary — a pre-existing installation still needs a managed identity with
> `DNS Zone Contributor` (or equivalent) to write records. If the user excludes both and also
> excludes the IAM modules, confirm their existing installs already have that role assigned,
> or DNS-01 and record sync fail silently.

## Step 5: Apply changes to .tf files

> **Input**: Modules to exclude (steps 2+4), replacement values (step 3), all `.tf` files
> **Output**: Clean `.tf` files, updated `terraform.tfvars`, `existing-resources.properties`

Clean **all** `.tf` files, not just `main.tf`:

### 5.1 main.tf
- Remove `module` blocks for excluded resources
- Always remove `scope_notification_api_key` and `service_notification_api_key`
- Remove `depends_on` referencing deleted modules
- Replace `module.{excluded}.{output}` with `var.existing_{output}` or data sources
- If an IAM module is removed, also remove its `azure_client_id` / `azure_federated_credential_id`
  wiring from `cert_manager` / `external_dns_*`, and flip `azure_workload_identity_enabled`
  to `false` — leaving it `true` without a credential id fails a `validation` block

### 5.2 provider.tf
- If `aks` was excluded: repoint the `kubernetes` and `helm` providers at
  `data.azurerm_kubernetes_cluster.existing` (see [Provider Configuration](#existing-cluster-data-sources))
- `subscription_id` is required on the `azurerm` provider

### 5.3 variables.tf
- Remove orphaned variables (search `var.{name}` in all `.tf`, if not found → remove)
- Add new variables for existing resources (`var.existing_*`)

### 5.4 locals.tf
- Remove orphaned locals (search `local.{name}` in all `.tf`, if not found → remove)
- **Keep `local.private_gateway_name`** if the agent references it — the base chart hardcodes
  `gateway-private` and the agent has to be told the same name

### 5.5 outputs.tf
- Remove outputs referencing deleted modules
- **Never remove the public zone's `name_servers`** unless `dns` itself was excluded. The DNS
  delegation in step 5 of `SKILL.md` reads it, and without delegation no certificate is issued

### 5.6 data blocks
- Remove orphaned `data` blocks in any `.tf`

### 5.7 terraform.tfvars
- Add existing resource values: `existing_resource_group_name = "my-rg"`

### 5.8 existing-resources.properties
- Save as documentation: `resource_group_name=my-existing-rg`

> `existing-resources.properties` is documentation. Real values go in `terraform.tfvars`.

## Step 6: Validate .tf files

> **Input**: Modified `.tf` files, `terraform.tfvars`
> **Output**: Validated files, ready for `tofu plan`/`tofu apply`

```bash
cd infrastructure/azure
tofu fmt
tofu init -backend=false
tofu validate
```

Use `tofu init -backend=false` to validate without needing backend credentials. See [tofu-modules-patterns.md](tofu-modules-patterns.md#module-reading-flow) for inspecting downloaded module variables.

- **If it passes** → Continue with step 5 of SKILL.md (DNS)
- **If it fails** → Read error, fix, repeat. Common causes:
  - Reference to deleted module without replacement
  - Undefined variable or missing value in tfvars
  - `depends_on` pointing to deleted module
  - Output referencing deleted module
  - Orphaned local
  - A `validation` block tripped by a half-removed Workload Identity wiring (see 5.1)

## Azure Variables

In addition to the general variables documented in [variables.md](variables.md), Azure requires:

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `subscription_id` | Azure subscription. Required by the provider **and** by `resource_group`, `vnet` and `aks` | terraform.tfvars |
| `azure_tenant_id` | Azure AD tenant. Consumed by `cert_manager`, `external_dns` and `agent` — all three fail their preconditions without it | terraform.tfvars |
| `azure_location` | Azure region (e.g., `eastus`) | terraform.tfvars |
| `resource_group_name` | Resource group every resource in this setup lives in | terraform.tfvars |
| `organization_slug` | Drives cluster and resource names | common.tfvars |
| `domain_name` | Public application domain | common.tfvars |
| `private_domain_name` | Private domain backing the internal gateway. **Two constraints, see the note below** | common.tfvars |
| `address_space` | VNet address space. **Must not overlap `10.0.0.0/16`** — see the note below | terraform.tfvars |
| `subnets_definition` | Map of subnet objects (see [azure-modules.md](azure-modules.md#vnet-infrastructureazurevnet)) | terraform.tfvars |
| `authorized_ip_ranges` | CIDRs allowed to reach the AKS API server | terraform.tfvars |
| `containerregistry_name` | ACR name — **globally unique, alphanumeric only** | terraform.tfvars |
| `kubernetes_version` | **Verify before applying.** The module's default is stale — [Pattern 9](azure-troubleshooting.md#9-stale-module-defaults--kubernetes-version-and-vm-size) | terraform.tfvars |
| `system_pool_vm_size` / `user_pool_vm_size` | **Verify before applying.** The module's default is not available in every subscription — [Pattern 9](azure-troubleshooting.md#9-stale-module-defaults--kubernetes-version-and-vm-size) | terraform.tfvars |
| `dns_type` | `"external_dns"`. The module has no validation and its own description and comment list different values — [Known gaps](azure-troubleshooting.md#known-gaps) | terraform.tfvars |
| `external_dns_txt_owner_id` | Owner tag for external-dns's TXT registry. **Unique per cluster** — the module default is a generic literal that makes two setups delete each other's records | terraform.tfvars |
| `agent_azure_client_id` / `agent_azure_client_secret` | Service principal for the agent. **Required on Azure regardless of `dns_type`** — [Pattern 12](azure-troubleshooting.md#12-the-agent-needs-a-service-principal-on-azure) | terraform.tfvars |
| `agent_image_tag` | `"latest"` on Azure (AWS is the exception, it uses `"aws"`) | terraform.tfvars |
| `tags` | Azure resource tags | terraform.tfvars |

> **`containerregistry_name` is globally unique across all of Azure** and accepts only
> alphanumeric characters — no dashes, no underscores. `np{organization_slug}acr` with the
> slug's dashes stripped is a workable pattern. A name collision fails partway through the
> apply, not at plan time.

> **`authorized_ip_ranges` gates the machine running tofu.** If the API server is restricted
> and the address running tofu is not in the list, every `kubernetes`/`helm` resource times
> out against a perfectly healthy cluster.

> **`address_space` must stay out of `10.0.0.0/16`.** That is AKS's default service CIDR, and the
> `aks` module does not expose `net_profile_service_cidr` — the VNet is the only thing that can
> move. `10.10.0.0/16` works. See
> [Pattern 10](azure-troubleshooting.md#10-the-vnet-range-collides-with-the-aks-service-cidr).

> **`private_domain_name` carries two constraints, and neither is obvious.**
>
> 1. **On GCP it holds the same value as `domain_name`** (split horizon), because the `dns` and
>    `private_dns` modules are separate — the same shape as Azure. But **split horizon does not
>    work on Azure yet**
>    ([Pattern 14](azure-troubleshooting.md#14-external-dns-split-horizon-is-not-supported-on-azure)),
>    so a setup that needs an internal gateway today has to use a *different* private domain and
>    run the public external-dns instance only.
> 2. **Whatever value it takes must be inside the public zone.** `cert_manager` generates two
>    ClusterIssuers and both are given the same `azure_hosted_zone_name` (the public zone), while
>    the internal one carries `selector.dnsZones = [<private_domain_name>]`. So the DNS-01
>    challenge for the private domain is written into the **public** zone. That resolves only if
>    the private domain is the public one or a subdomain of it — `internal.<domain>` works, an
>    unrelated `poc.internal` never issues.

## Provider Configuration

### Azure Provider

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm      = { source = "hashicorp/azurerm",    version = "~> 4.0" }
    helm         = { source = "hashicorp/helm",       version = "~> 3.0" }
    kubernetes   = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    nullplatform = { source = "nullplatform/nullplatform", version = "~> 0.0.X" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "nullplatform" {
  api_key = var.np_api_key
}
```

> `features {}` is mandatory on the `azurerm` provider even when empty.
> Do not hardcode the `nullplatform` provider version — resolve the latest at generation time
> as [infrastructure-generation.md](infrastructure-generation.md) requires.

For generic providers (kubernetes, helm, nullplatform) see [tofu-modules-patterns.md](tofu-modules-patterns.md#generic-provider-versions).

### New cluster (created by tofu)

**Use the `admin_*` outputs.** This module always turns on AAD-managed integration (it passes
`rbac_aad_tenant_id`), and on an AAD-managed cluster `kube_config` returns an **exec plugin**, not
a client certificate — so `module.aks.client_certificate` and `client_key` are empty and every
chart fails with `the server has asked for the client to provide credentials`. The `admin_*`
outputs come from `kube_admin_config`, which does carry a certificate. See
[Pattern 11](azure-troubleshooting.md#11-the-provider-blocks-must-use-the-admin-kubeconfig).

```hcl
provider "kubernetes" {
  host                   = module.aks.host
  cluster_ca_certificate = base64decode(module.aks.admin_cluster_ca_certificate)
  client_certificate     = base64decode(module.aks.admin_client_certificate)
  client_key             = base64decode(module.aks.admin_client_key)
}

provider "helm" {
  kubernetes = {
    host                   = module.aks.host
    cluster_ca_certificate = base64decode(module.aks.admin_cluster_ca_certificate)
    client_certificate     = base64decode(module.aks.admin_client_certificate)
    client_key             = base64decode(module.aks.admin_client_key)
  }
}
```

> There is **no `admin_host` output** — `host` is the same FQDN in both views, so mix it with the
> `admin_*` certificates.
>
> AKS outputs: `host`, `cluster_ca_certificate`, `client_certificate`, `client_key`,
> `admin_cluster_ca_certificate`, `admin_client_certificate`, `admin_client_key`, plus
> `cluster_name`, `oidc_issuer_url` and `node_resource_group`. All credential outputs are
> `sensitive`.
> Helm v3: see [tofu-modules-patterns.md](tofu-modules-patterns.md#helm-v3-syntax).
>
> The `admin_*` outputs are wrapped in `try(...)` and go `null` when **`disableLocalAccounts =
> true`**. That is *not* this module's default, so they are populated on a normal setup — but if a
> cluster does disable local accounts, neither output set works from Terraform and the layer needs
> a `kubelogin` exec block instead. Nothing in the module exposes that flag today.

### Existing cluster (data sources)

```hcl
data "azurerm_kubernetes_cluster" "existing" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.existing.kube_config[0].host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_key)
}

provider "helm" {
  kubernetes = {
    host                   = data.azurerm_kubernetes_cluster.existing.kube_config[0].host
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].cluster_ca_certificate)
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.existing.kube_config[0].client_key)
  }
}
```

> `kubelogin` / `az aks get-credentials` are needed for `kubectl` afterwards. Tofu does not
> need them (it uses the certificate directly), so a missing tool surfaces only during
> post-apply validation.

## Next

- Writing the module blocks → [azure-modules.md](azure-modules.md)
- Before the first apply, and whenever something fails → [azure-troubleshooting.md](azure-troubleshooting.md)
