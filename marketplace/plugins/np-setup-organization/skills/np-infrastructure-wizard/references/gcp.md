# Decision Tree - GCP Infrastructure

> Invoked from step 4 of the main wizard (`SKILL.md`).
> **Global input**: `infrastructure/gcp/` with original .tf files
> **Global output**: Customized .tf files, `existing-resources.properties` (if applicable), new variables in `terraform.tfvars`

> For general OpenTofu patterns (module source, Helm v3, agent_api_key) see [tofu-modules-patterns.md](tofu-modules-patterns.md).

> **This file is the entrypoint.** GCP reference material is split in three:
>
> | File | What lives there | Read it when |
> |---|---|---|
> | `gcp.md` (this one) | Decision tree (steps 0–6), variables, provider blocks | Always |
> | [gcp-modules.md](gcp-modules.md) | Module contracts and HCL blocks | Writing or editing `main.tf` |
> | [gcp-troubleshooting.md](gcp-troubleshooting.md) | The 11 critical patterns + symptom table | Something fails, or before a greenfield apply |

> **Provenance**: every module contract, variable and output in `gcp-modules.md` was read from
> `nullplatform/tofu-modules` at `v7.1.0`, cross-checked against a working GCP setup.
> `gcp-troubleshooting.md` documents failure modes observed on a real apply.
> **If you pinned a different `ref`**, re-read the module's `variables.tf` and `outputs.tf` from
> `.terraform/modules/` before trusting the contracts here.

## Contents

0. [Enable the GCP project APIs](#step-0-enable-the-gcp-project-apis)
1. [Module Classification](#step-1-module-classification)
2. [Ask about Cloud components](#step-2-ask-about-each-cloud-component)
3. [Resolve excluded dependencies](#step-3-resolve-excluded-module-dependencies)
4. [Ask about Commons components](#step-4-ask-about-commons-components)
5. [Apply changes to .tf](#step-5-apply-changes-to-tf-files)
6. [Validate .tf files](#step-6-validate-tf-files)
7. [GCP Variables](#gcp-variables)
8. [Provider Configuration](#provider-configuration)
9. [GCP Module Reference](gcp-modules.md)
10. [Critical GCP Patterns](gcp-troubleshooting.md#critical-gcp-patterns)
11. [Troubleshooting](gcp-troubleshooting.md#troubleshooting)

> **No schema decision on GCP.** Unlike AWS (which has an Istio schema and an ACM/Ingress
> schema — see [aws.md](aws.md) step 0), GCP has a single supported schema: **Istio +
> Gateway API + cert-manager + external-dns**, with `dns_type = "external_dns"`. There is
> no GCP-native certificate path equivalent to ACM in the modules. Do not ask the user to
> pick a schema; go straight to step 1.

## Step 0: Enable the GCP project APIs

> **Input**: `gcp_project_id`
> **Output**: Project ready for the first apply

Unlike AWS and Azure, GCP requires the per-project service APIs to be enabled **before**
the first apply. A disabled API surfaces as a generic `403 ... has not been used in project
... or it is disabled`, which reads like a permissions problem and is not one.

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  dns.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  --project=<gcp_project_id>
```

Verify all seven before continuing — the filter must cover the same set that was enabled,
or a missing API surfaces later as a `403` mid-apply:

```bash
gcloud services list --enabled --project=<gcp_project_id> \
  --filter="config.name:(compute OR container OR dns OR artifactregistry OR iam OR cloudresourcemanager OR serviceusage)" \
  --format="value(config.name)"
```

The principal running tofu needs enough to create everything below — in practice
`roles/container.admin`, `roles/compute.networkAdmin`, `roles/dns.admin`,
`roles/artifactregistry.admin`, `roles/iam.serviceAccountAdmin`, plus
`roles/iam.serviceAccountKeyAdmin` if the bindings layer will create registry keys.

## Step 1: Module Classification

> **Input**: `infrastructure/gcp/main.tf`
> **Output**: Modules classified by category

Read `main.tf` dynamically and classify:

### Cloud (askable)

| Module | Question |
|--------|----------|
| `vpc` | Do you already have a VPC network? |
| `cloud_nat` | Do you already have Cloud NAT for the private nodes? |
| `dns_public` | Do you already have a public Cloud DNS zone? |
| `dns_private` | Do you already have a private Cloud DNS zone? |
| `gke` | Do you already have a GKE cluster? |
| `security` | Do you already have firewall rules for the gateways? |
| `artifact_registry` | Do you already have an Artifact Registry repository? |

**IAM modules** (askable, but see the note below — they are one question, not two):

| Module | Question |
|--------|----------|
| `iam` + `iam_workload_identity` | Do you already have the service accounts and Workload Identity bindings for cert-manager and external-dns? |

> Treat `iam` and `iam_workload_identity` as a **single** question. They are two invocations
> of the same `infrastructure/gcp/iam` module split on purpose (see
> [Pattern 2](gcp-troubleshooting.md#2-iam-is-invoked-twice-on-purpose)) — a user who already
> has the service accounts also already has their bindings, and a user who needs one needs both.

### Nullplatform (always included, don't ask)

- `agent_api_key`, `base`, `agent`

Always remove: `scope_notification_api_key`, `service_notification_api_key`

### Commons (askable)

| Module | Question |
|--------|----------|
| `istio` | Do you already have Istio installed? |
| `cert_manager` | Do you already have cert-manager installed? |
| `external_dns_public` + `external_dns_private` | Do you already have external-dns configured? |
| `prometheus` | Do you already have Prometheus installed? |

> **external-dns on GCP uses the shared module, and it is NOT optional.** Same module as AWS,
> `infrastructure/commons/external_dns`, with `dns_provider_name = "google"`. Do **not**
> generate a local `modules/external_dns_google/` — the latest release supports Cloud DNS.
> Wiring in
> [gcp-modules.md](gcp-modules.md#external-dns-infrastructurecommonsexternal_dns); why it is
> mandatory in [Pattern 1](gcp-troubleshooting.md#1-external-dns-is-not-optional-on-gcp).
> Treat the public and private instances as a single question, but expect **two** module blocks.

> ### STOP — do not generate a GCP setup without external-dns
>
> `dns_type = "external_dns"` (the only supported value on GCP) makes the agent emit
> `HTTPRoute` objects and nothing else. **external-dns is the component that turns those into
> Cloud DNS records.** A `main.tf` with `dns_type = "external_dns"` and no external-dns module
> is broken by construction: the cluster comes up, Istio comes up, scopes register fine, and
> **no application hostname ever resolves** — with no error anywhere in the apply.
>
> Before finishing step 5, assert both of these:
>
> ```bash
> grep -n 'dns_type' infrastructure/gcp/terraform.tfvars
> grep -n 'external_dns' infrastructure/gcp/main.tf
> ```
>
> If the first matches and the second does not, the setup is incomplete. Do not present it as
> done-with-a-known-gap and do not offer the user a menu of alternatives: wire the two shared
> `commons/external_dns` blocks from
> [gcp-modules.md](gcp-modules.md#external-dns-infrastructurecommonsexternal_dns). If the
> pinned `ref` rejects `dns_provider_name = "google"`, bump the ref — do not fall back to a
> local copy of the module.

## Step 2: Ask about each Cloud component

> **Input**: List of Cloud modules
> **Output**: List of modules to keep vs exclude

For each Cloud module, ask: **"Do you already have a {resource} or do you need it created?"**

- **Create new** → Keep the module block
- **I already have one** → Add to excluded list, resolve dependencies in step 3

### Question order (respect dependencies)

1. `vpc` (base of everything; owns the secondary ranges GKE needs)
2. `cloud_nat` (depends on `vpc.network_self_link`)
3. `dns_public` (independent)
4. `dns_private` (depends on `vpc.network_self_link` for the zone's visibility binding)
5. `gke` (depends on `vpc.network_name` + the secondary range names)
6. `security` (depends on `gke.cluster_name`)
7. `artifact_registry` (independent)
8. `iam` + `iam_workload_identity` (project-level roles; the bindings need the KSA
   namespaces of cert-manager and external-dns, so ask after the Commons step if unclear)

> If the user creates `vpc`, don't ask about its dependencies in other modules.
> If the user brings an existing VPC, the **secondary ranges must already exist on the
> subnet** — GKE cannot create them. Confirm this explicitly; it is the single most common
> blocker on a brownfield GCP setup.

## Step 3: Resolve excluded module dependencies

> **Input**: List of excluded modules, `main.tf`
> **Output**: Replacement values for each referenced output

When the user says "I already have" a resource:

1. Find all `module.{excluded_module}.{output}` references in maintained modules
2. Ask the user for the real value of each found reference
3. Save the values (used in step 5)

### Dynamic detection

```bash
grep -oP 'module\.{excluded_module}\.\w+' infrastructure/gcp/main.tf | sort -u
```

### Data sources for existing resources

When a resource already exists, use data sources instead of redundant variables.

**Always present, regardless of what is excluded** — the `kubernetes` and `helm` providers
need it for the access token:

```hcl
data "google_client_config" "default" {}
```

**Existing VPC + subnet**:
```hcl
variable "network_name" { type = string }
variable "subnet_name"  { type = string }

data "google_compute_network" "existing" {
  name    = var.network_name
  project = var.gcp_project_id
}

data "google_compute_subnetwork" "existing" {
  name    = var.subnet_name
  region  = var.gcp_region
  project = var.gcp_project_id
}
```

> `data.google_compute_subnetwork.existing.secondary_ip_range` is a list of
> `{range_name, ip_cidr_range}`. Use it to confirm the pods and services ranges exist and
> to feed `ip_range_pods` / `ip_range_services` on the `gke` module.

**Existing GKE cluster**:
```hcl
variable "cluster_name" { type = string }

data "google_container_cluster" "existing" {
  name     = var.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id
}
```

> Outputs to map: `endpoint` (replaces `module.gke.host`),
> `master_auth[0].cluster_ca_certificate` (replaces `module.gke.cluster_ca_certificate`),
> `name` (replaces `module.gke.cluster_name`).

**Existing Cloud DNS zones**:
```hcl
variable "public_zone_name"  { type = string }
variable "private_zone_name" { type = string }

data "google_dns_managed_zone" "public" {
  name    = var.public_zone_name
  project = var.gcp_project_id
}

data "google_dns_managed_zone" "private" {
  name    = var.private_zone_name
  project = var.gcp_project_id
}
```

> `name` here is the Cloud DNS **managed zone resource name**, not the DNS domain. The two
> are different values and mixing them is a common failure — see
> [Pattern 7](gcp-troubleshooting.md#7-zone-resource-name-vs-dns-domain).

**Existing service accounts (IAM excluded)**:
```hcl
variable "cert_manager_sa_email" { type = string }
variable "external_dns_sa_email" { type = string }
```

> Plain variables, not data sources: the modules consume the SA **email** and nothing else,
> so a lookup buys nothing over the value itself.

## Step 4: Ask about Commons components

> **Input**: List of Commons modules
> **Output**: List of Commons modules to keep vs exclude

For each Commons module: **"Do you already have {component} installed or should we install it?"**

- **Install** → Keep the module block
- **I already have it** → Remove (generally no outputs referenced by other modules)

> Exception on GCP: excluding `cert_manager` or `external_dns` does **not** make the `iam`
> service accounts unnecessary — the pre-existing installations still need Workload Identity
> to write to Cloud DNS. If the user excludes both and also excludes `iam`, confirm their
> existing installs already have `roles/dns.admin` bound, or DNS-01 and record sync fail
> silently.

## Step 5: Apply changes to .tf files

> **Input**: Modules to exclude (steps 2+4), replacement values (step 3), all `.tf` files
> **Output**: Clean `.tf` files, updated `terraform.tfvars`, `existing-resources.properties`

Clean **all** `.tf` files, not just `main.tf`:

### 5.1 main.tf
- Remove `module` blocks for excluded resources
- Always remove `scope_notification_api_key` and `service_notification_api_key`
- Remove `depends_on` referencing deleted modules
- Replace `module.{excluded}.{output}` with `var.existing_{output}` or data sources
- If `iam_workload_identity` is removed, also remove it from every `depends_on` — the
  `cert_manager` and `external_dns_*` blocks reference it

### 5.2 provider.tf
- If `gke` was excluded: repoint the `kubernetes` and `helm` providers at
  `data.google_container_cluster.existing` (see [Provider Configuration](#existing-cluster-data-sources))
- Keep `data "google_client_config" "default" {}` in every case — the token comes from there

### 5.3 variables.tf
- Remove orphaned variables (search `var.{name}` in all `.tf`, if not found → remove)
- Add new variables for existing resources (`var.existing_*`)

### 5.4 locals.tf
- Remove orphaned locals (search `local.{name}` in all `.tf`, if not found → remove)
- **Keep `local.cloud_provider = "gcp"`** — consumed by `istio`, `cert_manager` and `agent`
- **Keep `local.private_gateway_name`** — see [Pattern 5](gcp-troubleshooting.md#5-the-private-gateway-name-is-hardcoded-in-the-base-chart)

### 5.5 outputs.tf
- Remove outputs referencing deleted modules
- **Never remove `public_zone_name_servers`** unless `dns_public` itself was excluded. The
  DNS delegation in step 5 of `SKILL.md` reads it, and without delegation no certificate is
  ever issued

### 5.6 data blocks
- Remove orphaned `data` blocks in any `.tf` — except `google_client_config`

### 5.7 terraform.tfvars
- Add existing resource values: `existing_network_name = "my-vpc"`
- `dns_type = "external_dns"` (the only supported value on GCP)

### 5.8 existing-resources.properties
- Save as documentation: `network_name=my-vpc`

> `existing-resources.properties` is documentation. Real values go in `terraform.tfvars`.

## Step 6: Validate .tf files

> **Input**: Modified `.tf` files, `terraform.tfvars`
> **Output**: Validated files, ready for `tofu plan`/`tofu apply`

```bash
cd infrastructure/gcp
tofu fmt
tofu init -backend=false
tofu validate

# No shared variable may be defined in both files. Any output here is a bug:
# terraform.tfvars silently wins for THIS layer and the other two never see it.
comm -12 \
  <(grep -oE '^[a-z_]+' ../../common.tfvars | sort -u) \
  <(grep -oE '^[a-z_]+' terraform.tfvars | sort -u)
```

Use `tofu init -backend=false` to validate without needing backend credentials. See [tofu-modules-patterns.md](tofu-modules-patterns.md#module-reading-flow) for inspecting downloaded module variables.

- **If it passes** → Continue with step 5 of SKILL.md (DNS)
- **If it fails** → Read error, fix, repeat. Common causes:
  - Reference to deleted module without replacement
  - Undefined variable or missing value in tfvars
  - `depends_on` pointing to deleted module
  - Output referencing deleted module
  - Orphaned local (`cloud_provider` and `private_gateway_name` are **not** orphans)

## DNS delegation on GCP

The delegation flow itself is step 5 of `SKILL.md`. Two GCP-specific facts change how it plays
out:

1. **It is a cross-cloud delegation.** The child zone lives in Cloud DNS, but the parent
   (`nullapps.io` and its subzones) is a Route53 zone controlled by Nullplatform.
   `scripts/delegate-dns.sh` handles exactly this shape: with `--cloud gcp` it reads the
   nameservers from Cloud DNS with `gcloud` and writes the NS record into Route53 with
   `aws route53`. It needs an active `gcloud` session **and** AWS credentials for the parent
   account. If you do not have access to the parent account, `SKILL.md` step 5.5.a routes you
   to the manual request path (5.5.c) — that is now the only reason to take it on GCP.
2. **The NS records come from the module output.** After the first apply, read
   `public_zone_name_servers` (the `name_servers` output of `module.dns_public`) and send those
   four values to Nullplatform with the subzone name. That is why step 5.5 of `gcp.md` insists
   the output is never removed.

Until the delegation lands, cert-manager cannot solve the DNS-01 challenge and the certificate
sits in `PENDING_VALIDATION` until it times out (1h+). Do the delegation before the general
apply, not after.

## GCP Variables

In addition to the general variables documented in [variables.md](variables.md), GCP requires:

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `gcp_project_id` | Project every resource in this setup lives in | terraform.tfvars |
| `gcp_region` | Region for the regional resources (e.g., `us-east1`) | terraform.tfvars |
| `organization_slug` | Drives **every** resource name in this layer | common.tfvars |
| `domain_name` | Application domain. **`common.tfvars` only — never in `terraform.tfvars`** | common.tfvars |
| `private_domain_name` | Same value as `domain_name` (split horizon). **`common.tfvars` only** | common.tfvars |
| `subnet_cidr` | Primary node subnet CIDR | terraform.tfvars |
| `pods_cidr` | Secondary range for pods | terraform.tfvars |
| `services_cidr` | Secondary range for services | terraform.tfvars |
| `node_pools` | List of node pool objects | terraform.tfvars |
| `authorized_ip_ranges` | Control-plane allowlist. **`list(object({ cidr_block, display_name }))`**, not a list of CIDR strings | terraform.tfvars |
| `artifact_registry_repository_id` | Artifact Registry repository name | terraform.tfvars |
| `dns_type` | Always `"external_dns"` on GCP | terraform.tfvars |
| `agent_image_tag` | `"latest"` on GCP (AWS is the exception, it uses `"aws"`) | terraform.tfvars |
| `labels` | GCP labels — **lowercase only** | terraform.tfvars |

> ### The domain variables live in `common.tfvars` and nowhere else
>
> `domain_name` and `private_domain_name` are read by **all three layers**, and only
> `infrastructure/` gets `-var-file=terraform.tfvars` on top. So an override there wins for
> infrastructure and is invisible to the other two:
>
> ```
> common.tfvars              domain_name = "old.playground.nullapps.io"
> infrastructure/…tfvars     domain_name = "new.playground.nullapps.io"   ← wins, infra only
> ```
>
> Infrastructure creates the Cloud DNS zone for `new`, while `nullplatform/` and
> `nullplatform-bindings/` register the platform against `old`. Applications get hostnames in
> a domain that has no zone in this project, and **nothing resolves** — with three clean
> applies and no error anywhere. Observed on a real run.
>
> Set the domain in `common.tfvars`, and if `terraform.tfvars` already carries one, **delete
> it** rather than syncing the two. The check is in [step 6](#step-6-validate-tf-files).
>
> `private_domain_name` holds the **same value** as `domain_name` — see
> [split horizon](gcp-modules.md#split-horizon-private_domain_name--domain_name).

> `organization_slug` is the slug variable `/np-setup-orchestrator init` actually writes to
> `common.tfvars`. Do not invent `var.account` or `var.account_slug` — neither is generated,
> and referencing them produces an undefined-variable error at plan time. Note that
> `account_slug` **is** a legitimate *module input name* on `commons/cert_manager`; it is fed
> from `var.organization_slug`.

### Values that differ from AWS — get these right the first time

Every row here is a value a GCP run must set differently from the AWS reference. Each one was
hit on a real setup; the details are behind the links.

| Setting | GCP value | Why it differs |
|---|---|---|
| `module "base"` → `metrics_server_enabled` | **`false`**, as a literal in the HCL — not a tfvars variable | GKE ships metrics-server as a managed addon; EKS does not. `true` fails the `base` release at apply on an APIService ownership conflict — [details](gcp-modules.md#metrics_server_enabled-must-be-false-on-gke) |
| `private_domain_name` | **same value as `domain_name`** | Split horizon, like the AWS `dns` module. A separate `internal.<domain>` breaks DNS-01 for internal hostnames — [details](gcp-modules.md#split-horizon-private_domain_name--domain_name) |
| `external_dns.sources` | **`["crd"]`** | external-dns reads DNSEndpoint CRs, not the agent's HTTPRoutes — [details](gcp-modules.md#sources-must-be-crd-and-the-label-filter-goes-with-it) |
| `external_dns.txt_owner_id` | the cluster/org slug | Must be unique per cluster, never a generic literal |
| `dns_type` | `"external_dns"` | The only supported value on GCP; there is no `clouddns` |
| `agent_image_tag` | `"latest"` | AWS is the exception that uses `"aws"` |
| `authorized_ip_ranges` | `list(object(...))`, and `[]` means **open** | Same knob as EKS `endpoint_public_access_cidrs`, opposite default |
| `node_pools[*].machine_type` | **`e2-standard-2`** minimum | Shared-core types (`e2-medium`) leave only ~940m allocatable; GKE's own overhead alone exceeds it and the `base` release times out — [details](gcp-modules.md#gke-infrastructuregcpgke) |
| `node_pools[*]` | only the attributes the pinned module declares | Closed object type — `disk_type`, `auto_repair`, `auto_upgrade` do not exist and are a hard error |
| `node_pools[*]` node count | `total_min_count`/`total_max_count` where available, else `min_count` | `min_count` is **per zone** and the cluster is regional, so it is multiplied by 3; the `total_*` pair is cluster-wide |
| `labels` | lowercase only | GCP rejects uppercase at the resource, not at plan |
| `module.security.cluster_name` | `local.cluster_name`, plus `depends_on` | `module.gke.cluster_name` is unknown at plan time and aborts the plan |
| `module.base` | **no `nrn`** | The module does not declare it; only `agent` and `agent_api_key` take it |
| `domain_name` / `private_domain_name` | `common.tfvars` **only** | An override in `terraform.tfvars` desyncs the three layers silently |

### CIDR sizing

The three ranges must not overlap each other, and must not overlap anything the VPC is
later peered with. Pods is the range that runs out first: GKE reserves a **/24 per node**
by default (110 pods per node), so each doubling of the pods prefix doubles the node
ceiling — a `/14` holds 1024 `/24`s and therefore supports up to **1024 nodes**, a `/16`
supports 256.

A working starting point:

```hcl
subnet_cidr   = "10.20.0.0/20"
pods_cidr     = "10.32.0.0/14"
services_cidr = "10.36.0.0/20"
```

### Slug constraints

The slug is not a free-form label on GCP — it is interpolated into resource names that have
hard limits:

| Derived name | Constraint |
|---|---|
| `np-{slug}-cert-manager` (service account `account_id`) | **30 characters max** |
| `np-{slug}-external-dns` (service account `account_id`) | **30 characters max** |
| `{slug}` (GKE cluster name) | lowercase letters, digits, `-`; must start with a letter |
| `{slug}-vpc`, `-nodes`, `-pods`, `-services`, `-router`, `-nat` | valid GCP resource names |

`np-` + `-external-dns` consumes 16 characters, leaving **14** for the slug. Validate this
before the first apply — the failure arrives partway through, after the VPC and cluster
already exist.

## Provider Configuration

### GCP Provider

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google       = { source = "hashicorp/google",     version = "~> 5.0" }
    helm         = { source = "hashicorp/helm",       version = "~> 3.0" }
    kubernetes   = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    nullplatform = { source = "nullplatform/nullplatform", version = "~> 0.0.X" }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "nullplatform" {
  api_key = var.np_api_key
}
```

> **`google ~> 5.0` is load-bearing, not a default.** Several `infrastructure/gcp/*` modules
> pin `~> 5.0` themselves, so allowing `>= 6.0` makes `tofu init` fail on provider constraint
> resolution. Do not bump it without checking every GCP module's `versions.tf`.
>
> **Do not hardcode the `nullplatform` provider version.** Resolve the latest at generation
> time as [infrastructure-generation.md](infrastructure-generation.md) requires, and write
> `~> 0.0.X` with the value you obtained.

For generic providers (kubernetes, helm, nullplatform) see [tofu-modules-patterns.md](tofu-modules-patterns.md#generic-provider-versions).

### New cluster (created by tofu)

```hcl
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.host}"
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes = {
    host                   = "https://${module.gke.host}"
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
```

> Correct GKE outputs: `host`, `cluster_ca_certificate`, `cluster_name`.
> `module.gke.host` has **no scheme** — the `https://` prefix is required.
> Helm v3: see [tofu-modules-patterns.md](tofu-modules-patterns.md#helm-v3-syntax).

> **This is not the GKE equivalent of an `aws eks get-token` exec block.** AWS resolves a
> fresh token on every provider call; GCP resolves `data.google_client_config.default`
> **once, at plan time**, and it is short-lived. A very long apply can outlive its own
> token. See [Pattern 8](gcp-troubleshooting.md#8-the-access-token-is-resolved-at-plan-time).

> **It is the same knob as EKS's `endpoint_public_access_cidrs`** — do not present it as a
> GCP-only restriction. What differs is the default, and it differs in the dangerous
> direction: EKS *requires* at least one CIDR (a `validation` block rejects an empty list),
> while GKE treats an empty list as **no allowlist at all**, i.e. the public endpoint open to
> the internet. Verified in the upstream module: with `master_authorized_networks = []` no
> `master_authorized_networks_config` block is emitted and GKE applies its permissive default.
>
> So `authorized_ip_ranges = []` on GKE is equivalent to `["0.0.0.0/0"]` on EKS — which is
> what most AWS PoCs use. If the user's AWS setups "just work from anywhere", that is why, and
> matching it is a legitimate choice for a PoC: open means *reachable*, not *authenticated*.
> Say so instead of insisting on an IP, and note the cost of the allowlist — if their egress
> IP changes, every `kubernetes`/`helm` resource times out against a perfectly healthy cluster.

> **`authorized_ip_ranges` gates the machine running tofu.** The cluster runs private nodes
> with a **public control plane endpoint**. An empty list leaves that endpoint reachable
> from anywhere — acceptable for a PoC, not acceptable after it. Ask the user for the CIDRs
> to allow, and make sure the address running tofu is among them or every `kubernetes`/`helm`
> resource times out.

### Existing cluster (data sources)

```hcl
data "google_client_config" "default" {}

data "google_container_cluster" "existing" {
  name     = var.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.existing.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.existing.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes = {
    host                   = "https://${data.google_container_cluster.existing.endpoint}"
    cluster_ca_certificate = base64decode(data.google_container_cluster.existing.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
```

> `gke-gcloud-auth-plugin` must be installed for `kubectl` to work against the cluster
> afterwards. Tofu itself does not need it (it uses the access token directly), so a missing
> plugin surfaces only during post-apply validation.

## Next

- Writing the module blocks → [gcp-modules.md](gcp-modules.md)
- Before the first apply, and whenever something fails → [gcp-troubleshooting.md](gcp-troubleshooting.md)
