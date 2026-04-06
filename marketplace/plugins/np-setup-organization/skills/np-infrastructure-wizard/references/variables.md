# Required Variables

Variables are read from `organization.properties`, `common.tfvars`, and `infrastructure/{cloud}/terraform.tfvars`:

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `organization_id` | Organization ID | organization.properties |
| `account_id` | Nullplatform account ID | Selected via wizard (step 1) |
| `nrn` | Nullplatform Resource Name | common.tfvars |
| `np_api_key` | Nullplatform API key | common.tfvars |
| `organization_slug` | Organization slug | common.tfvars |
| `tags_selectors` | Tags for agent matching | common.tfvars |

The `nrn` is critical for Nullplatform modules (base, agent). Without a valid account, the Terraform plan will fail.

## Credential verification by cloud

| Cloud | Command | What to verify |
|-------|---------|----------------|
| AWS | `aws sts get-caller-identity` | Account ID matches tfvars |
| Azure / Azure ARO | `az account show` | Subscription ID matches tfvars |
| GCP | `gcloud config list account` | Project matches tfvars |
| OCI | `oci iam region list` | Tenancy/compartment matches tfvars |
