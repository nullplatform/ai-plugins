# Decision Tree - Azure Infrastructure

> Invoked from step 4 of the main wizard (`SKILL.md`).
> **Global input**: `infrastructure/azure/` with original .tf files
> **Global output**: Customized .tf files, `existing-resources.properties` (if applicable), new variables in `terraform.tfvars`

## Contents

1. [Module Classification](#step-1-module-classification)
2. [Ask about Cloud components](#step-2-ask-about-each-cloud-component)
3. [Resolve excluded dependencies](#step-3-resolve-excluded-module-dependencies)
4. [Ask about Commons components](#step-4-ask-about-commons-components)
5. [Apply changes to .tf](#step-5-apply-changes-to-tf-files)
6. [Validate .tf files](#step-6-validate-tf-files)

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
| `base_security` | Do you already have NSGs for the gateways? |

### Nullplatform (always included, don't ask)

- `agent_api_key`, `agent`, `base`

Always remove: `scope_notification_api_key`, `service_notification_api_key`

### Commons (askable)

| Module | Question |
|--------|----------|
| `cert_manager` | Do you already have cert-manager installed? |
| `istio` | Do you already have Istio installed? |
| `external_dns` | Do you already have external-dns configured? |
| `prometheus` | Do you already have Prometheus installed? |

## Step 2: Ask about each Cloud component

> **Input**: List of Cloud modules
> **Output**: List of modules to keep vs exclude

For each Cloud module, ask: **"Do you already have a {resource} or do you need it created?"**

- **Create new** → Keep the module block
- **I already have one** → Add to excluded list, resolve dependencies in step 3

### Question order (respect dependencies)

1. `resource_group` (many depend on this)
2. `vnet` (depends on resource_group)
3. `aks` (depends on resource_group, vnet)
4. `acr` (depends on resource_group)
5. `dns` (depends on resource_group)
6. `private_dns` (depends on resource_group, vnet)
7. `base_security` (depends on resource_group)

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

### Examples

**Resource Group excluded** → ask: RG name, location (if referenced)

**VNet excluded** → ask: subnet ID for AKS, VNet ID

**base_security excluded** → ask: public NSG ID, private NSG ID

## Step 4: Ask about Commons components

> **Input**: List of Commons modules
> **Output**: List of Commons modules to keep vs exclude

For each Commons module: **"Do you already have {component} installed or should we install it?"**

- **Install** → Keep the module block
- **I already have it** → Remove (generally no outputs referenced by other modules)

## Step 5: Apply changes to .tf files

> **Input**: Modules to exclude (steps 2+4), replacement values (step 3), all `.tf` files
> **Output**: Clean `.tf` files, updated `terraform.tfvars`, `existing-resources.properties`

Clean **all** `.tf` files, not just `main.tf`:

### 5.1 main.tf
- Remove `module` blocks for excluded resources
- Always remove `scope_notification_api_key` and `service_notification_api_key`
- Remove `depends_on` referencing deleted modules
- Replace `module.{excluded}.{output}` with `var.existing_{output}`

### 5.2 variables.tf
- Remove orphaned variables (search `var.{name}` in all `.tf`, if not found → remove)
- Add new variables for existing resources (`var.existing_*`)

### 5.3 locals.tf
- Remove orphaned locals (search `local.{name}` in all `.tf`, if not found → remove)

### 5.4 outputs.tf
- Remove outputs referencing deleted modules

### 5.5 data blocks
- Remove orphaned `data` blocks in any `.tf`

### 5.6 terraform.tfvars
- Add existing resource values: `existing_resource_group_name = "my-rg"`

### 5.7 existing-resources.properties
- Save as documentation: `resource_group_name=my-existing-rg`

> `existing-resources.properties` is documentation. Real values go in `terraform.tfvars`.

## Step 6: Validate .tf files

> **Input**: Modified `.tf` files, `terraform.tfvars`
> **Output**: Validated files, ready for `tofu plan`/`tofu apply`

```bash
cd infrastructure/azure
tofu fmt
tofu init
tofu validate
```

- **If it passes** → Continue with step 5 of SKILL.md (DNS)
- **If it fails** → Read error, fix, repeat. Common causes:
  - Reference to deleted module without replacement
  - Undefined variable or missing value in tfvars
  - `depends_on` pointing to deleted module
  - Output referencing deleted module
  - Orphaned local

## Greenfield first apply (Azure)

Two gotchas hit a from-scratch Azure apply (new RG + VNet + AKS + ACR in one run).
Both are Azure-specific; handle them before/around step 7 of `SKILL.md`.

### A. AcrPull role — `for_each` with an ACR created in the same run

The `aks` module gates the AcrPull role on `acr_id`. When the ACR is created in the
same apply, `acr_id` is unknown at plan time, so the `for_each` key set is unknown and
the plan fails with **"Invalid for_each argument"**.

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

### B. Perpetual route-table drift on the node-pool subnet (kubenet)

With **kubenet**, AKS creates a route table in the managed (`MC_`) resource group and
associates it with the node-pool subnet for pod-CIDR routing. The VNet module doesn't
model it, so **every plan wants to remove it** (`routeTable.id` → null). Applying that
**breaks pod networking**.

- **Durable fix — wire the `aks_route_table` module** (present in tofu-modules since
  `v6.2.2`). It discovers the AKS-managed route table from the node resource group and
  re-associates it with the subnet on every apply, so the drift stops. Add it downstream
  of `aks` (it needs `node_resource_group` and the subnet id).
- **If not wired — never apply the route-table removal.** `-exclude` on the subnet does
  not help (the subnet is upstream of AKS→agent→everything, so it drags almost the whole
  graph). Use `-target` for the resources you actually want instead.
- **For brand-new clusters with no kubenet requirement, prefer Azure CNI** — it doesn't
  use a subnet route table, removing this whole class of drift. Evaluate network
  semantics before choosing it for prod.
