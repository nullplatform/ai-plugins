# Arbol de Decision - AWS Infrastructure

> Invocado desde el paso 4 del wizard principal (`SKILL.md`).
> **Input global**: `infrastructure/aws/` con archivos .tf originales
> **Output global**: Archivos .tf customizados, `existing-resources.properties` (si aplica), variables nuevas en `terraform.tfvars`

> Para patrones generales de OpenTofu (source de modulos, Helm v3, agent_api_key) ver [tofu-modules-patterns.md](tofu-modules-patterns.md).

## Contenido

0. [Decision de Networking Schema](#paso-0-decision-de-networking-schema)
1. [Clasificacion de Modulos](#paso-1-clasificacion-de-modulos)
2. [Preguntar por componentes Cloud](#paso-2-preguntar-por-cada-componente-cloud)
3. [Resolver dependencias de excluidos](#paso-3-resolver-dependencias-de-modulos-excluidos)
4. [Preguntar por componentes Commons](#paso-4-preguntar-por-componentes-commons)
5. [Aplicar cambios a .tf](#paso-5-aplicar-cambios-a-los-archivos-tf)
6. [Validar archivos .tf](#paso-6-validar-archivos-tf)
7. [Variables AWS](#variables-aws)
8. [Provider Configuration](#provider-configuration)
9. [Referencia de Modulos AWS](#referencia-de-modulos-aws)
10. [Patrones Criticos AWS](#patrones-criticos-aws)
11. [Troubleshooting](#troubleshooting)

## Paso 0: Decision de Networking Schema

> **Input**: Preferencia del usuario
> **Output**: Schema elegido (`istio` o `acm_ingress`) que condiciona modulos disponibles

AWS soporta dos schemas de networking. Preguntar **antes** de clasificar modulos:

**"Que schema de networking queres usar?"**

| Aspecto | Istio (recomendado) | ACM/Ingress |
|---------|---------------------|-------------|
| Load Balancer | ALB Controller | ALB Controller |
| Ingress | Istio Gateways (Gateway API) | AWS Ingress Controller |
| Certificados | cert-manager + Let's Encrypt | ACM (nativo AWS) |
| DNS sync | External DNS | External DNS |
| `dns_type` del agent | `"external_dns"` | `"route53"` |
| Complejidad | Mayor (mas componentes) | Menor |
| Flexibilidad | Mayor (multi-cloud compatible) | Menor (AWS-only) |

> Si el usuario no tiene preferencia, recomendar **Istio** (es el default en todos los clouds).

## Paso 1: Clasificacion de Modulos

> **Input**: `infrastructure/aws/main.tf`, schema elegido en paso 0
> **Output**: Modulos clasificados por categoria

Leer `main.tf` dinamicamente y clasificar:

### Cloud (preguntables)

| Modulo | Pregunta |
|--------|----------|
| `vpc` | Ya tenes una VPC? |
| `eks` | Ya tenes un cluster EKS? |
| `route53` | Ya tenes zonas DNS en Route53? |
| `security` | Ya tenes Security Groups para los gateways? |
| `alb_controller` | Ya tenes AWS Load Balancer Controller? |

**Si schema=ACM/Ingress**, agregar:

| Modulo | Pregunta |
|--------|----------|
| `acm` | Ya tenes un certificado ACM? |
| `ingress` | Ya tenes el Ingress Controller configurado? |

**IAM modules** (preguntables, dependen de EKS OIDC):

| Modulo | Pregunta |
|--------|----------|
| `iam_external_dns` | Ya tenes el IAM role para external-dns? |
| `iam_cert_manager` | Ya tenes el IAM role para cert-manager? |
| `iam_agent` | Ya tenes el IAM role para el agente? |

### Nullplatform (siempre incluidos, no preguntar)

- `agent_api_key`, `agent`, `base`

Eliminar siempre: `scope_notification_api_key`, `service_notification_api_key`

### Commons (preguntables)

| Modulo | Pregunta |
|--------|----------|
| `cert_manager` | Ya tenes cert-manager instalado? |
| `external_dns` | Ya tenes external-dns configurado? |
| `prometheus` | Ya tenes Prometheus instalado? |

**Si schema=Istio**, agregar:

| Modulo | Pregunta |
|--------|----------|
| `istio` | Ya tenes Istio instalado? |

> Nota: AWS tiene dos instancias de external-dns (public y private). Se tratan como un solo modulo para la pregunta pero el `main.tf` puede tener dos bloques (`external_dns_public` y `external_dns_private`).

## Paso 2: Preguntar por cada componente Cloud

> **Input**: Lista de modulos Cloud
> **Output**: Lista de modulos a mantener vs excluir

Para cada modulo Cloud, preguntar: **"Ya tenes un {recurso} o necesitas que lo cree?"**

- **Crear nuevo** -> Mantener el bloque module
- **Ya tengo uno** -> Agregar a lista de excluidos, resolver dependencias en paso 3

### Orden de preguntas (respetar dependencias)

1. `vpc` (base de todo)
2. `eks` (depende de vpc)
3. `route53` (depende de vpc para zona privada)
4. `alb_controller` (depende de eks OIDC)
5. `security` (depende de eks para derivar VPC CIDR)
6. Si schema=ACM/Ingress:
   - `acm` (depende de route53)
   - `ingress` (depende de acm)
7. IAM modules:
   - `iam_external_dns` (depende de eks OIDC + route53)
   - `iam_cert_manager` (depende de eks OIDC + route53)
   - `iam_agent` (depende de eks OIDC + route53)

> Si el usuario crea `vpc`, no preguntar por sus dependencias en otros modulos.
> Si el usuario crea `eks`, los modulos IAM pueden usar su OIDC provider directamente.

## Paso 3: Resolver dependencias de modulos excluidos

> **Input**: Lista de modulos excluidos, `main.tf`
> **Output**: Valores de reemplazo para cada output referenciado

Cuando el usuario dice "ya tengo" un recurso:

1. Buscar todas las referencias `module.{modulo_excluido}.{output}` en modulos que se mantienen
2. Pedir al usuario el valor real de cada referencia encontrada
3. Guardar los valores (se usan en paso 5)

### Deteccion dinamica

```bash
grep -oP 'module\.{modulo_excluido}\.\w+' infrastructure/aws/main.tf | sort -u
```

### Data sources para recursos existentes

Cuando un recurso es existente, usar data sources en vez de variables redundantes:

**VPC existente**:
```hcl
variable "vpc_id" { type = string }

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}
```

**EKS existente**:
```hcl
variable "cluster_name" { type = string }

data "aws_eks_cluster" "existing" {
  name = var.cluster_name
}
data "aws_eks_cluster_auth" "existing" {
  name = var.cluster_name
}
data "aws_iam_openid_connect_provider" "existing" {
  url = data.aws_eks_cluster.existing.identity[0].oidc[0].issuer
}
```

**DNS zones existentes**:
```hcl
variable "public_zone_id" { type = string }
variable "private_zone_id" { type = string }

data "aws_route53_zone" "public" {
  zone_id = var.public_zone_id
}
data "aws_route53_zone" "private" {
  zone_id = var.private_zone_id
}
```

## Paso 4: Preguntar por componentes Commons

> **Input**: Lista de modulos Commons
> **Output**: Lista de modulos Commons a mantener vs excluir

Para cada modulo Commons: **"Ya tenes {componente} instalado o lo instalamos?"**

- **Instalar** -> Mantener el bloque module
- **Ya tengo** -> Eliminar (generalmente sin outputs referenciados por otros modulos)

## Paso 5: Aplicar cambios a los archivos .tf

> **Input**: Modulos a excluir (pasos 2+4), valores de reemplazo (paso 3), todos los `.tf`
> **Output**: Archivos `.tf` limpios, `terraform.tfvars` actualizado, `existing-resources.properties`

Limpiar **todos** los archivos `.tf`, no solo `main.tf`:

### 5.1 main.tf
- Eliminar bloques `module` de recursos excluidos
- Eliminar siempre `scope_notification_api_key` y `service_notification_api_key`
- Eliminar `depends_on` que referencien modulos eliminados
- Reemplazar `module.{excluido}.{output}` con `var.existing_{output}` o data sources
- Si schema=Istio: eliminar modulos `acm` e `ingress` (si existen)
- Si schema=ACM/Ingress: eliminar modulo `istio` (si existe)

### 5.2 providers.tf
- Si `eks` fue excluido: reemplazar providers `kubernetes` y `helm` para que usen data sources en vez de `module.eks.*` (ver [Provider Configuration](#provider-configuration) seccion "Cluster existente")
- Agregar data sources `aws_eks_cluster` y `aws_eks_cluster_auth` con `var.existing_cluster_name`

### 5.3 variables.tf
- Eliminar variables huerfanas (buscar `var.{nombre}` en todos los `.tf`, si no aparece -> eliminar)
- Agregar variables nuevas para recursos existentes (`var.existing_*`)

### 5.4 locals.tf
- Eliminar locals huerfanos (buscar `local.{nombre}` en todos los `.tf`, si no aparece -> eliminar)

### 5.5 outputs.tf
- Eliminar outputs que referencian modulos eliminados

### 5.6 data blocks
- Eliminar bloques `data` huerfanos en cualquier `.tf`

### 5.7 terraform.tfvars
- Agregar valores de recursos existentes: `existing_vpc_id = "vpc-xxx"`
- Configurar `dns_type` segun schema elegido:
  - Istio: `dns_type = "external_dns"`
  - ACM/Ingress: `dns_type = "route53"`

### 5.8 existing-resources.properties
- Guardar como documentacion: `vpc_id=vpc-xxx`

> `existing-resources.properties` es documentacion. Los valores reales van en `terraform.tfvars`.

## Paso 6: Validar archivos .tf

> **Input**: Archivos `.tf` modificados, `terraform.tfvars`
> **Output**: Archivos validados, listos para `tofu plan`/`tofu apply`

```bash
cd infrastructure/aws
tofu fmt
tofu init -backend=false
tofu validate
```

Usar `tofu init -backend=false` para validar sin necesitar credenciales del backend. Ver [tofu-modules-patterns.md](tofu-modules-patterns.md#flujo-de-lectura-de-modulos) para inspeccionar variables de modulos descargados.

- **Si pasa** -> Continuar con paso 5 de SKILL.md (DNS)
- **Si falla** -> Leer error, corregir, repetir. Causas comunes:
  - Referencia a modulo eliminado sin reemplazo
  - Variable sin definir o sin valor en tfvars
  - `depends_on` apuntando a modulo eliminado
  - Output referenciando modulo eliminado
  - Local huerfano

## Variables AWS

Ademas de las variables generales documentadas en [variables.md](variables.md), AWS requiere:

| Variable | Descripcion | Origen |
| -------- | ----------- | ------ |
| `aws_region` | Region AWS (ej: `us-east-1`) | terraform.tfvars |
| `aws_profile` | Perfil AWS CLI para autenticacion (default: null, opcional) | terraform.tfvars |
| `dns_type` | `"external_dns"` (Istio) o `"route53"` (ACM/Ingress) | terraform.tfvars |
| `agent_image_tag` | Siempre `"aws"` para AWS (otros clouds usan `"latest"`) | terraform.tfvars |

### Variables adicionales segun schema

**Si schema=Istio** (`dns_type = "external_dns"`), el modulo agent requiere variables adicionales que se incluyen en el template con placeholders (no preguntar, el usuario las completa al deployar):

| Variable | Descripcion |
|----------|-------------|
| `agent_use_account_slug` | Flag para usar account slug en nombres |
| `agent_image_pull_secrets` | Image pull secrets (vacio si no aplica) |
| `agent_service_template` | Path al template de servicio Istio |
| `agent_initial_ingress_path` | Path al template de ingress inicial |
| `agent_blue_green_ingress_path` | Path al template de ingress blue-green |

**Si schema=ACM/Ingress** (`dns_type = "route53"`): no se requieren variables adicionales del agent.

## Provider Configuration

### Provider AWS

```hcl
aws = { source = "hashicorp/aws", version = "~> 6.0" }
```

Para providers genericos (kubernetes, helm, nullplatform) ver [tofu-modules-patterns.md](tofu-modules-patterns.md#provider-versions-genericas).

### Cluster nuevo (creado por tofu)

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = var.aws_profile != null ? [
      "eks", "get-token", "--cluster-name", module.eks.eks_cluster_name, "--profile", var.aws_profile
    ] : [
      "eks", "get-token", "--cluster-name", module.eks.eks_cluster_name
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = var.aws_profile != null ? [
        "eks", "get-token", "--cluster-name", module.eks.eks_cluster_name, "--profile", var.aws_profile
      ] : [
        "eks", "get-token", "--cluster-name", module.eks.eks_cluster_name
      ]
    }
  }
}
```

> Outputs EKS correctos: `eks_cluster_endpoint`, `eks_cluster_ca`, `eks_cluster_name`.
> Helm v3: ver [tofu-modules-patterns.md](tofu-modules-patterns.md#helm-v3-syntax).
> aws_profile: condicional para no pasar `--profile null`.

### Cluster existente (data sources)

```hcl
data "aws_eks_cluster" "existing" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "existing" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.existing.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.existing.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.existing.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.existing.token
  }
}
```

## Referencia de Modulos AWS

Para formato de source y versionado ver [tofu-modules-patterns.md](tofu-modules-patterns.md#source-de-modulos-git-ref). Para `agent_api_key` ver [tofu-modules-patterns.md](tofu-modules-patterns.md#modulo-agent-api-key).

### Modulos IAM (inputs y outputs)

**external_dns_iam** (`infrastructure/aws/iam/external_dns`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `hosted_zone_public_id`, `hosted_zone_private_id`
- Output: `nullplatform_external_dns_role_arn`

**cert_manager_iam** (`infrastructure/aws/iam/cert_manager`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `hosted_zone_public_id`, `hosted_zone_private_id`
- Output: `nullplatform_cert_manager_role_arn`

**agent_iam** (`infrastructure/aws/iam/agent`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `agent_namespace`
- Output: `nullplatform_agent_role_arn`

### External DNS (variables correctas)

```hcl
module "external_dns_public" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"
  dns_provider_name = "aws"
  aws_region        = var.aws_region
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  domain_filters    = var.domain_name
  zone_id_filter    = module.route53.public_zone_id
  zone_type         = "public"
  type              = "public"
  depends_on        = [module.alb_controller]
}

module "external_dns_private" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"
  dns_provider_name = "aws"
  aws_region        = var.aws_region
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  domain_filters    = var.domain_name
  zone_id_filter    = module.route53.private_zone_id
  zone_type         = "private"
  type              = "private"
  create_namespace  = false
  depends_on        = [module.alb_controller, module.external_dns_public]
}
```

> `type` controla el nombre del Helm release (`external-dns-{type}`). `zone_type` filtra zonas AWS.
> El privado usa `create_namespace = false` para evitar conflicto de namespace con el publico.

### Cert Manager (variables correctas)

```hcl
module "cert_manager" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/cert_manager?ref={version}"
  cloud_provider      = "aws"
  aws_region          = var.aws_region
  aws_sa_arn          = module.cert_manager_iam.nullplatform_cert_manager_role_arn
  private_domain_name = module.route53.private_zone_name
  hosted_zone_name    = module.route53.public_zone_name
  account_slug        = var.account
  depends_on          = [module.alb_controller]
}
```

### Base (defaults para AWS)

```hcl
module "base" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref={version}"
  nrn          = var.nrn
  np_api_key   = module.agent_api_key.api_key
  k8s_provider = "eks"
  aws_region   = var.aws_region

  gateway_enabled           = true
  gateway_internal_enabled  = true
  gateways_enabled          = true
  gateway_public_aws_name   = var.gateway_public_aws_name
  gateway_internal_aws_name = var.gateway_internal_aws_name
  prometheus_enabled        = true
  metrics_server_enabled    = true

  gateway_public_aws_security_group_id  = module.security.public_gateway_security_group_id
  gateway_private_aws_security_group_id = module.security.private_gateway_security_group_id

  depends_on = [module.alb_controller]
}
```

> `metrics_server_enabled = true` instala Kubernetes metrics-server (necesario para HPA y `kubectl top`).
> `gateway_*_aws_security_group_id` vienen del modulo `security` y se usan para anotar los NLB con los SG correctos.
> `gateway_security_enabled` es `false` por defecto. Solo si se habilita se necesitan provider stubs de Azure/GCP.

## Patrones Criticos AWS

### ALB Controller Webhook

Los modulos Helm posteriores deben depender de `module.alb_controller` para asegurar que el webhook este registrado.

Todos los modulos Helm posteriores (`cert_manager`, `external_dns`, `istio`, `ingress`, `base`) deben incluir:

```hcl
depends_on = [module.alb_controller]
```

El modulo `agent` hereda la dependencia transitivamente via `depends_on = [module.base]`.

### IRSA (IAM Roles for Service Accounts)

Todos los modulos IAM (`iam_external_dns`, `iam_cert_manager`, `iam_agent`) usan el patron IRSA:

1. Obtienen el OIDC provider del cluster EKS
2. Crean un IAM role con trust policy federada
3. El trust policy permite `sts:AssumeRoleWithWebIdentity` desde el service account especifico

Dependencias tipicas: EKS OIDC provider ARN + Route53 zone ID.

### Backend S3

El backend S3 requiere `profile` en `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tfstate-bucket"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    profile        = "my-aws-profile"
  }
}
```

> Sin `profile`, tofu usa credenciales default que pueden no coincidir con el entorno deseado.
> El modulo `infrastructure/aws/backend` de tofu-modules crea bucket S3 con versioning, encryption y object lock COMPLIANCE.

### dns_type del Agent

El modulo `agent` recibe `dns_type` que determina como gestiona DNS:

- **Istio schema**: `dns_type = "external_dns"` (external-dns sincroniza records)
- **ACM/Ingress schema**: `dns_type = "route53"` (el agente gestiona Route53 directamente)

No mezclar esquemas. Si usas Istio, `dns_type` DEBE ser `external_dns`. Si usas ACM/Ingress, DEBE ser `route53`.

### Agent HTTPRoute Templates (Istio schema)

Cuando se usa Istio con Gateway API, el agent debe crear HTTPRoute (no ALB Ingress). Por defecto el agent usa templates ALB Ingress. Para que use HTTPRoute, pasar estas variables al modulo `agent`:

```hcl
module "agent" {
  ...
  service_template        = var.service_template
  initial_ingress_path    = var.initial_ingress_path
  blue_green_ingress_path = var.blue_green_ingress_path
}
```

Defaults recomendados en `variables.tf`:

| Variable | Default |
|----------|---------|
| `service_template` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/service.yaml.tpl` |
| `initial_ingress_path` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/initial-httproute.yaml.tpl` |
| `blue_green_ingress_path` | `/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/blue-green-httproute.yaml.tpl` |

Sin estas variables, el agent crea Ingress con `ingressClassName: alb` que no es compatible con Gateway API. Resultado: no se crea HTTPRoute, el DNS no resuelve.

### Security Module y Cluster SG

El modulo `security` crea SGs para los gateways (NLB) y opcionalmente agrega reglas de ingreso al SG del cluster EKS. Pasar `cluster_security_group_id` con el **primary SG** (EKS-managed):

```hcl
module "security" {
  ...
  cluster_name              = module.eks.eks_cluster_name
  cluster_security_group_id = module.eks.eks_cluster_primary_security_group_id
}
```

**IMPORTANTE**: Usar `eks_cluster_primary_security_group_id` (el SG creado y gestionado por EKS, adjunto a todos los nodos). NO usar `eks_cluster_security_group_id` (additional SG creado por el modulo Terraform, no adjunto a nodos por defecto).

Sin estas reglas, el NLB no puede alcanzar los pods de Istio gateway → targets unhealthy → timeout en el endpoint.

## Troubleshooting

Para problemas AWS-especificos (ALB webhook, IRSA, EKS endpoint, S3 backend) ver [aws-troubleshooting.md](aws-troubleshooting.md).
Para problemas genericos ver [troubleshooting.md](troubleshooting.md).
