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

## IAM Policy: MalformedPolicyDocument

If you see `"Resource must be in ARN format"`, an ARN is empty. Verify that `build_permissions_context` derives the ARNs correctly.
