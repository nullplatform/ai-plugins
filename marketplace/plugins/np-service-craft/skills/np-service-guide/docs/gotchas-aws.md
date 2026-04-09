# AWS Gotchas

## S3 Lifecycle Rules

AWS provider requires an explicit `filter {}` block in lifecycle rules, even if it applies to all objects:

```hcl
rule {
  id     = "my-rule"
  status = "Enabled"
  filter {}
  transition { ... }
}
```

Without `filter {}`, current versions give a warning and future versions will give an error.

## Credentials for Local Testing

Before running the agent locally with AWS services:

```bash
aws sso login --profile <name>
aws sts get-caller-identity --profile <name>  # verify
```

The profile is configured in `values.yaml` (`aws_profile`) and `build_context` exports it as `AWS_PROFILE`.

## ARNs in Permissions

Derive ARNs from names instead of reading them from `service.attributes`:

```bash
# S3 (deterministic):
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

# RDS:
DB_ARN="arn:aws:rds:${REGION}:${ACCOUNT_ID}:db:${DB_INSTANCE_NAME}"
```

Reason: `.service.attributes` may not contain the ARN as a direct field.

## IAM Name Length Limits

IAM resources have strict character limits. **Always use `sanitize_name()`** to truncate:

| Resource | Max chars | Common pattern |
|----------|-----------|----------------|
| IAM User | 64 | `sanitize_name "${SERVICE_NAME}-${LINK_ID}" 64` |
| IAM Policy | 128 | `sanitize_name "${SERVICE_NAME}-${SCOPE_SLUG}-${APP_SLUG}" 128` |
| IAM Role | 64 | `sanitize_name "${SERVICE_NAME}-${SCOPE_SLUG}" 64` |

If you see `"Value at 'userName' failed to satisfy constraint: Member must have length less than or equal to 64"`, the name was not truncated.

## IAM Policy: MalformedPolicyDocument

If you see `"Resource must be in ARN format"`, an ARN is empty. Verify that `build_permissions_context` derives the ARNs correctly.

## IRSA Prerequisites

IAM Roles for Service Accounts (IRSA) only works if:
1. The EKS cluster has an OIDC provider configured
2. The **scope infrastructure creates a dedicated K8s ServiceAccount per app** with an associated IAM role
3. The `app_role_name` attribute is populated in the scope/entity attributes

If the scope doesn't manage per-app ServiceAccounts, IRSA will fail silently (the `app_role_name` will be empty and the `count = var.app_role_name != "" ? 1 : 0` guard will skip the attachment).

Default to **IAM User + Access Keys** for link credential strategy unless the user confirms their scope creates dedicated SAs.
