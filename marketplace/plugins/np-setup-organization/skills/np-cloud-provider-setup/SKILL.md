---
name: np-cloud-provider-setup
description: This skill should be used when the user asks to "configure cloud credentials", "setup AWS access", "setup Azure access", "setup GCP access", "connect cloud provider", or needs to configure cloud provider authentication for nullplatform infrastructure provisioning.
---

# Nullplatform Cloud Provider Setup

Configure your cloud provider credentials to be able to create infrastructure.

## When to Use

- Configuring cloud credentials for the first time
- Changing cloud provider
- Validating existing credentials
- Infrastructure already exists and you only need to validate access

## Prerequisites

Before using this skill, make sure you have configured:

1. Verify that `NP_API_KEY` is configured (environment variable or `.env`)
2. Invoke `/np-api check-auth` to verify authentication and get the organization_id

## Supported Cloud Providers

| Provider | Kubernetes | Container Registry | DNS |
|----------|------------|-------------------|-----|
| AWS | EKS | ECR | Route53 |
| Azure | AKS | ACR | Azure DNS / Cloudflare |
| GCP | GKE | Artifact Registry | Cloud DNS |

## Configuration by Provider

### AWS

**Requirements:**

- AWS Account with permissions to create EKS, VPC, Route53, ECR
- AWS CLI configured
- IAM credentials (Access Key + Secret Key) or IAM Role

**Validation:**

```bash
# Verify credentials
aws sts get-caller-identity

# Verify basic permissions
aws ec2 describe-vpcs --max-items 1
```

**Reference templates:** `infrastructure/example/aws/`

---

### Azure

**Requirements:**

- Azure Subscription with permissions to create AKS, VNet, ACR, DNS
- Azure CLI installed and logged in
- Service Principal with Contributor permissions

**Create Service Principal:**

```bash
az ad sp create-for-rbac --name "nullplatform-sp" --role Contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

**Validation:**

```bash
# Login
az login

# Verify subscription
az account show

# Verify permissions
az group list --query "[0].name"
```

**Reference templates:** `infrastructure/example/azure/`

---

### GCP

**Requirements:**

- GCP Project with enabled APIs (GKE, VPC, Cloud DNS, Artifact Registry)
- Service Account with Editor permissions
- gcloud CLI configured

**Enable APIs:**

```bash
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable artifactregistry.googleapis.com
```

**Validation:**

```bash
# Verify configuration
gcloud config list

# Verify permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

**Reference templates:** `infrastructure/example/gcp/`

## Use Cases

### Case 1: Create new infrastructure

If you don't have infrastructure, the wizard will help you:
1. Choose your folder structure
2. Copy templates from `infrastructure/example/{provider}/`
3. Customize the variables

### Case 2: Infrastructure already exists

If you already have infrastructure (VPC, K8s, etc.), you only need to:
1. Validate access with the commands above
2. Skip to the `/np-nullplatform-wizard` skill

## Checklist Before Continuing

- [ ] Cloud CLI installed and configured
- [ ] Valid credentials with sufficient permissions
- [ ] Region/location selected
- [ ] Domain available for DNS (optional but recommended)

## Next Step

Once credentials are configured, the next step is to create the infrastructure:

**Tell Claude**: "Let's create the infrastructure"

Or invoke directly: `/np-infrastructure-wizard`

## Troubleshooting

### AWS: Access Denied

- Verify that the IAM user has permissions for EKS, EC2, Route53
- Review policies attached to the user/role

### Azure: Authentication Failed

- Verify that the Service Principal hasn't expired
- Regenerate secret if needed: `az ad sp credential reset --name "nullplatform-sp"`

### GCP: Permission Denied

- Verify that APIs are enabled
- Review Service Account IAM roles
