# Resources by Cloud Provider

## Networking

| Resource | AWS | Azure | Azure ARO | GCP | OCI |
| -------- | --- | ----- | --------- | --- | --- |
| Virtual Network | VPC | VNet | VNet | VPC | VCN |
| Subnets | Public/Private | AKS/Gateway/Endpoints | ARO/Gateway | Public/Private | Public/Private |
| NAT | NAT Gateway | Implicit | Implicit | Cloud NAT | NAT Gateway |

## Kubernetes

| Resource | AWS | Azure | Azure ARO | GCP | OCI |
| -------- | --- | ----- | --------- | --- | --- |
| Cluster | EKS | AKS | ARO (OpenShift) | GKE | OKE |
| Node Pools | Managed | System + User | Worker | Default | Managed |
| OIDC | IRSA (IAM Roles for Service Accounts) | AAD | AAD | Workload Identity | OCI IAM |
| IAM Bindings | IRSA via OIDC provider | Managed Identity | Managed Identity | Workload Identity binding | Instance Principal |

## DNS & Certificates

| Resource | AWS | Azure | Azure ARO | GCP | OCI |
| -------- | --- | ----- | --------- | --- | --- |
| DNS Zone | Route53 | Azure DNS / Cloudflare | Azure DNS / Cloudflare | Cloud DNS | OCI DNS |
| Certificates | ACM + cert-manager | cert-manager | cert-manager | cert-manager | cert-manager |

## Nullplatform Components

| Component | Description |
| --------- | ----------- |
| Agent | Executes control plane actions |
| Base | Foundational K8s configuration |
| Istio | Ingress Gateway for HTTPRoute routing |
| External DNS | Syncs DNS automatically |
| Prometheus | Metrics (optional) |

## Ingress by Cloud

By default, all clouds use **Istio** (Gateway API) as the ingress controller.

**Exception: AWS** has two networking schemas (see [aws.md](aws.md) step 0):
- **Istio** (recommended): Istio Gateways + cert-manager + Let's Encrypt
- **ACM/Ingress**: AWS Ingress Controller + ACM (AWS native certificates)

Both schemas use **ALB Controller** as the load balancer. The difference is the ingress layer and certificate management.

| Cloud | Default Ingress | Alternative | Load Balancer |
|-------|----------------|-------------|---------------|
| AWS | Istio (Gateway API) | ACM/Ingress Controller | ALB Controller (both schemas) |
| Azure | Istio | - | Azure LB |
| Azure ARO | Istio | - | Azure LB |
| GCP | Istio | - | GCP LB |
| OCI | Istio | - | OCI LB |

## Agent HTTPRoute Templates (Istio schema) — MANDATORY

When using Istio (Gateway API) on any cloud, the agent module MUST include the following variables so it creates HTTPRoute resources instead of falling back to default Ingress templates. **These values are MANDATORY — they MUST NOT be left empty, omitted, or as placeholders:**

| Variable | Required Value |
|----------|----------------|
| `service_template` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/service.yaml.tpl` |
| `initial_ingress_path` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/initial-httproute.yaml.tpl` |
| `blue_green_ingress_path` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/blue-green-httproute.yaml.tpl` |

> **CRITICAL**: Without these variables, the agent creates default Ingress resources (e.g., `ingressClassName: alb` on AWS) instead of HTTPRoute. This breaks DNS resolution and routing completely. This is the most common cause of broken routing when using Istio.

These variables are additional to the rest of the agent module variables (`dns_type`, `agent_image_tag`, `nrn`, etc.) — they do not replace them. Set them in both `variables.tf` (as defaults) and `terraform.tfvars`.

## Base Module — Gateway NLB Naming — MANDATORY

The `base` module's gateway load balancer names MUST always include the account slug to guarantee uniqueness. The module defaults (`k8s-nullplatform-internet-facing`, `k8s-nullplatform-internal`) assume a single setup per cloud account and fail with `DuplicateLoadBalancerName` (or equivalent) when there are multiple.

**Always set these variables in the `base` module using the account slug:**

| Variable | Required Pattern |
|----------|-----------------|
| `gateway_public_aws_name` | `k8s-np-{account_slug}-public` |
| `gateway_internal_aws_name` | `k8s-np-{account_slug}-internal` |

Replace `{account_slug}` with the actual organization/account slug (e.g., `k8s-np-acme-public`).

> **CRITICAL**: AWS NLB names have a **32 character limit**. The pattern `k8s-np-{slug}-internal` uses 17 characters for the prefix/suffix, leaving **15 characters** for the slug. If the slug exceeds 15 characters, truncate it (e.g., `agustin-training-dos` -> `agustin-train`). Always verify the final name is <= 32 characters before applying.

> **CRITICAL**: Never rely on the module defaults for these names. Always pass explicit values with the account slug, regardless of whether there are currently multiple setups in the same cloud account.

These variables are additional to the rest of the base module variables (`nrn`, `np_api_key`, `k8s_provider`, etc.) — they do not replace them.

## Backend by Cloud

| Cloud | Backend | Required Values |
|-------|---------|-----------------|
| AWS | `s3` | `bucket`, `key`, `region`, `profile` |
| Azure | `azurerm` | `resource_group_name`, `storage_account_name`, `container_name`, `key` |
| Azure ARO | `azurerm` (create if not exists) | Same as Azure |
| GCP | `gcs` | `bucket`, `prefix` |
| OCI | `s3` (compatible) | `bucket`, `key`, `region`, `endpoints.s3` |
