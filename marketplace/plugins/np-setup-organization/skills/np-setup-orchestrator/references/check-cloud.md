# check-cloud: Verify Cloud

## Flow with Automatic Detection

### Step 1: Detect Cloud Provider

```bash
ls -d infrastructure/*/ 2>/dev/null | grep -v example
```

If no folder is detected, ask which one to use.

### Step 2: Extract Account Configuration from Terraform

#### AWS

Search in Terraform files (priority order):

```bash
# 1. Profile in terraform.tfvars
grep -E '^aws_profile\s*=' infrastructure/aws/terraform.tfvars 2>/dev/null

# 2. Profile in backend.tf
grep -E 'profile\s*=' infrastructure/aws/backend.tf 2>/dev/null

# 3. Account ID in comments or NRN
grep -E 'account.*=.*[0-9]{12}|arn:aws:.*:[0-9]{12}:' infrastructure/aws/*.tf infrastructure/aws/*.tfvars 2>/dev/null

# 4. S3 bucket from backend
grep -E 'bucket\s*=' infrastructure/aws/backend.tf 2>/dev/null
```

#### Azure

```bash
grep -E 'subscription_id|tenant_id' infrastructure/azure/*.tf infrastructure/azure/*.tfvars 2>/dev/null
```

#### GCP

```bash
grep -E 'project\s*=' infrastructure/gcp/*.tf infrastructure/gcp/*.tfvars 2>/dev/null
```

### Step 3: Map Profile to Account ID

If an AWS profile was detected:

```bash
grep -A10 "\[profile {PROFILE_NAME}\]" ~/.aws/config | grep -E 'sso_account_id|role_arn' | head -1
```

### Step 4: Show Detected Information

Show a table with what was detected (provider, profile, region, account ID).

### Step 5: Verify Current Access

```bash
aws sts get-caller-identity 2>&1
```

- **If access successful**: compare current account ID vs required. If they match, show success. If they don't match, warn about mismatch.
- **If access fails**: go to guided authentication flow.

### Guided Authentication Flow

**If a profile was detected in Terraform:**

Offer with AskUserQuestion:
- **Yes, authenticate with {PROFILE_NAME}** → `aws sso login --profile {PROFILE_NAME}`
- **Use another profile** → List profiles that match the account ID
- **Continue without cloud access** → Skip verification

**If there are multiple valid profiles for the same account:** show list and ask which to use.

**If there are NO compatible profiles:** show available profiles with their accounts and offer: configure new SSO profile, use Access Keys, or continue without access.

### Authentication by Provider

#### AWS
```bash
aws sso login --profile {PROFILE_NAME}
aws sts get-caller-identity --profile {PROFILE_NAME}
export AWS_PROFILE={PROFILE_NAME}
```

#### Azure
```bash
az login
az account set --subscription {SUBSCRIPTION_ID}
```

#### GCP
```bash
gcloud auth login
gcloud config set project {PROJECT_ID}
```

### If "Continue without cloud access" is chosen

Inform that cloud infra cannot be verified, K8s may work if kubeconfig is already configured, and the API works normally. Mark check-cloud as "skipped" and continue with check-k8s.
