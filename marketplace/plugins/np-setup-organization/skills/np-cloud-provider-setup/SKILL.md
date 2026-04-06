---
name: np-cloud-provider-setup
description: This skill should be used when the user asks to "configure cloud credentials", "setup AWS access", "setup Azure access", "setup GCP access", "connect cloud provider", or needs to configure cloud provider authentication for nullplatform infrastructure provisioning.
---

# Nullplatform Cloud Provider Setup

Configura las credenciales de tu cloud provider para poder crear infraestructura.

## Cuando Usar

- Configurando credenciales de cloud por primera vez
- Cambiando de cloud provider
- Validando credenciales existentes
- Infraestructura ya existe y solo necesitas validar acceso

## Prerequisitos

Antes de usar este skill, asegurate de tener configurado:

1. Verificar que `NP_API_KEY` está configurada (variable de entorno o `.env`)
2. Invocar `/np-api check-auth` para verificar autenticacion y obtener el organization_id

## Cloud Providers Soportados

| Provider | Kubernetes | Container Registry | DNS |
|----------|------------|-------------------|-----|
| AWS | EKS | ECR | Route53 |
| Azure | AKS | ACR | Azure DNS / Cloudflare |
| GCP | GKE | Artifact Registry | Cloud DNS |

## Configuracion por Provider

### AWS

**Requisitos:**

- AWS Account con permisos para crear EKS, VPC, Route53, ECR
- AWS CLI configurado
- IAM credentials (Access Key + Secret Key) o IAM Role

**Validacion:**

```bash
# Verificar credenciales
aws sts get-caller-identity

# Verificar permisos basicos
aws ec2 describe-vpcs --max-items 1
```

**Templates de referencia:** `infrastructure/example/aws/`

---

### Azure

**Requisitos:**

- Azure Subscription con permisos para crear AKS, VNet, ACR, DNS
- Azure CLI instalado y logueado
- Service Principal con permisos de Contributor

**Crear Service Principal:**

```bash
az ad sp create-for-rbac --name "nullplatform-sp" --role Contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

**Validacion:**

```bash
# Login
az login

# Verificar subscription
az account show

# Verificar permisos
az group list --query "[0].name"
```

**Templates de referencia:** `infrastructure/example/azure/`

---

### GCP

**Requisitos:**

- GCP Project con APIs habilitadas (GKE, VPC, Cloud DNS, Artifact Registry)
- Service Account con permisos de Editor
- gcloud CLI configurado

**Habilitar APIs:**

```bash
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

**Validacion:**

```bash
# Verificar configuracion
gcloud config list

# Verificar permisos
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

**Templates de referencia:** `infrastructure/example/gcp/`

## Casos de Uso

### Caso 1: Crear infraestructura nueva

Si no tenes infraestructura, el wizard te ayudara a:
1. Elegir tu estructura de carpetas
2. Copiar templates desde `infrastructure/example/{provider}/`
3. Personalizar las variables

### Caso 2: Infraestructura ya existe

Si ya tenes infraestructura (VPC, K8s, etc.), solo necesitas:
1. Validar acceso con los comandos de arriba
2. Saltar al skill `/np-nullplatform-wizard`

## Checklist Antes de Continuar

- [ ] Cloud CLI instalado y configurado
- [ ] Credenciales validas con permisos suficientes
- [ ] Region/location seleccionado
- [ ] Dominio disponible para DNS (opcional pero recomendado)

## Siguiente Paso

Una vez configuradas las credenciales, el siguiente paso es crear la infraestructura:

**Decile a Claude**: "Creemos la infraestructura"

O invoca directamente: `/np-infrastructure-wizard`

## Troubleshooting

### AWS: Access Denied

- Verificar que el IAM user tiene permisos para EKS, EC2, Route53
- Revisar policies attached al user/role

### Azure: Authentication Failed

- Verificar que el Service Principal no expiro
- Regenerar secret si es necesario: `az ad sp credential reset --name "nullplatform-sp"`

### GCP: Permission Denied

- Verificar que las APIs estan habilitadas
- Revisar IAM roles del Service Account
