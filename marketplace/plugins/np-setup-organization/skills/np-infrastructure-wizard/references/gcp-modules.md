# GCP Module Reference

> Companion to [gcp.md](gcp.md). Read this when writing or editing `infrastructure/gcp/main.tf`.
> For the decision tree see [gcp.md](gcp.md); for failure modes see [gcp-troubleshooting.md](gcp-troubleshooting.md).

> **Provenance**: every contract below was read from `nullplatform/tofu-modules` at `v7.1.0`
> and cross-checked against a working GCP setup. **If you pinned a different `ref`**, re-read
> the module's `variables.tf` and `outputs.tf` from `.terraform/modules/` before trusting
> these lists — variable sets change between versions.

For source format and versioning see [tofu-modules-patterns.md](tofu-modules-patterns.md#module-source-git-ref). For `agent_api_key` see [tofu-modules-patterns.md](tofu-modules-patterns.md#agent-api-key-module).

All paths below are under `infrastructure/gcp/` in `nullplatform/tofu-modules`, except the
`commons/` ones and the local external-dns module.

## Contents

- [VPC](#vpc-infrastructuregcpvpc)
- [Cloud NAT](#cloud-nat-infrastructuregcpcloud-nat)
- [Cloud DNS](#cloud-dns-infrastructuregcpcloud-dns)
- [GKE](#gke-infrastructuregcpgke)
- [Security](#security-infrastructuregcpsecurity)
- [IAM](#iam-infrastructuregcpiam)
- [Artifact Registry](#artifact-registry-infrastructuregcpartifact-registry)
- [Istio](#istio-infrastructurecommonsistio)
- [Cert Manager](#cert-manager-infrastructurecommonscert_manager)
- [External DNS](#external-dns-infrastructurecommonsexternal_dns)
- [Prometheus](#prometheus-infrastructurecommonsprometheus)
- [Base](#base-gcp-defaults-nullplatformbase)
- [Agent](#agent-nullplatformagent)

## VPC (`infrastructure/gcp/vpc`)
- Inputs: `project_id`, `network_name`, `subnets`, `secondary_ranges`
- Outputs: `network_name`, `network_self_link`, `subnets_names`, `subnets_self_links`

```hcl
module "vpc" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/vpc?ref={version}"

  network_name = local.network_name
  project_id   = var.gcp_project_id

  subnets = [{
    subnet_name   = local.subnet_name
    subnet_ip     = var.subnet_cidr
    subnet_region = var.gcp_region
  }]

  # GKE takes its pod and service ranges from these secondary ranges rather than
  # from the primary subnet CIDR, so the three never overlap.
  secondary_ranges = {
    (local.subnet_name) = [
      { range_name = local.pods_range_name,     ip_cidr_range = var.pods_cidr },
      { range_name = local.services_range_name, ip_cidr_range = var.services_cidr },
    ]
  }
}
```

## Cloud NAT (`infrastructure/gcp/cloud-nat`)
- Inputs: `project_id`, `region`, `network_id`, `router_name`, `nat_name`
- Outputs: `router_name`, `nat_name`

```hcl
module "cloud_nat" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/cloud-nat?ref={version}"

  nat_name    = local.nat_name
  network_id  = module.vpc.network_self_link
  project_id  = var.gcp_project_id
  region      = var.gcp_region
  router_name = local.router_name
}
```

> `network_id` takes the **self link**, not the name.
> Cloud NAT is not optional on this topology — see [Pattern 3](gcp-troubleshooting.md#3-cloud-nat-is-mandatory-not-optional).

## Cloud DNS (`infrastructure/gcp/cloud-dns`)
- Inputs: `project_id`, `domain_name`, `zone_name`, `visibility`, `private_zone_networks`, `dnssec_enabled`, `tags`
- Outputs: `zone_name`, `zone_id`, `name_servers`

```hcl
module "dns_public" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/cloud-dns?ref={version}"

  domain_name = var.domain_name
  project_id  = var.gcp_project_id
  tags        = var.labels
}

module "dns_private" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/cloud-dns?ref={version}"

  domain_name           = var.private_domain_name
  private_zone_networks = [module.vpc.network_self_link]
  project_id            = var.gcp_project_id
  tags                  = var.labels
  visibility            = "private"

  # Split-horizon: same dns_name as the public zone, so the module's default
  # resource name (domain with dots replaced by dashes) would collide.
  zone_name = "${replace(var.private_domain_name, ".", "-")}-private"
}
```

> `name_servers` on the public zone is what the DNS delegation in step 5 of `SKILL.md`
> needs. Expose it as an output.
> `zone_name` is the **resource name**, not the domain — see [Pattern 7](gcp-troubleshooting.md#7-zone-resource-name-vs-dns-domain).

### Split horizon: `private_domain_name` == `domain_name`

**Default to one domain with two zones, the same way AWS does it.** `infrastructure/aws/dns`
creates both `aws_route53_zone.public_zone` and `.private_zone` with `name = var.domain_name` —
the *same* domain — and its `private_zone_name` output is literally equal to
`public_zone_name`. That is why AWS setups have no `private_domain_name` variable: there is no
second domain to name. Inside the VPC the name resolves to the internal gateway; outside, to
the public one.

GCP reaches the same shape: `google_dns_managed_zone` takes `dns_name` and `visibility`
independently, so two invocations with the same `domain_name` and different `visibility` give
split horizon. The only catch is the **resource** name, which defaults to
`replace(domain_name, ".", "-")` and therefore collides — hence the explicit `zone_name` above.

**Why not a separate `internal.<domain>` private zone.** It looks tidier and it breaks
certificate issuance for internal hostnames. cert-manager solves DNS-01 by writing a TXT
record that **Let's Encrypt must read from the internet**; with project-scoped
`roles/dns.admin` it picks the managed zone that best matches the name. For
`_acme-challenge.app.internal.<domain>` the best match is the *private* zone, so the challenge
lands somewhere the public internet cannot see and never validates. A publicly resolvable
*parent* does not help — the challenge record itself has to be public. Split horizon avoids it:
the TXT goes in the public zone, the A record lives in the private one.

> Confidence: the AWS module using one domain for both zones is **verified** at `v7.1.0`. The
> DNS-01 zone-selection failure is **reasoned**, not observed on an apply. Either way, parity
> with the production AWS setup is the safer default.

It also makes the external-dns wiring honest: both instances filter the same domain, and the
separation comes from `--google-zone-visibility` plus
`--label-filter=dns/zone-type=…` — not from a domain filter that could never have done the job.

## GKE (`infrastructure/gcp/gke`)
- Inputs: `project_id`, `cluster_name`, `location`, `vpc_name`, `vpc_subnet_name`, `ip_range_pods`, `ip_range_services`, `node_pools`, `authorized_ip_ranges`, `master_ipv4_cidr_block`, `deletion_protection_enabled`, `tags`
- Outputs: `cluster_name`, `host`, `cluster_ca_certificate`

```hcl
module "gke" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/gke?ref={version}"

  authorized_ip_ranges = var.authorized_ip_ranges
  cluster_name         = local.cluster_name
  ip_range_pods        = local.pods_range_name
  ip_range_services    = local.services_range_name
  location             = var.gcp_region
  node_pools           = var.node_pools
  project_id           = var.gcp_project_id
  tags                 = var.labels
  vpc_name             = module.vpc.network_name
  vpc_subnet_name      = local.subnet_name
}
```

> `ip_range_pods` / `ip_range_services` take the **secondary range names**, not CIDRs.
> `location` set to a region (not a zone) makes the cluster regional.
>
> **`authorized_ip_ranges` is a list of objects, not a list of CIDR strings**:
> ```hcl
> authorized_ip_ranges = [
>   { cidr_block = "203.0.113.10/32", display_name = "office" },
> ]
> ```
> Azure's AKS equivalent is a plain `set(string)` — the two clouds differ here, so do not
> copy the value across.
> **`node_pools` counts are PER ZONE, and `location = region` makes the cluster regional.**
> The module wraps `terraform-google-modules/kubernetes-engine//modules/private-cluster` and
> passes `region = var.location`, so `min_count`/`max_count` are multiplied by the number of
> zones in the region — three, in most. `min_count = 2` in `us-east1` is **six** nodes, not
> two, and `max_count = 4` is twelve.
>
> | tfvars | Region with 3 zones |
> |---|---|
> | `min_count = 2`, `e2-standard-4` | 6 nodes — 24 vCPU / 96 GB / 600 GB disk |
> | `min_count = 1`, `e2-standard-4` | 3 nodes — 12 vCPU / 48 GB / 300 GB disk |
>
> **`node_pools` is a CLOSED object type — extra attributes are a hard error.** Terraform
> rejects any key the object does not declare:
>
> ```
> Invalid value for input variable: element 0: attribute "disk_type" is not expected here
> ```
>
> `disk_type`, `auto_repair`, `auto_upgrade`, `image_type`, `labels` and `taints` all look
> plausible and **none of them exist**. Read the pinned module's `variables.tf` and use only
> what it declares — this is the generic "never infer from the name" rule, and `node_pools` is
> where it bites most often because the GKE ecosystem is full of examples using a richer shape.
>
> **Read the pinned module's `variables.tf` for the exact set** — it has grown over time, so
> an older pin may not have everything below:
>
> `name`, `machine_type`, `disk_size_gb`, `autoscaling`, `min_count`, `max_count` (**per
> zone**), `node_count`, `total_min_count`, `total_max_count` (**cluster-wide**), `spot`,
> `preemptible`.
>
> **When the user asks for "N nodes total", use `total_min_count` / `total_max_count`** if the
> pinned ref has them. That is the direct expression of a cluster-wide bound and it sidesteps
> the per-zone multiplication entirely — it is also what makes GKE behave like an EKS managed
> node group, which spreads a desired count across AZs rather than multiplying by them. The
> module validates that the two are set together. On refs without them, fall back to
> `min_count` and state the multiplication out loud.

> **Never use a shared-core machine type (`e2-micro`, `e2-small`, `e2-medium`).** They do not
> merely run tight — the setup cannot come up at all. Measured on a real 3-node `e2-medium`
> cluster:
>
> ```
> allocatable per node   940m      ← out of 2 nominal vCPU; e2-medium is shared-core
> requested per node     854-903m  → 90-96%, with zero applications deployed
> free cluster-wide      ~200m
> ```
>
> GKE's own system pods take **~1500m of the 2820m allocatable (54%)** — that overhead is
> roughly fixed per node, so on small nodes it eats most of the machine. Istio plus the
> gateways add another 1000m. The result is that `nullplatform-log-controller`, a DaemonSet
> requesting 100m, cannot schedule, and the `base` release fails after its full ten-minute
> `wait` with `context deadline exceeded`:
>
> ```
> 0/3 nodes are available: 1 Insufficient cpu, 2 node(s) didn't satisfy plugin(s) [NodeAffinity]
> ```
>
> (The NodeAffinity entries are the other nodes — a DaemonSet pod is pinned to one node, so
> "insufficient cpu on 1 node" is the whole story.)
>
> **`e2-medium` is not the GCP equivalent of an AWS `t3.medium`.** A `t3.medium` leaves ~1930m
> allocatable on EKS; `e2-medium` leaves 940m — less than half. If the user asks for parity
> with their AWS PoC shape, the honest mapping is **`e2-standard-2`** (2 *dedicated* vCPU).
>
> | Machine type | Allocatable CPU/node | Verdict |
> |---|---|---|
> | `e2-medium` | ~940m | **Does not work** — platform alone exceeds it |
> | `e2-standard-2` | ~1930m | Minimum that works; fine for a PoC |
> | `e2-standard-4` | ~3920m | Comfortable with real applications |
>
> Prefer shrinking `min_count` over shrinking the machine type: CPU pressure here is per-node
> and fixed, so more small nodes does not help — every extra node brings its own system
> overhead and another DaemonSet pod. State the resulting node count to the user before they
> apply; the per-zone multiplication is the most common cost surprise on a GKE PoC.
>
> Set `deletion_protection_enabled = false` on a PoC or `tofu destroy` fails on the cluster.

## Security (`infrastructure/gcp/security`)
- Inputs: `cluster_name`, `gcp_project_id`, `gcp_region`, `gateways_enabled`, `gateway_internal_enabled`, `gcp_network_name`, `network_cidr`
- Outputs: `public_gateway_firewall_name`, `private_gateway_firewall_name`

```hcl
module "security" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/security?ref={version}"

  # local.cluster_name, NOT module.gke.cluster_name — see the box below.
  cluster_name             = local.cluster_name
  gateway_internal_enabled = var.nullplatform_base.gateway_internal_enabled
  gcp_project_id           = var.gcp_project_id
  gcp_region               = var.gcp_region

  # The dependency the removed reference used to carry.
  depends_on = [module.gke]
}
```

> **`cluster_name` must be a value known at plan time.** The module gates two data sources on
> `count = var.cluster_name != "" ? 1 : 0`:
>
> ```hcl
> data "google_container_cluster"  "this" { count = var.cluster_name != "" ? 1 : 0  ... }
> data "google_compute_subnetwork" "this" { count = var.cluster_name != "" ? 1 : 0  ... }
> ```
>
> Fed from `module.gke.cluster_name`, on a greenfield run that string does not exist yet, so
> the count is unknown and **`tofu plan` aborts**:
>
> ```
> Error: Invalid count argument
>   on .terraform/modules/security/infrastructure/gcp/security/main.tf line 18,
>   in data "google_container_cluster" "this":
>   The "count" value depends on resource attributes that cannot be determined until apply
> ```
>
> `local.cluster_name` is the same string — it is what `module.gke` was given in the first
> place — and it is known up front. Passing it drops the implicit dependency, so add
> `depends_on = [module.gke]`: the data sources still have to read a cluster that exists, and
> `depends_on` on a module defers the data source reads to apply time. Observed on a real
> plan; the fix takes it to `Plan: 49 to add, 0 to change, 0 to destroy`.
>
> Same class of bug as Azure's AcrPull `for_each` — a `count`/`for_each` keyed on something
> the same apply has not produced yet. When wiring any module, check whether the value feeds a
> meta-argument before passing an output into it.

> This module **creates** the firewall rules; `base` only references them **by name**. That
> fixes the order `gke → security → base` — see [Pattern 4](gcp-troubleshooting.md#4-order-is-gke--security--base).
> Keep `gateway_internal_enabled` in sync with the same flag on `base`, or `base` references
> a rule that was never created.

## IAM (`infrastructure/gcp/iam`)
- Inputs: `project_id`, `service_accounts`, `workload_identity_bindings`
- Output: `service_accounts` (map of name → email)

Invoked **twice** — see [Pattern 2](gcp-troubleshooting.md#2-iam-is-invoked-twice-on-purpose):

```hcl
module "iam" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/iam?ref={version}"

  project_id = var.gcp_project_id

  service_accounts = [
    {
      name         = local.cert_manager_sa_name
      display_name = "cert-manager DNS-01 solver for ${var.organization_slug}"
      roles        = ["roles/dns.admin"]
    },
    {
      name         = local.external_dns_sa_name
      display_name = "external-dns record writer for ${var.organization_slug}"
      roles        = ["roles/dns.admin"]
    },
  ]
}

module "iam_workload_identity" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/iam?ref={version}"

  project_id = var.gcp_project_id

  workload_identity_bindings = [
    {
      service_account_email = module.iam.service_accounts[local.cert_manager_sa_name]
      namespace             = local.cert_manager_namespace
      ksa_name              = local.cert_manager_ksa_name
    },
    {
      service_account_email = module.iam.service_accounts[local.external_dns_sa_name]
      namespace             = local.external_dns_namespace
      ksa_name              = local.external_dns_public_ksa
    },
    {
      service_account_email = module.iam.service_accounts[local.external_dns_sa_name]
      namespace             = local.external_dns_namespace
      ksa_name              = local.external_dns_private_ksa
    },
  ]
}
```

> `roles/dns.admin` is **project-scoped** here. AWS narrows the equivalent policy to
> specific hosted zone IDs; the GCP module does not expose a per-zone condition. If the
> project holds DNS zones outside this setup, note the wider blast radius.

## Artifact Registry (`infrastructure/gcp/artifact-registry`)
- Inputs: `project_id`, `location`, `repository_id`, `format`, `tags`, `workload_identity_bindings`
- Outputs: `repository_id`, `repository_url`, `service_account_email`

```hcl
module "artifact_registry" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/gcp/artifact-registry?ref={version}"

  location      = var.gcp_region
  project_id    = var.gcp_project_id
  repository_id = var.artifact_registry_repository_id
  tags          = var.labels
}
```

> `repository_url` is the image prefix the build pipeline pushes to, and
> `service_account_email` (holding `artifactregistry.writer`) is what authenticates the
> push. Both are consumed by the bindings layer — expose them as outputs.

## Istio (`infrastructure/commons/istio`)

```hcl
module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/istio?ref={version}"

  cloud_provider  = local.cloud_provider   # "gcp"
  istiod_replicas = var.istio.istiod_replicas
  service_type    = var.istio.service_type

  depends_on = [module.gke]
}
```

> `cloud_provider` is validated against `["", "aws", "oci", "azure", "gcp"]`.
> `istiod_replicas = 1` halves the footprint on a small cluster at the cost of a single
> point of failure for the mesh control plane.

## Cert Manager (`infrastructure/commons/cert_manager`)

```hcl
module "cert_manager" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/cert_manager?ref={version}"

  account_slug   = var.organization_slug
  cloud_provider = local.cloud_provider   # "gcp"
  gcp_sa_email   = module.iam.service_accounts[local.cert_manager_sa_name]
  project_id     = var.gcp_project_id

  # The public DOMAIN, not the Cloud DNS resource name.
  hosted_zone_name    = var.domain_name
  private_domain_name = var.private_domain_name

  depends_on = [module.gke, module.iam_workload_identity]
}
```

> `account_slug` is the **module's input name**; the value comes from `var.organization_slug`,
> the slug the orchestrator actually writes to `common.tfvars`.
> `cloud_provider` is validated against `["gcp", "azure", "cloudflare", "aws", "oci"]`.
> On GCP the auth is Workload Identity via `gcp_sa_email` — there is no GCP equivalent of
> the `aws_sa_arn` role ARN or the Azure `azure_client_id` / federated credential.
> `depends_on` **must** include `module.iam_workload_identity`: without the binding in
> place, the pod starts, fails to impersonate the SA, and DNS-01 never solves.
>
> **The KSA to bind is `cert-manager` in namespace `cert-manager`.** Verified by rendering
> chart `1.18.2` (the module default): the controller Deployment `cert-manager` runs under
> ServiceAccount `cert-manager`. The chart also creates `cert-manager-cainjector`,
> `cert-manager-webhook` and `cert-manager-startupapicheck` — **do not bind those**; only the
> controller solves DNS-01. Binding the wrong one leaves the controller unable to impersonate
> the GSA and DNS-01 fails with an impersonation error while everything looks installed.

## External DNS (`infrastructure/commons/external_dns`)

**GCP uses the shared module, same as AWS.** Cloud DNS support lives in
`infrastructure/commons/external_dns` — `dns_provider_name = "google"`. Do **not** generate a
local `modules/external_dns_google/`; older GCP setups carried one because the shared module
had no `google` branch, and that is no longer true.

> If the pinned `ref` reports that `google` is not a valid `dns_provider_name`, the ref is too
> old. Pin the latest release — never vendor a local copy of the module.

```hcl
module "external_dns_public" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"

  dns_provider_name = "google"
  domain_filters    = var.domain_name
  type              = "public"
  zone_type         = "public"

  gcp_project_id            = var.gcp_project_id
  gcp_service_account_email = module.iam.service_accounts[local.external_dns_sa_name]
  gcp_service_account_name  = local.external_dns_public_ksa

  external_dns_version = var.external_dns.version
  policy               = var.external_dns.policy
  sources              = var.external_dns.sources
  txt_owner_id         = var.external_dns.txt_owner_id

  depends_on = [module.gke, module.iam_workload_identity]
}

# Both instances share one namespace, so only the public one creates it and the
# private one waits for it. Letting both create it is a race that fails the apply
# on whichever loses.
module "external_dns_private" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"

  create_namespace  = false
  dns_provider_name = "google"
  domain_filters    = var.private_domain_name
  type              = "private"
  zone_type         = "private"

  gcp_project_id            = var.gcp_project_id
  gcp_service_account_email = module.iam.service_accounts[local.external_dns_sa_name]
  gcp_service_account_name  = local.external_dns_private_ksa

  external_dns_version = var.external_dns.version
  policy               = var.external_dns.policy
  sources              = var.external_dns.sources
  txt_owner_id         = var.external_dns.txt_owner_id

  depends_on = [module.gke, module.iam_workload_identity, module.external_dns_public]
}
```

> **`zone_type` becomes `--google-zone-visibility`** — which *zones* external-dns writes to.
> Set it to `"public"` / `"private"` to match the instance; a `validation` rejects anything
> else on `google`.
>
> **Known gap: it does not yet derive `--label-filter`.** The `google` branch does not pass a
> label filter, though `route53_config` does and the module already computes
> `effective_label_filter`. That matters with **split horizon**, where
> both instances share the same `domain_filters` and the label is the only thing separating
> them: each reads every DNSEndpoint and publishes it into its own zone, so **a private
> hostname becomes a public record pointing at an internal address**.
>
> There is no caller-side workaround — the `google` branch ignores `label_filter` entirely, so
> passing it changes nothing. Until the module ships it, either accept that exposure on a
> throwaway PoC or fix it upstream. Tell the user which they are choosing rather than leaving
> it implicit.
>
> `type` controls the Helm release name (`external-dns-{type}`) — keep it aligned with
> `zone_type`.
>
> `gcp_service_account_name` is the **KSA** and must match the `ksa_name` given to
> `iam_workload_identity`, per instance — two different KSAs bound to one GSA.
> `gcp_service_account_email` is the **GSA**, the same for both.
>
> **`txt_owner_id` must be unique per cluster.** It is the owner tag external-dns writes into
> its TXT registry records to know which entries are its own. Generate it from the cluster or
> organization slug (`txt_owner_id = "acme-prod"`), never a generic literal like
> `"external_dns"`: two clusters sharing a zone with the same owner id each believe they own
> the other's records and fight over them, deleting each other's hostnames. Both instances
> share one value on purpose — they are the same owner, separated by the label filter.
>
> `domain_filters` is singular-valued despite the plural name, and with split horizon both
> instances get the **same** domain. The separation comes from `zone_type`, not from here.

### `sources` must be `["crd"]`, and the label filter goes with it

**Verified** against `nullplatform/scopes` (`main`) and `tofu-modules` `v7.1.0`. The chain is:

```
scope's manage_route  ->  DNSEndpoint CR       ->  external-dns   ->  Cloud DNS record
(networking/dns/          (dns-endpoint.yaml.tpl,   (sources=["crd"],
 external_dns)             labeled dns/zone-type)    --label-filter)
```

- `sources = ["crd"]` — the module default, and correct. external-dns watches **DNSEndpoint
  custom resources**, not `HTTPRoute` objects.
- `["gateway-httproute"]` reads like the obvious choice given `dns_type = "external_dns"` and
  the agent's HTTPRoute templates, but it is the wrong end of the chain: the HTTPRoutes handle
  *routing*, the DNSEndpoints handle *DNS*. Setting it produces the silent no-records failure.
- The matching `--label-filter` comes from `zone_type` and is what keeps the public and private
  instances apart. Do not override `label_filter` unless you also handle that separation.

**Do not add an `rbac.additionalPermissions` block.** Verified by rendering the upstream chart
at `1.19.0`: with `sources = ["crd"]` the chart already emits a second ClusterRole granting
`get/watch/list` on `externaldns.k8s.io/dnsendpoints` plus `*` on `dnsendpoints/status`. The
module's AWS branch adds the **write** verbs on top of that; nothing explains why, and reading
CRs does not need them.

## Prometheus (`infrastructure/commons/prometheus`)

```hcl
module "prometheus" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/prometheus?ref={version}"

  depends_on = [module.gke]
}
```

## Base (GCP defaults) (`nullplatform/base`)

```hcl
module "base" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref={version}"

  np_api_key   = module.agent_api_key.api_key
  k8s_provider = "gke"

  gateway_api_crds_install = var.nullplatform_base.gateway_api_crds_install
  gateway_api_enabled      = var.nullplatform_base.gateway_api_enabled

  # MUST be false on GKE — see the box below. Literal, never a tfvars variable.
  metrics_server_enabled = false

  # Names of the firewall rules created by module.security, referenced by the
  # chart when it annotates the gateway Services.
  gateway_public_gcp_firewall_name  = module.security.public_gateway_firewall_name
  gateway_private_gcp_firewall_name = module.security.private_gateway_firewall_name

  depends_on = [module.gke, module.istio]
}
```

### `metrics_server_enabled` MUST be `false` on GKE

**GKE ships metrics-server as a managed addon; EKS does not.** Same flag, opposite
correct value — `aws.md` documents `metrics_server_enabled = true` because on EKS that
flag is what *provides* the Metrics API. On GKE it only tries to install a second one.

Write it as a **literal `false`** in the `module "base"` block, not as a tfvars variable.
The value is a property of GKE, so there is nothing for an operator to decide and no reason
to leave a knob that can be set wrong — see
[generation rule 35](infrastructure-generation.md#35-metrics_server_enabled-depends-on-cloud-provider).

Verified on a live GKE cluster:

```
kube-system/metrics-server-v1.35.1
  image:  gke-release/metrics-server:v0.8.0-gke.23
  labels: addonmanager.kubernetes.io/mode: Reconcile     ← GKE restores it if deleted
```

The `APIService v1beta1.metrics.k8s.io` it registers carries **no Helm ownership
metadata**, because GKE created it — so Helm refuses to adopt it and the release fails:

```
Error: installation failed
  with module.base.helm_release.base
  Unable to continue with install: APIService "v1beta1.metrics.k8s.io" exists and cannot
  be imported into the current release: invalid ownership metadata; label validation
  error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"
```

It surfaces **at apply**, not at plan — and late, after the cluster, Istio, cert-manager
and external-dns are already up.

**Nothing is lost by disabling it.** HPA and `kubectl top` are served by GKE's own
metrics-server; `kubectl top nodes` and `AVAILABLE: True` on the APIService were both
confirmed with the flag off. Prometheus is unaffected either way — it scrapes `/metrics`
endpoints directly and never queries the Metrics API.

> `k8s_provider` is validated against `["eks", "gke", "aks", "oke", "aro"]` — use `"gke"`.
>
> **`base` takes no `nrn`.** The variable does not exist on the module at `v7.1.0` (nor on
> `main`); the chart derives its scope from the API key. Passing it is a hard
> `Unsupported argument` at plan time. This is a cloud-independent trait of the module, not
> a GCP one — it is called out here because the surrounding block is the thing people copy.

> **The AWS gateway-naming rule does not apply to GCP.** `gateway_public_aws_name` /
> `gateway_internal_aws_name` (see the MANDATORY note in
> [resources-by-cloud.md](resources-by-cloud.md#base-module--gateway-nlb-naming--mandatory))
> are AWS-only variables and there are no GCP equivalents. On GCP the coupling is the
> **firewall rule names** above, passed from `module.security`. Passing the `*_aws_name`
> variables on a GKE setup is a no-op that reads like configuration.

## Agent (`nullplatform/agent`)

```hcl
module "agent" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref={version}"

  agent_repos_scope = var.agent_repos_scope
  api_key           = module.agent_api_key.api_key
  cloud_provider    = local.cloud_provider   # "gcp"
  cluster_name      = module.gke.cluster_name
  image_tag         = var.agent_image_tag
  nrn               = var.nrn
  tags_selectors    = var.tags_selectors

  # With dns_type = external_dns the agent writes HTTPRoute objects and never
  # touches a DNS API itself; external-dns owns the records.
  dns_type             = var.dns_type          # "external_dns"
  domain               = var.domain_name
  private_domain       = var.private_domain_name
  private_gateway_name = local.private_gateway_name

  # Without these three the agent falls back to plain Ingress templates.
  blue_green_ingress_path = var.agent_blue_green_ingress_path
  initial_ingress_path    = var.agent_initial_ingress_path
  service_template        = var.agent_service_template

  depends_on = [module.base]
}
```

> `cloud_provider` is validated against `["aws", "gcp", "azure", "oci"]`.
> Unlike `base`, the agent **does** take `nrn`, and it is required (no default).
> `aws_iam_role_arn` and the `azure_*` variables do not apply on GCP — the agent
> authenticates to Cloud DNS through nothing at all, because with
> `dns_type = "external_dns"` it does not talk to a DNS API.
> Extra scope/service repos still go in `agent_repos_extra`; see the catalog referenced
> from `SKILL.md`.
