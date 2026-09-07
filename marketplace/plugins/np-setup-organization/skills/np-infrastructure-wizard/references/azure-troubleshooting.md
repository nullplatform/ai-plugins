# Azure Troubleshooting and Critical Patterns

> Companion to [azure.md](azure.md). Read this **before a greenfield apply** and whenever
> something fails. For the decision tree see [azure.md](azure.md); for module contracts see
> [azure-modules.md](azure-modules.md).

> **Confidence markers.** Azure has less field coverage than AWS, which is the reference
> implementation used in production, so every pattern is labelled:
>
> - **`OBSERVED`** — hit on a real Azure apply.
> - **`DERIVED`** — reasoned from module source at `v7.1.0` and internally consistent, but
>   **not confirmed on a live apply**. Treat as a strong hint. If you hit one of these and it
>   turns out different, update this file rather than working around it silently.
>
> There is no Azure equivalent yet of the GCP pattern list built from a full apply. Gaps are
> listed at the end.

## Critical Azure Patterns

### 1. AcrPull role — `for_each` with an ACR created in the same run

**`OBSERVED`.** Applies to a from-scratch apply (new RG + VNet + AKS + ACR in one run).

The `aks` module gates the AcrPull role on `acr_id`. When the ACR is created in the same
apply, `acr_id` is unknown at plan time, so the `for_each` key set is unknown and the plan
fails with **"Invalid for_each argument"**.

- **tofu-modules with `attach_acr`**: set `attach_acr = true` on the `aks` module. That
  fixes the `for_each` key set at plan time regardless of `acr_id`, so greenfield applies
  in a single run. (Leaving it unset keeps the legacy `acr_id != null` gate, which still
  fails on greenfield.)
- **Older pins (e.g. `v6.2.2`)**: two-phase apply.

  ```bash
  # Phase 1 — everything except the ACR role assignment (acr_id still unknown)
  tofu apply -var-file="../../common.tfvars" -var-file="terraform.tfvars" \
    -exclude=module.aks.module.aks.azurerm_role_assignment.acr
  # Phase 2 — normal apply; acr_id is now in state, role assignment resolves
  tofu apply -var-file="../../common.tfvars" -var-file="terraform.tfvars"
  ```

### 2. Perpetual route-table drift on the node-pool subnet (kubenet)

**`OBSERVED`.**

With **kubenet**, AKS creates a route table in the managed (`MC_`) resource group and
associates it with the node-pool subnet for pod-CIDR routing. The VNet module's underlying
AVM submodule always renders the `route_table` field, so leaving it out of
`subnets_definition` is an explicit **detach**, not an omission — **every plan wants to
remove it** (`routeTable.id` → null). Applying that **breaks pod networking**.

> **This is not a conditional case: every cluster from this module is kubenet.**
> `infrastructure/azure/aks` wraps `Azure/aks/azurerm` v11.0.0 and does **not** expose
> `network_plugin`; the upstream default is `kubenet`. Confirmed on an applied cluster
> (`networkProfile.networkPlugin = kubenet`). Azure CNI would remove this whole class of drift,
> but there is no way to ask for it from the caller — that is a module change, not a choice.

**Only one of the two ways out actually works — and it needs two passes.**

- **Let the subnet own it.** `subnets_definition` accepts an optional
  `route_table = { id = ... }` per subnet. Declaring it makes the subnet's desired state
  match reality and the drift stops for good — the plan goes quiet. (The module's own
  `variables.tf` documents this.)

  On greenfield this takes **two passes**: the id belongs to a route table AKS creates, which
  needs the subnet to exist first. Get it after the first apply:

  ```bash
  az network route-table list \
    -g $(az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv) \
    --query '[0].id' -o tsv
  ```

- **`OBSERVED` — do NOT wire the `aks_route_table` module.** It re-associates the route table on
  every apply, but it **races the VNet module's detach inside the same apply**: both issue a
  `PUT` on the same subnet and Azure cancels one of them.

  ```
  # module.vnet…subnet["aks"] has changed              <- AKS attached the route table
  # module.vnet…subnet["aks"] will be updated in-place <- the vnet wants to detach it
  # module.aks_route_table…will be updated in-place    <- and this one to re-attach it

  Error: Failed to create/update resource
    ERROR CODE: Canceled
    CanceledAndSupersededDueToAnotherOperation
    Operation PutSubnetOperation (ab25f86d…) was canceled and superseded by
    operation PutSubnetOperation (6f4af59e…)
  ```

- **Until the route table is declared — never apply the removal.** `-exclude` on the subnet
  does not help (the subnet is upstream of AKS→agent→everything, so it drags almost the
  whole graph). Use `-target` for the resources you actually want instead.

### 3. Workload Identity needs one `iam` invocation per consumer

**`DERIVED`** from `infrastructure/azure/iam` at `v7.1.0`.

The module creates exactly one of each:

```hcl
azurerm_user_assigned_identity.this          # name
azurerm_federated_identity_credential.this   # subject system:serviceaccount:{namespace}:{service_account_name}
azurerm_role_assignment.this                 # role_definition_name on scope
```

The federated credential's subject is pinned to a single KSA, so two consumers cannot share
one invocation. cert-manager gets one. external-dns gets one **per instance** when the
private zone is in play, because public and private DNS are different Azure resource types
and need different roles (`DNS Zone Contributor` vs `Private DNS Zone Contributor`) on
different resources.

Two outputs are easy to swap and they are not interchangeable:

| Output | Feeds | What it is |
|---|---|---|
| `client_id` | `azure_client_id` | The managed identity's client id |
| `id` | `azure_federated_credential_id` | The managed identity's **resource id** |

`commons/cert_manager` enforces this with a `validation` block whose error message names
`module.iam` explicitly:

> `azure_federated_credential_id is required when cloud_provider is 'azure' and azure_workload_identity_enabled is true. Use module.iam to create the federated identity credential and pass its id output.`

The mirror-image validation is that `azure_workload_identity_enabled = false` **requires**
`azure_client_secret`. There is no third path — half-configured Workload Identity fails at
plan time, which is the good case.

> This is exactly the situation `infrastructure-generation.md` warns about: a variable with a
> default **and** a `validation` block is conditionally required. Read the validations.

### 4. The `dns` module only creates a public zone

**`DERIVED`** from `infrastructure/azure/dns` at `v7.1.0` — but it is a source-level fact,
not an inference.

The module's entire `main.tf` is one resource, `azurerm_dns_zone.public_dns_zone`. Its
outputs then include:

```hcl
output "private_dns_zone_name" { value = azurerm_dns_zone.public_dns_zone.name }
output "private_dns_zone_id"   { value = azurerm_dns_zone.public_dns_zone.id }
```

Both **alias the public zone**. Anything wired to `module.dns.private_dns_zone_id` silently
points at the public zone: the private external-dns instance writes public records, or the
private role assignment grants access to the wrong resource. Nothing errors.

The real private zone comes from the separate `private_dns` module, which creates an
`azurerm_private_dns_zone` and requires `virtual_network_links` — a private zone with no VNet
link resolves for nobody.

> Worth reporting upstream. Until it changes, treat `module.dns`'s two private outputs as if
> they did not exist.

### 5. Two external-dns instances, one namespace

**`DERIVED`** from `commons/external_dns` at `v7.1.0`; the equivalent on GCP and AWS is
`OBSERVED`, so the mechanism is well established.

> **Read [Pattern 14](#14-external-dns-split-horizon-is-not-supported-on-azure) before using
> this.** Two instances are currently **not implementable** on Azure — the namespace race below
> is a real detail of a pattern that does not work end to end yet. This section describes the
> target shape for when the module is fixed.

Both instances land in the same namespace. Only the public one creates it; the private one
sets `create_namespace = false` and takes `depends_on = [module.external_dns_public]`.
Letting both create it is a race that fails the apply on whichever loses, intermittently,
which makes it read like a transient error.

On Azure the two instances also differ in `dns_provider_name` (`azure` vs
`azure-private-dns`) — both are in the module's validation list, and they share auth, secret
mount and ServiceAccount wiring, differing only in the external-dns `provider.name`.

> Watch the variable names: `commons/cert_manager` takes `azure_resource_group_name`, while
> `commons/external_dns` takes `azure_resource_group`. Same concept, different spelling.

### 6. ACR names are globally unique and alphanumeric only

**`DERIVED`** from Azure's own naming rules; `containerregistry_name` is a plain required
input with no validation in the module.

`np{organization_slug}acr` with dashes stripped is a workable pattern. A collision fails
**partway through the apply**, after the resource group and possibly the VNet already exist —
not at plan time. Check availability before the first apply.

### 7. `base` takes no `nrn`

**`OBSERVED`** (cloud-independent).

`nullplatform/base` does not declare `variable "nrn"` at `v7.1.0` or on `main`; it derives
its scope from the API key. Passing it is a hard `Unsupported argument` at plan time. `nrn`
is still required by `agent` and `agent_api_key`.

### 8. Azure backend

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "my-tfstate-rg"
    storage_account_name = "mytfstatesa"
    container_name       = "tfstate"
    key                  = "infrastructure/azure/terraform.tfstate"
  }
}
```

The storage account holding the state cannot be managed by the Terraform that stores its
state in it, so it is created once, by hand:

```bash
az group create --name <rg> --location <location>
az storage account create --name <sa> --resource-group <rg> \
  --location <location> --sku Standard_LRS --min-tls-version TLS1_2
az storage container create --name tfstate --account-name <sa> --auth-mode login
```

> Storage account names are **globally unique**, 3–24 characters, lowercase alphanumeric
> only — the same class of constraint as ACR. There is no `profile` equivalent as in the S3
> backend; `azurerm` uses the ambient Azure CLI login. Confirm `az account show` matches the
> intended subscription before `tofu init`.

### 9. Stale module defaults — Kubernetes version and VM size

**`OBSERVED`.** Two `infrastructure/azure/aks` defaults have aged out of what Azure accepts.
Neither is caught by `tofu validate` **or** `tofu plan` — Terraform cannot know what a
subscription allows until it asks.

```
"code": "K8sVersionNotSupported",
"message": "Managed cluster <name> is on version 1.32.7, which is only available for
            Long-Term Support (LTS). To enable LTS on the cluster, see
            https://aka.ms/aks/enable-lts."
```

The module pins `kubernetes_version = "1.32.7"`. The upstream AVM module defaults it to `null`
(= latest in the region); this module replaces a default that ages well with one that ages badly.

**Bumping the patch does not fix it — the minor has to move.** Verified: `1.33.12` fails with the
same error. In `eastus` as of 2026-08, `1.31`/`1.32`/`1.33` are **LTS-only**; only `1.34`, `1.35`
and `1.36` carry `KubernetesOfficial`.

**`az aks get-versions -o table` does not show the support plan.** Use the JSON:

```bash
az aks get-versions --location <loc> -o json \
  | jq -r '.values[] | "\(.version) \(.capabilities.supportPlan | join(","))"'
```

```
"code": "BadRequest",
"message": "The VM size of Standard_D2s_v5 is not allowed in your subscription in
            location '<loc>'. The available VM sizes are '<hundreds of SKUs>'"
```

`system_pool_vm_size` and `user_pool_vm_size` both default to `Standard_D2s_v5`, which is not
enabled in every subscription. Check before applying — and note the error dumps the entire
allow-list, which buries everything else in the output:

```bash
az vm list-skus --location <loc> --resource-type virtualMachines \
  --query "[?name=='<sku>'].restrictions"
```

> **Check the vCPU quota too.** A fresh subscription can carry a `Total Regional vCPUs` limit as
> low as 10. The module defaults (system pool 2 nodes + user pool min 1) are 3 nodes; at 2 vCPU
> each that is 6, and a roomier sizing hits the ceiling.
> `az vm list-usage --location <loc>` shows it.

### 10. The VNet range collides with the AKS service CIDR

**`OBSERVED`.**

```
"code": "ServiceCidrOverlapExistingSubnetsCidr",
"message": "The specified service CIDR 10.0.0.0/16 is conflicted with an existing
            subnet CIDR 10.0.1.0/24."
```

`10.0.0.0/16` is AKS's **default service CIDR**, and `infrastructure/azure/aks` does not expose
`net_profile_service_cidr`, `net_profile_dns_service_ip` or `net_profile_pod_cidr` — nothing
reaches the AVM module, whose own defaults are `null`, so AKS decides. **There is no way to move
the service CIDR from the caller.** The VNet is what has to move: use `10.10.0.0/16` or anything
else outside `10.0.0.0/16`.

> **Migration note.** If a setup already applied with a colliding range, the fix is to **recreate**
> the VNet, not update it. Changing `address_space` while the old subnet is still in place fails
> with `NetcfgSubnetRangeOutsideVnet` — Azure validates the VNet `PUT` against subnets that no
> longer fit. Destroy `module.vnet` (and any `private_dns` VNet link that depends on it) first.

### 11. The provider blocks must use the admin kubeconfig

**`OBSERVED`.** This one blocks **every** `helm_release` and `kubernetes_*` resource in the layer —
istio, cert-manager, external-dns, prometheus, `base` and `agent`.

```
Error: installation failed
Kubernetes cluster unreachable: the server has asked for the client to provide credentials
```

`infrastructure/azure/aks` passes `rbac_aad_tenant_id`, which turns on **AAD-managed**
integration (`aadProfile.managed = true`). With AAD managed, `kube_config` returns an **exec
plugin** (devicecode + `kubelogin`), not a client certificate — so `module.aks.client_certificate`
and `client_key` come back empty. Measured on a real cluster:

| View | `client-certificate-data` | `exec:` | Authenticates? |
|---|---|---|---|
| `kube_config` | **0** | 2 | **no** |
| `kube_admin_config` | 1 | 0 | **yes** |

Wire the providers to the **`admin_*`** outputs. They are `try()`-wrapped and are only `null` when
`disableLocalAccounts = true`, which is **not** this module's default:

```hcl
provider "kubernetes" {
  host                   = module.aks.host
  cluster_ca_certificate = base64decode(module.aks.admin_cluster_ca_certificate)
  client_certificate     = base64decode(module.aks.admin_client_certificate)
  client_key             = base64decode(module.aks.admin_client_key)
}
```

> There is **no `admin_host` output** — mix `host` (from `kube_config`) with the `admin_*`
> certificates. The FQDN is the same in both views.
>
> If a setup does disable local accounts, neither path works from Terraform and the layer needs
> `kubelogin` in an exec block instead. Nothing in the module exposes that flag today.

### 12. The agent needs a service principal on Azure

**`OBSERVED`.** The `agent` module's eight Azure preconditions include `azure_client_id` and
`azure_client_secret`, and **`dns_type` does not participate in any of them** — the credentials
have to exist even with external-dns owning every record. That makes an app registration a
prerequisite of the first apply, the Azure equivalent of enabling the GCP project APIs.

```bash
az ad sp create-for-rbac --name np-agent-<setup> --role Reader \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>
```

`Reader` is enough with `dns_type = "external_dns"`. With `dns_type = "azure"` the agent writes
records itself and needs `DNS Zone Contributor` (plus `Private DNS Zone Contributor` when a
private zone is in play).

Feed the `appId` to `agent_azure_client_id` and the `password` to `agent_azure_client_secret`,
both from `terraform.tfvars` (gitignored — the secret is long-lived).

### 13. `cert_manager` and `base` have to interleave

**`OBSERVED`.**

```
release cert-manager-config failed, and has been uninstalled due to atomic being set:
2 errors occurred:
  * namespaces "gateways" not found
```

`commons/cert_manager` ships **two** Helm releases: `cert_manager` (the chart) and
`cert_manager_config` (the ClusterIssuers). The second deploys into the `gateways` namespace,
which **`base`** creates. But `base` needs cert-manager's CRDs first, for its wildcard
`Certificate`. The real order is:

```
cert_manager (chart)  ->  base  ->  cert_manager_config
```

The module bundles both releases, so **the caller cannot order them separately**. Apply in two
passes: everything except `base`, then `base`, then re-apply `cert_manager` so it picks up
`cert_manager_config`. This works because the failure is atomic — the release is rolled back and
Terraform retries it cleanly on the next run.

### 14. external-dns split horizon is not supported on Azure

**`OBSERVED`.** Two independent blockers at `v7.1.0`, neither with a caller-side workaround.

```
Error: secrets "external-dns-azure-config" already exists
  with module.external_dns_private.kubernetes_secret_v1.external_dns_azure_config[0],
  on commons/external_dns/secret.tf line 13
```

1. **The secret name is hardcoded.** `secret.tf` sets `name = "external-dns-azure-config"`, which
   does not vary by `var.type`, and both instances share `external_dns_namespace`. There is no
   variable to override it. Sharing one secret is not a fix either: the two instances need
   different `azure_client_id`s, and the public identity has no `Private DNS Zone Contributor`.
   Expressing that would take one managed identity with two federated credentials, which
   `infrastructure/azure/iam` cannot produce — see
   [Pattern 3](#3-workload-identity-needs-one-iam-invocation-per-consumer).
2. **`--label-filter` never reaches the Azure path.** Only `route53_config` builds `extraArgs`;
   `azure_config` has none, so `label_filter` and `zone_type` are computed into
   `local.effective_label_filter` and dropped. Confirmed on a running pod — the deployment's args
   are `--source=crd --policy=sync --registry=txt --txt-owner-id=… --domain-filter=… --provider=azure`
   and nothing else. With split horizon that label is the only thing separating the instances, so
   the public one reads the private DNSEndpoints and publishes **public records pointing at
   internal IPs**.

**Generate the public instance only, and tell the user why.** Both blockers are one-line module
fixes (`external-dns-azure-config-${var.type}`, and `extraArgs` on `azure_config`); until they
land, split horizon on Azure produces a setup that is worse than a single instance.

> **This also constrains `private_domain_name`** — see the note in
> [azure.md](azure.md#azure-variables).

## Troubleshooting

| Symptom | Probable cause | Fix |
|---|---|---|
| `Invalid for_each argument` on the ACR role assignment | ACR created in the same apply, `acr_id` unknown at plan time | [Pattern 1](#1-acrpull-role--for_each-with-an-acr-created-in-the-same-run) — `attach_acr = true` |
| Every plan wants to remove the node subnet's route table | kubenet route table not modelled by the VNet module | [Pattern 2](#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet) — declare `route_table` or wire `aks_route_table` |
| Pod networking breaks after an apply | The route-table removal was applied | [Pattern 2](#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet) — re-associate it |
| `azure_federated_credential_id is required ...` at plan time | Workload Identity enabled without the credential id | [Pattern 3](#3-workload-identity-needs-one-iam-invocation-per-consumer) — pass `module.iam_*.id` |
| `azure_client_secret is required ...` at plan time | Workload Identity disabled and no secret | [Pattern 3](#3-workload-identity-needs-one-iam-invocation-per-consumer) — prefer enabling Workload Identity |
| cert-manager / external-dns pod runs but every DNS write is denied | `client_id` and `id` swapped, or the role assigned on the wrong scope | [Pattern 3](#3-workload-identity-needs-one-iam-invocation-per-consumer) |
| Private hostnames resolve publicly, or not at all | Something wired to `module.dns.private_dns_zone_*`, which aliases the public zone | [Pattern 4](#4-the-dns-module-only-creates-a-public-zone) — use `module.private_dns` |
| Private zone resolves for nobody | `private_dns` created without `virtual_network_links` | Link the VNet |
| Namespace already exists / intermittent apply failure on external-dns | Both instances creating the namespace | [Pattern 5](#5-two-external-dns-instances-one-namespace) — `create_namespace = false` on the private one |
| Apply fails on ACR creation partway through | Name collision (globally unique) or a non-alphanumeric character | [Pattern 6](#6-acr-names-are-globally-unique-and-alphanumeric-only) |
| `Unsupported argument: nrn` on `module.base` | `nrn` passed to `base`, which does not declare it | [Pattern 7](#7-base-takes-no-nrn) |
| `Invalid index` on `module.vnet.subnet_ids["aks"]` | `subnet_ids` is keyed by the subnet's **name**, not the map key | [azure-modules.md — VNet](azure-modules.md#vnet-infrastructureazurevnet) |
| `K8sVersionNotSupported … only available for Long-Term Support` | `kubernetes_version` left at the module default | [Pattern 9](#9-stale-module-defaults--kubernetes-version-and-vm-size) — move the **minor**, not the patch |
| `The VM size of … is not allowed in your subscription` | `*_vm_size` left at the module default | [Pattern 9](#9-stale-module-defaults--kubernetes-version-and-vm-size) |
| `ServiceCidrOverlapExistingSubnetsCidr` | VNet inside `10.0.0.0/16`, AKS's default service CIDR | [Pattern 10](#10-the-vnet-range-collides-with-the-aks-service-cidr) — move the VNet |
| `NetcfgSubnetRangeOutsideVnet` while fixing the range | `address_space` changed with the old subnet still in place | [Pattern 10](#10-the-vnet-range-collides-with-the-aks-service-cidr) — recreate, don't update |
| `Kubernetes cluster unreachable: the server has asked for the client to provide credentials` | Providers wired to `kube_config` on an AAD-managed cluster | [Pattern 11](#11-the-provider-blocks-must-use-the-admin-kubeconfig) — use the `admin_*` outputs |
| `Cannot include a null value in a string template` on the agent | One of the agent's eight Azure variables is missing | [Pattern 12](#12-the-agent-needs-a-service-principal-on-azure) |
| `azure_client_id is required when cloud_provider is 'azure'` | No service principal for the agent | [Pattern 12](#12-the-agent-needs-a-service-principal-on-azure) |
| `namespaces "gateways" not found` on `cert-manager-config` | `cert_manager` applied before `base` | [Pattern 13](#13-cert_manager-and-base-have-to-interleave) — two passes |
| `secrets "external-dns-azure-config" already exists` | Two external-dns instances on Azure | [Pattern 14](#14-external-dns-split-horizon-is-not-supported-on-azure) — public only |
| Public records pointing at internal IPs | `--label-filter` is never emitted on the Azure path | [Pattern 14](#14-external-dns-split-horizon-is-not-supported-on-azure) |
| `Resource Group … was not found` on `data.azurerm_resource_group.aks_rg` | Full greenfield plan attempted before the RG exists | Expected — apply the RG first, see `SKILL.md` step 5.3 |
| `InUseSubnetCannotBeDeleted` during `destroy` | AKS's internal load balancer still holds a frontend IP in the subnet | Transient — re-run `destroy` once the `MC_*` RG is gone |
| Every plan wants to delete the node subnet's route table, and `aks_route_table` is wired | The two modules race on the same subnet | [Pattern 2](#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet) — declare `route_table`, drop the module |
| `kubernetes`/`helm` resources time out from the start | Machine running tofu not in `authorized_ip_ranges` | Add its egress CIDR |
| Certificates stuck in `PENDING_VALIDATION`, then time out | DNS zone not delegated | `SKILL.md` step 5 |
| `kubectl` fails after a successful apply | `kubelogin` missing / no `az aks get-credentials` | Tofu uses the client certificate directly; kubectl does not |

## Provider warnings you will see, and what they mean

None of these break an apply today. The first one breaks the next major provider bump.

- **`azurerm_federated_identity_credential.resource_group_name` is deprecated** — *"This field is
  no longer used and will be removed in the next major version of the Azure Provider."*
  `infrastructure/azure/iam` passes it, so you get one warning per `iam` invocation (three in a
  full setup). **`azurerm` 5.x is already released**, and the modules pin `~> 4.0`, so this is a
  module fix waiting to happen rather than a cosmetic warning.
- **`modtm_telemetry` + `random_uuid` in the VNet plan.** The AVM module sends usage telemetry to
  Microsoft by default. Harmless, but on a client PoC set `enable_telemetry = false` — and expect
  the two resources in the plan if you don't.
- **`azapi_resource.retry.multiplier` / `randomization_factor` deprecated** — four warnings from
  inside the AVM subnet submodule. Nothing to do from the caller.

## Known gaps

Not covered here because there is no verified source for them yet. If you hit any of these,
document what actually happened:

- **Whether `azurerm` registers the resource providers on its own.** A virgin subscription starts
  with `Microsoft.ContainerService`, `ContainerRegistry`, `Network`, `Storage`, `ManagedIdentity`,
  `OperationalInsights` and `Compute` all `NotRegistered`. The provider schema exposes
  `resource_provider_registrations`, `resource_providers_to_register` and
  `skip_provider_registration`, so it *can* — but the schema does not say what the default set
  covers. On the run this file is based on they were registered by hand first, so the question is
  still open. Resolve it on a virgin subscription before writing a `Step 0`:

  ```bash
  az provider show -n Microsoft.ContainerService --query registrationState -o tsv
  ```

  Either way, `gcp.md`'s claim that "unlike AWS and Azure, GCP requires the per-project service
  APIs to be enabled" is at best imprecise for Azure.
- **Which `dns_type` Azure should use.** The agent's variable description lists `azure`,
  `route53` and `external_dns`, its own comment lists `azure`, `aws`, `gcp` and `external_dns`,
  and the variable defaults to `""` with no validation block — so nothing in the modules forces a
  choice, and the two lists in the module disagree with each other. Setups so far use
  `external_dns`. Ask the user and record the answer rather than guessing.
- **What the agent actually does with its Azure credentials under `dns_type = "external_dns"`.**
  That they are *required* is settled — [Pattern 12](#12-the-agent-needs-a-service-principal-on-azure).
  Whether anything reads them is not, so the least-privilege scope is still a guess (`Reader` was
  enough to apply, but nothing exercised the credential).
- **Node pool sizing that leaves room for the platform components.** A 3-node
  `Standard_D2s_v7` cluster (2 system + 1 user) carried istio, cert-manager, external-dns,
  prometheus, `base` and the agent with everything `Running` — but nothing was deployed on top of
  it, so this is a floor, not a recommendation.
- **Anything ARO-specific** — [azure-aro.md](azure-aro.md) is still a stub and ARO is OpenShift,
  not AKS.

**Closed since the first draft of this file** — a greenfield Azure apply *does* need a phased
first pass, and the phases are now documented: the resource group has to exist before a full plan
resolves at all ([the symptom table](#troubleshooting)), and `cert_manager` has to straddle `base`
([Pattern 13](#13-cert_manager-and-base-have-to-interleave)). Azure CNI vs kubenet is also closed,
though not the way the question was asked: the module gives no choice
([Pattern 2](#2-perpetual-route-table-drift-on-the-node-pool-subnet-kubenet)).

For generic problems see [troubleshooting.md](troubleshooting.md).
