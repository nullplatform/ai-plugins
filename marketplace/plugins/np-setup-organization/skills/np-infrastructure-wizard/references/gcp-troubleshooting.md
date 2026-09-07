# GCP Troubleshooting and Critical Patterns

> Companion to [gcp.md](gcp.md). Read this **before a greenfield apply** and whenever
> something fails. For the decision tree see [gcp.md](gcp.md); for module contracts see
> [gcp-modules.md](gcp-modules.md).

> These patterns document failure modes observed on a real GCP apply against
> `nullplatform/tofu-modules` `v7.1.0`. Several of them fail **silently** — the apply
> succeeds and the platform is quietly broken — which is why they are worth reading up
> front rather than after the fact.

## Critical GCP Patterns

### 1. external-dns is not optional on GCP

Use the shared `infrastructure/commons/external_dns` with `dns_provider_name = "google"` —
the same module AWS uses. Wiring in
[gcp-modules.md](gcp-modules.md#external-dns-infrastructurecommonsexternal_dns).

> **Do not generate a local `modules/external_dns_google/`.** Older GCP setups carried one
> because the shared module's `dns_provider_name` validation had no `google` entry and its
> `provider_configs` map had no `google_config`. Cloud DNS support has since been added. If a
> pinned `ref` still rejects `google`, it is too old — **pin the latest release**. A local copy
> drifts from upstream and has to be reconciled later.

> **Do not turn the question into a menu.** Observed failure mode: a wizard run finds
> external-dns missing, offers the user "document the gap / fix it upstream / switch to
> Cloudflare", the user picks the first, and the run reports success on a setup where no
> hostname will ever resolve. There is one answer — wire the module.

This matters more than it looks, because external-dns owns one half of a mechanism the agent
deliberately gave up. With `dns_type = "external_dns"` the agent never calls a DNS API:

```
agent deploys  ->  HTTPRoute                                  (routing inside the mesh)
               ->  DNSEndpoint CR  ->  external-dns  ->  A/CNAME in Cloud DNS

cert-manager   ------------------------------------->  TXT in Cloud DNS  (DNS-01)
```

**The two are parallel consumers of the zone, not a chain.** cert-manager solves DNS-01 by
writing its own `_acme-challenge` TXT records through its own service account (`gcp_sa_email`
+ `roles/dns.admin`); it does not go through external-dns. So a broken external-dns leaves you
with a **valid certificate on a hostname that does not resolve**. What both depend on is the
zone existing and being delegated.

Without external-dns **the deploy reports success and the hostname never resolves**: cluster
healthy, gateway holding a public IP, HTTPRoute in place, scope registered in nullplatform —
and no A record. `dig` returns NXDOMAIN and no error surfaces anywhere in the apply.

> **The agent's HTTPRoutes are not what external-dns reads.** The HTTPRoute templates handle
> routing; DNS comes from a separate `DNSEndpoint` CR the scope creates. So `sources` must be
> `["crd"]`, and the `--label-filter` that goes with it is what keeps the public and private
> instances apart. Both details in
> [gcp-modules.md](gcp-modules.md#sources-must-be-crd-and-the-label-filter-goes-with-it).

> **Follow-up, not a blocker**: a `google` branch upstream in the shared module. Once it
> ships, both call sites move to the shared module and the local one is deleted; the deltas to
> reconcile are listed in [gcp-modules.md](gcp-modules.md#external-dns-infrastructurecommonsexternal_dns).
> Until then the local module is the supported path — and a GCP setup that "uses the commons
> external_dns module" is misconfigured by construction.

### 2. `iam` is invoked twice on purpose

The Workload Identity bindings consume the **emails of the service accounts created in the
same module**. Asking one invocation for both the accounts and their bindings means writing
`module.iam.service_accounts[...]` inside `module.iam`'s own arguments — a self-reference
that Terraform rejects as a cycle between the module's input and its own output.

Splitting into `module.iam` (accounts) and `module.iam_workload_identity` (bindings) breaks
the cycle by making the second consume the first's output.

> **What this is not:** it is not an `Invalid for_each argument`. The bindings' `for_each` key
> is `"${wi.namespace}-${wi.ksa_name}"`, which is known at plan time regardless of whether the
> SA emails are; only the *values* would be unknown, and Terraform tolerates that. If you do
> see `Invalid for_each argument` on GCP, look elsewhere.
>
> AWS does not hit the cycle at all, because IRSA resolves through the cluster's OIDC provider
> ARN, which is an output of `eks`, not of the IAM module itself.

Consequence for step 5 of [gcp.md](gcp.md#51-maintf): if you remove one, remove both, and strip
`module.iam_workload_identity` from every `depends_on`.

### 3. Cloud NAT is mandatory, not optional

The cluster runs **private nodes**, which have no external IP. Without Cloud NAT they
cannot reach the container registry or the nullplatform control plane.

The symptom is **every pod stuck in `ImagePullBackOff` on an otherwise healthy cluster** —
nodes Ready, control plane fine, no networking error anywhere. Do not offer `cloud_nat` as
a component the user can decline unless they confirm an existing NAT or Private Google
Access path on the same subnet.

### 4. Order is `gke → security → base`

`module.security` **creates** the gateway firewall rules. `module.base` only references
them **by name** (`gateway_public_gcp_firewall_name`, `gateway_private_gcp_firewall_name`).

Referencing by name rather than by ID means Terraform cannot infer the dependency — there
is no resource reference to trace. `base` will happily apply against a firewall rule that
does not exist, and the gateway Services get annotations pointing at nothing. Keep
`depends_on = [module.gke, module.istio]` on `base` and let the `module.security.*`
references carry the rest.

**And `security` itself must not take `module.gke.cluster_name`.** It gates two data sources
on `count = var.cluster_name != "" ? 1 : 0`, so an unknown-at-plan-time name aborts the plan
with `Invalid count argument` before anything is created. Pass `local.cluster_name` — the same
string, known up front — and restore the ordering with `depends_on = [module.gke]`. Details
and the exact error in
[gcp-modules.md](gcp-modules.md#security-infrastructuregcpsecurity).

> So the chain is held together by two different mechanisms, and neither is a plain reference:
> `gke → security` by `depends_on` (because the name has to be known early), and
> `security → base` by name-valued outputs (because `base` references rules by name). Deleting
> either `depends_on` looks harmless and breaks a different thing.

### 5. The private gateway name is hardcoded in the base chart

`gateway.internal.name = "gateway-private"` is fixed inside the nullplatform base chart and
is **not exposed as a module variable**. The agent has to be told the same name via
`private_gateway_name`, or blue/green traffic shifting on the private domain has nothing to
attach to.

Keep it as a local so the coupling is visible:

```hcl
locals {
  private_gateway_name = "gateway-private"
}
```

Do not delete it as an orphan in step 5.4 of [gcp.md](gcp.md#54-localstf).

### 6. Two external-dns instances, one namespace

Both instances land in the same namespace. Only the public one creates it; the private one
sets `create_namespace = false` and takes `depends_on = [module.external_dns_public]`.

Letting both create it is a **race that fails the apply on whichever loses**, and it fails
intermittently, which makes it read like a transient error.

Their KSAs are different (`external-dns-public`, `external-dns-private`) and both are bound
to the same GSA — that is why `iam_workload_identity` has three bindings for two service
accounts.

### 7. Zone resource name vs DNS domain

Cloud DNS distinguishes the **managed zone resource name** from the **DNS domain**, and the
modules consume different ones:

| Consumer | Takes | Example |
|---|---|---|
| `cert_manager.hosted_zone_name` | the **domain** | `acme.nullapps.io` |
| `external_dns_*.domain_filter` | the **domain** | `acme.nullapps.io` |
| `data.google_dns_managed_zone.name` | the **resource name** | `acme-nullapps-io` |
| `module.dns_public.zone_name` output | the **resource name** | `acme-nullapps-io` |

Passing the resource name where a domain is expected produces a cert-manager solver that
matches nothing — certificates sit in `PENDING_VALIDATION` for an hour, then time out,
while the deploy reports success.

### 8. The access token is resolved at plan time

`data.google_client_config.default.access_token` is read once, at plan time, and is
short-lived. A long apply — a first greenfield run creating a cluster from scratch — can
outlive its own token, and the `kubernetes`/`helm` resources late in the graph fail with
authentication errors on a cluster that is perfectly healthy.

If this happens, re-run the apply. State is intact; the second run has a fresh token and a
much shorter graph left to walk. This is a real difference from the AWS `exec` block, which
mints a token per call.

### 9. GCP rejects uppercase in label values

`var.labels` feeds GCP labels, which accept only lowercase letters, digits, `-` and `_`.
An uppercase character fails the apply at the resource, not at plan time. Normalize before
passing:

```hcl
labels = {
  managed-by = "opentofu"
  setup      = "nullplatform"
}
```

### 10. Agent HTTPRoute Templates (Istio schema)

GCP always uses Istio with Gateway API, so the agent **always** needs the three template
variables. See [Agent HTTPRoute Templates in resources-by-cloud.md](resources-by-cloud.md#agent-httproute-templates-istio-schema--mandatory)
for the mandatory values — they must not be left empty, omitted, or as placeholders.

Unlike AWS, there is no schema on GCP where these are optional.

### 11. GCS Backend

```hcl
terraform {
  backend "gcs" {
    bucket = "my-tfstate-bucket"
    prefix = "infrastructure/gcp"
  }
}
```

The bucket holding the state cannot be managed by the Terraform that stores its state in
it, so it is created once, by hand:

```bash
gcloud storage buckets create gs://<state-bucket-name> \
  --project=<gcp-project-id> --location=<gcp-region> --uniform-bucket-level-access
gcloud storage buckets update gs://<state-bucket-name> --versioning
```

> There is no `profile` equivalent as in the S3 backend — GCS uses the ambient
> Application Default Credentials. Confirm the active identity (`gcloud config list account`)
> and the active project (`gcloud config get-value project`) match the intended target
> before `tofu init`.

## Troubleshooting

| Symptom | Probable cause | Fix |
|---|---|---|
| `403 ... has not been used in project ... or it is disabled` | A project API is not enabled | [gcp.md Step 0](gcp.md#step-0-enable-the-gcp-project-apis) — enable the seven APIs |
| Every pod in `ImagePullBackOff`, cluster otherwise healthy | No Cloud NAT for the private nodes | [Pattern 3](#3-cloud-nat-is-mandatory-not-optional) — add `cloud_nat` |
| Deploy succeeds, hostname never resolves | external-dns not wired at all | [Pattern 1](#1-external-dns-is-not-optional-on-gcp) — two `commons/external_dns` blocks with `dns_provider_name = "google"` |
| `main.tf` has `dns_type = "external_dns"` and no external-dns module | The setup was generated with the gap "documented" instead of filled | [Pattern 1](#1-external-dns-is-not-optional-on-gcp) — generate the local module before calling the setup done |
| `delegate-dns.sh` finds no parent zone | The parent is a Route53 zone owned by Nullplatform; your AWS credentials do not reach it | [gcp.md — DNS delegation](gcp.md#dns-delegation-on-gcp) — request it manually (`SKILL.md` 5.5.c) |
| `delegate-dns.sh` finds no child managed zone | Wrong GCP project, or the step 5.3 apply did not create the zone | Check `gcloud config get-value project` or pass `--gcp-project`; re-run with `--dry-run` |
| external-dns pod running and healthy, zero records written | `sources` set to `gateway-httproute` instead of `crd` | [gcp-modules.md — `sources`](gcp-modules.md#sources-must-be-crd-and-the-label-filter-goes-with-it) |
| Private hostnames appear in the **public** zone | Missing `--label-filter=dns/zone-type=…`; `domainFilters` alone does not separate the instances when the private domain is a subdomain of the public one | [gcp-modules.md — `sources`](gcp-modules.md#sources-must-be-crd-and-the-label-filter-goes-with-it) |
| `main.tf` has `dns_type = "external_dns"` and no external-dns module | The setup was generated with the gap "documented" instead of filled | [Pattern 1](#1-external-dns-is-not-optional-on-gcp) — wire the shared module before calling it done |
| Certificates stuck in `PENDING_VALIDATION`, then time out | DNS zone not delegated, **or** zone resource name passed where a domain is expected | `SKILL.md` step 5 for delegation; [Pattern 7](#7-zone-resource-name-vs-dns-domain) for the name |
| Cycle / self-referential block error on `module.iam` | `iam` collapsed into one invocation | [Pattern 2](#2-iam-is-invoked-twice-on-purpose) — split into two |
| `Invalid count argument` on `data "google_container_cluster" "this"` in `module.security` | `cluster_name` fed from `module.gke.cluster_name`, unknown at plan time on greenfield | [Pattern 4](#4-order-is-gke--security--base) — pass `local.cluster_name` + `depends_on = [module.gke]` |
| Namespace already exists / intermittent apply failure on external-dns | Both instances creating the namespace | [Pattern 6](#6-two-external-dns-instances-one-namespace) — `create_namespace = false` on the private one |
| `kubernetes`/`helm` resources fail auth late in a long apply | Plan-time token expired | [Pattern 8](#8-the-access-token-is-resolved-at-plan-time) — re-run the apply |
| Blue/green on the private domain does nothing | `private_gateway_name` mismatch | [Pattern 5](#5-the-private-gateway-name-is-hardcoded-in-the-base-chart) — must be `gateway-private` |
| Gateway Services annotated with a nonexistent firewall rule | `security` excluded or `gateway_internal_enabled` out of sync with `base` | [Pattern 4](#4-order-is-gke--security--base) |
| Apply fails on service account creation partway through | Slug longer than 14 chars | [gcp.md — Slug constraints](gcp.md#slug-constraints) |
| Undefined variable `account` / `account_slug` at plan time | Doc drift; the orchestrator writes `organization_slug` | Use `var.organization_slug` |
| `Unsupported argument: nrn` on `module.base` | `nrn` passed to `base`, which does not declare it | Remove it — only `agent` and `agent_api_key` take `nrn` |
| `kubectl` fails after a successful apply | `gke-gcloud-auth-plugin` not installed | Install it; tofu does not need it, kubectl does |
| `kubernetes`/`helm` resources time out from the start | Machine running tofu not in `authorized_ip_ranges` | Add its egress CIDR |
| Label value rejected | Uppercase character in `var.labels` | [Pattern 9](#9-gcp-rejects-uppercase-in-label-values) |

For generic problems see [troubleshooting.md](troubleshooting.md).
