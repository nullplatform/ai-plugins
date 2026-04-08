# Decision Tree - AWS Infrastructure

> Invoked from step 4 of the main wizard (`SKILL.md`).
> **Global input**: `infrastructure/aws/` with original .tf files
> **Global output**: Customized .tf files, `existing-resources.properties` (if applicable), new variables in `terraform.tfvars`

> For general OpenTofu patterns (module source, Helm v3, agent_api_key) see [tofu-modules-patterns.md](tofu-modules-patterns.md).

## Contents

0. [Networking Schema Decision](#step-0-networking-schema-decision)
1. [Module Classification](#step-1-module-classification)
2. [Ask about Cloud components](#step-2-ask-about-each-cloud-component)
3. [Resolve excluded dependencies](#step-3-resolve-excluded-module-dependencies)
4. [Ask about Commons components](#step-4-ask-about-commons-components)
5. [Apply changes to .tf](#step-5-apply-changes-to-tf-files)
6. [Validate .tf files](#step-6-validate-tf-files)
7. [AWS Variables](#aws-variables)
8. [Provider Configuration](#provider-configuration)
9. [AWS Module Reference](#aws-module-reference)
10. [Critical AWS Patterns](#critical-aws-patterns)
11. [Troubleshooting](#troubleshooting)

## Step 0: Networking Schema Decision

> **Input**: User preference
> **Output**: Chosen schema (`istio` or `acm_ingress`) that conditions available modules

AWS supports two networking schemas. Ask **before** classifying modules:

**"Which networking schema do you want to use?"**

| Aspect | Istio (recommended) | ACM/Ingress |
|--------|---------------------|-------------|
| Load Balancer | ALB Controller | ALB Controller |
| Ingress | Istio Gateways (Gateway API) | AWS Ingress Controller |
| Certificates | cert-manager + Let's Encrypt | ACM (AWS native) |
| DNS sync | External DNS | External DNS |
| Agent `dns_type` | `"external_dns"` | `"route53"` |
| Complexity | Higher (more components) | Lower |
| Flexibility | Higher (multi-cloud compatible) | Lower (AWS-only) |

> If the user has no preference, recommend **Istio** (it's the default across all clouds).

## Step 1: Module Classification

> **Input**: `infrastructure/aws/main.tf`, schema chosen in step 0
> **Output**: Modules classified by category

Read `main.tf` dynamically and classify:

### Cloud (askable)

| Module | Question |
|--------|----------|
| `vpc` | Do you already have a VPC? |
| `eks` | Do you already have an EKS cluster? |
| `dns` | Do you already have DNS zones in Route53? |
| `alb_controller` | Do you already have AWS Load Balancer Controller? |

**If schema=ACM/Ingress**, add:

| Module | Question |
|--------|----------|
| `acm` | Do you already have an ACM certificate? |
| `ingress` | Do you already have the Ingress Controller configured? |

**IAM modules** (askable, depend on EKS OIDC):

| Module | Question |
|--------|----------|
| `iam_external_dns` | Do you already have the IAM role for external-dns? |
| `iam_cert_manager` | Do you already have the IAM role for cert-manager? |
| `iam_agent` | Do you already have the IAM role for the agent? |

### Nullplatform (always included, don't ask)

- `agent_api_key`, `agent`, `base`

Always remove: `scope_notification_api_key`, `service_notification_api_key`

### Commons (askable)

| Module | Question |
|--------|----------|
| `cert_manager` | Do you already have cert-manager installed? |
| `external_dns` | Do you already have external-dns configured? |
| `prometheus` | Do you already have Prometheus installed? |

**If schema=Istio**, add:

| Module | Question |
|--------|----------|
| `istio` | Do you already have Istio installed? |

> Note: AWS has two external-dns instances (public and private). They are treated as a single module for the question but the `main.tf` may have two blocks (`external_dns_public` and `external_dns_private`).

## Step 2: Ask about each Cloud component

> **Input**: List of Cloud modules
> **Output**: List of modules to keep vs exclude

For each Cloud module, ask: **"Do you already have a {resource} or do you need it created?"**

- **Create new** -> Keep the module block
- **I already have one** -> Add to excluded list, resolve dependencies in step 3

### Question order (respect dependencies)

1. `vpc` (base of everything)
2. `eks` (depends on vpc)
3. `dns` (depends on vpc for private zone)
4. `alb_controller` (depends on eks OIDC)
6. If schema=ACM/Ingress:
   - `acm` (depends on dns)
   - `ingress` (depends on acm)
7. IAM modules:
   - `iam_external_dns` (depends on eks OIDC + dns)
   - `iam_cert_manager` (depends on eks OIDC + dns)
   - `iam_agent` (depends on eks OIDC + dns)

> If the user creates `vpc`, don't ask about its dependencies in other modules.
> If the user creates `eks`, IAM modules can use its OIDC provider directly.

## Step 3: Resolve excluded module dependencies

> **Input**: List of excluded modules, `main.tf`
> **Output**: Replacement values for each referenced output

When the user says "I already have" a resource:

1. Find all `module.{excluded_module}.{output}` references in maintained modules
2. Ask the user for the real value of each found reference
3. Save the values (used in step 5)

### Dynamic detection

```bash
grep -oP 'module\.{excluded_module}\.\w+' infrastructure/aws/main.tf | sort -u
```

### Data sources for existing resources

When a resource already exists, use data sources instead of redundant variables:

**Existing VPC**:
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

**Existing EKS**:
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

**Existing DNS zones**:
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

## Step 4: Ask about Commons components

> **Input**: List of Commons modules
> **Output**: List of Commons modules to keep vs exclude

For each Commons module: **"Do you already have {component} installed or should we install it?"**

- **Install** -> Keep the module block
- **I already have it** -> Remove (generally no outputs referenced by other modules)

## Step 5: Apply changes to .tf files

> **Input**: Modules to exclude (steps 2+4), replacement values (step 3), all `.tf` files
> **Output**: Clean `.tf` files, updated `terraform.tfvars`, `existing-resources.properties`

Clean **all** `.tf` files, not just `main.tf`:

### 5.1 main.tf
- Remove `module` blocks for excluded resources
- Always remove `scope_notification_api_key` and `service_notification_api_key`
- Remove `depends_on` referencing deleted modules
- Replace `module.{excluded}.{output}` with `var.existing_{output}` or data sources
- If schema=Istio: remove `acm` and `ingress` modules (if they exist)
- If schema=ACM/Ingress: remove `istio` module (if it exists)

### 5.2 providers.tf
- If `eks` was excluded: replace `kubernetes` and `helm` providers to use data sources instead of `module.eks.*` (see [Provider Configuration](#provider-configuration) "Existing cluster" section)
- Add `aws_eks_cluster` and `aws_eks_cluster_auth` data sources with `var.existing_cluster_name`

### 5.3 variables.tf
- Remove orphaned variables (search `var.{name}` in all `.tf`, if not found -> remove)
- Add new variables for existing resources (`var.existing_*`)

### 5.4 locals.tf
- Remove orphaned locals (search `local.{name}` in all `.tf`, if not found -> remove)

### 5.5 outputs.tf
- Remove outputs referencing deleted modules

### 5.6 data blocks
- Remove orphaned `data` blocks in any `.tf`

### 5.7 terraform.tfvars
- Add existing resource values: `existing_vpc_id = "vpc-xxx"`
- Configure `dns_type` based on chosen schema:
  - Istio: `dns_type = "external_dns"`
  - ACM/Ingress: `dns_type = "route53"`

### 5.8 existing-resources.properties
- Save as documentation: `vpc_id=vpc-xxx`

> `existing-resources.properties` is documentation. Real values go in `terraform.tfvars`.

## Step 6: Validate .tf files

> **Input**: Modified `.tf` files, `terraform.tfvars`
> **Output**: Validated files, ready for `tofu plan`/`tofu apply`

```bash
cd infrastructure/aws
tofu fmt
tofu init -backend=false
tofu validate
```

Use `tofu init -backend=false` to validate without needing backend credentials. See [tofu-modules-patterns.md](tofu-modules-patterns.md#module-reading-flow) for inspecting downloaded module variables.

- **If it passes** -> Continue with step 5 of SKILL.md (DNS)
- **If it fails** -> Read error, fix, repeat. Common causes:
  - Reference to deleted module without replacement
  - Undefined variable or missing value in tfvars
  - `depends_on` pointing to deleted module
  - Output referencing deleted module
  - Orphaned local

## AWS Variables

In addition to the general variables documented in [variables.md](variables.md), AWS requires:

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `aws_region` | AWS region (e.g., `us-east-1`) | terraform.tfvars |
| `aws_profile` | AWS CLI profile for authentication (default: null, optional) | terraform.tfvars |
| `dns_type` | `"external_dns"` (Istio) or `"route53"` (ACM/Ingress) | terraform.tfvars |
| `agent_image_tag` | Always `"aws"` for AWS (other clouds use `"latest"`) | terraform.tfvars |

### Additional variables by schema

**If schema=Istio** (`dns_type = "external_dns"`), the agent module requires additional MANDATORY variables. See [Agent HTTPRoute Templates in resources-by-cloud.md](resources-by-cloud.md#agent-httproute-templates-istio-schema--mandatory) for the exact required values — they must not be left empty.

**If schema=ACM/Ingress** (`dns_type = "route53"`): no additional agent variables are required.

## Provider Configuration

### AWS Provider

```hcl
aws = { source = "hashicorp/aws", version = "~> 6.0" }
```

For generic providers (kubernetes, helm, nullplatform) see [tofu-modules-patterns.md](tofu-modules-patterns.md#generic-provider-versions).

### New cluster (created by tofu)

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

> Correct EKS outputs: `eks_cluster_endpoint`, `eks_cluster_ca`, `eks_cluster_name`.
> Helm v3: see [tofu-modules-patterns.md](tofu-modules-patterns.md#helm-v3-syntax).
> aws_profile: conditional to avoid passing `--profile null`.

> **EKS: `endpoint_public_access_cidrs` is required** when `endpoint_public_access = true` (which is the default). The variable has `default = []` but a `validation` block that enforces at least one CIDR when public access is enabled. Always ask the user for the CIDRs to allow (e.g., `["0.0.0.0/0"]` for open access, or specific IPs for restricted access).

### Existing cluster (data sources)

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

## AWS Module Reference

For source format and versioning see [tofu-modules-patterns.md](tofu-modules-patterns.md#git-ref-module-source). For `agent_api_key` see [tofu-modules-patterns.md](tofu-modules-patterns.md#agent-api-key-module).

### IAM Modules (inputs and outputs)

**external_dns_iam** (`infrastructure/aws/iam/external_dns`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `hosted_zone_public_id`, `hosted_zone_private_id`
- Output: `nullplatform_external_dns_role_arn`

**cert_manager_iam** (`infrastructure/aws/iam/cert_manager`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `hosted_zone_public_id`, `hosted_zone_private_id`
- Output: `nullplatform_cert_manager_role_arn`

**agent_iam** (`infrastructure/aws/iam/agent`):
- Inputs: `cluster_name`, `aws_iam_openid_connect_provider_arn`, `agent_namespace`
- Output: `nullplatform_agent_role_arn`

### External DNS (correct variables)

```hcl
module "external_dns_public" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns?ref={version}"
  dns_provider_name = "aws"
  aws_region        = var.aws_region
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  domain_filters    = var.domain_name
  zone_id_filter    = module.dns.public_zone_id
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
  zone_id_filter    = module.dns.private_zone_id
  zone_type         = "private"
  type              = "private"
  create_namespace  = false
  depends_on        = [module.alb_controller, module.external_dns_public]
}
```

> `type` controls the Helm release name (`external-dns-{type}`). `zone_type` filters AWS zones.
> The private one uses `create_namespace = false` to avoid namespace conflict with the public one.

### Cert Manager (correct variables)

```hcl
module "cert_manager" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/cert_manager?ref={version}"
  cloud_provider      = "aws"
  aws_region          = var.aws_region
  aws_sa_arn          = module.cert_manager_iam.nullplatform_cert_manager_role_arn
  private_domain_name = module.dns.private_zone_name
  hosted_zone_name    = module.dns.public_zone_name
  account_slug        = var.account
  depends_on          = [module.alb_controller]
}
```

### Base (AWS defaults)

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

  depends_on = [module.alb_controller]
}
```

> `metrics_server_enabled = true` installs Kubernetes metrics-server (needed for HPA and `kubectl top`).
> `gateway_security_enabled` is `false` by default. Only if enabled are Azure/GCP provider stubs needed.

## Critical AWS Patterns

### ALB Controller Webhook

Subsequent Helm modules must depend on `module.alb_controller` to ensure the webhook is registered.

All subsequent Helm modules (`cert_manager`, `external_dns`, `istio`, `ingress`, `base`) must include:

```hcl
depends_on = [module.alb_controller]
```

The `agent` module inherits the dependency transitively via `depends_on = [module.base]`.

### IRSA (IAM Roles for Service Accounts)

All IAM modules (`iam_external_dns`, `iam_cert_manager`, `iam_agent`) use the IRSA pattern:

1. They get the OIDC provider from the EKS cluster
2. They create an IAM role with a federated trust policy
3. The trust policy allows `sts:AssumeRoleWithWebIdentity` from the specific service account

Typical dependencies: EKS OIDC provider ARN + Route53 zone ID.

### S3 Backend

The S3 backend requires `profile` in `backend.tf`:

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

> Without `profile`, tofu uses default credentials which may not match the desired environment.
> The `infrastructure/aws/backend` module from tofu-modules creates an S3 bucket with versioning, encryption, and COMPLIANCE object lock.

### Agent dns_type

The `agent` module receives `dns_type` which determines how it manages DNS:

- **Istio schema**: `dns_type = "external_dns"` (external-dns syncs records)
- **ACM/Ingress schema**: `dns_type = "route53"` (the agent manages Route53 directly)

Do not mix schemas. If you use Istio, `dns_type` MUST be `external_dns`. If you use ACM/Ingress, it MUST be `route53`.

### Agent HTTPRoute Templates (Istio schema)

When using Istio with Gateway API, the agent must create HTTPRoute (not ALB Ingress). See [Agent HTTPRoute Templates in resources-by-cloud.md](resources-by-cloud.md#agent-httproute-templates-istio-schema--mandatory) for the mandatory variable values that must be set in the agent module.

## Troubleshooting

For AWS-specific problems (ALB webhook, IRSA, EKS endpoint, S3 backend) see [aws-troubleshooting.md](aws-troubleshooting.md).
For generic problems see [troubleshooting.md](troubleshooting.md).
