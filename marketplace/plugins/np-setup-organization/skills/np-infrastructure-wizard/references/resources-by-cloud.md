# Recursos por Cloud Provider

## Networking

| Recurso | AWS | Azure | Azure ARO | GCP | OCI |
| ------- | --- | ----- | --------- | --- | --- |
| Red Virtual | VPC | VNet | VNet | VPC | VCN |
| Subnets | Public/Private | AKS/Gateway/Endpoints | ARO/Gateway | Public/Private | Public/Private |
| NAT | NAT Gateway | Implicit | Implicit | Cloud NAT | NAT Gateway |

## Kubernetes

| Recurso | AWS | Azure | Azure ARO | GCP | OCI |
| ------- | --- | ----- | --------- | --- | --- |
| Cluster | EKS | AKS | ARO (OpenShift) | GKE | OKE |
| Node Pools | Managed | System + User | Worker | Default | Managed |
| OIDC | IRSA (IAM Roles for Service Accounts) | AAD | AAD | Workload Identity | OCI IAM |
| IAM Bindings | IRSA via OIDC provider | Managed Identity | Managed Identity | Workload Identity binding | Instance Principal |

## DNS & Certificates

| Recurso | AWS | Azure | Azure ARO | GCP | OCI |
| ------- | --- | ----- | --------- | --- | --- |
| DNS Zone | Route53 | Azure DNS / Cloudflare | Azure DNS / Cloudflare | Cloud DNS | OCI DNS |
| Certificates | ACM + cert-manager | cert-manager | cert-manager | cert-manager | cert-manager |

## Nullplatform Components

| Componente | Descripcion |
| ---------- | ----------- |
| Agent | Ejecuta acciones del control plane |
| Base | Configuracion foundacional K8s |
| Istio | Ingress Gateway para HTTPRoute routing |
| External DNS | Sincroniza DNS automaticamente |
| Prometheus | Metricas (opcional) |

## Ingress por Cloud

Por default, todos los clouds usan **Istio** (Gateway API) como ingress controller.

**Excepcion: AWS** tiene dos schemas de networking (ver [aws.md](aws.md) paso 0):
- **Istio** (recomendado): Istio Gateways + cert-manager + Let's Encrypt
- **ACM/Ingress**: AWS Ingress Controller + ACM (certificados nativos AWS)

Ambos schemas usan **ALB Controller** como load balancer. La diferencia es el ingress layer y la gestion de certificados.

| Cloud | Ingress por default | Alternativa | Load Balancer |
|-------|--------------------|-------------|---------------|
| AWS | Istio (Gateway API) | ACM/Ingress Controller | ALB Controller (ambos schemas) |
| Azure | Istio | - | Azure LB |
| Azure ARO | Istio | - | Azure LB |
| GCP | Istio | - | GCP LB |
| OCI | Istio | - | OCI LB |

## Backend por Cloud

| Cloud | Backend | Valores requeridos |
|-------|---------|-------------------|
| AWS | `s3` | `bucket`, `key`, `region`, `profile` |
| Azure | `azurerm` | `resource_group_name`, `storage_account_name`, `container_name`, `key` |
| Azure ARO | `azurerm` (crear si no existe) | Mismos que Azure |
| GCP | `gcs` | `bucket`, `prefix` |
| OCI | `s3` (compatible) | `bucket`, `key`, `region`, `endpoints.s3` |
