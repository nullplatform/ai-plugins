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

## Backend by Cloud

| Cloud | Backend | Required Values |
|-------|---------|-----------------|
| AWS | `s3` | `bucket`, `key`, `region`, `profile` |
| Azure | `azurerm` | `resource_group_name`, `storage_account_name`, `container_name`, `key` |
| Azure ARO | `azurerm` (create if not exists) | Same as Azure |
| GCP | `gcs` | `bucket`, `prefix` |
| OCI | `s3` (compatible) | `bucket`, `key`, `region`, `endpoints.s3` |
