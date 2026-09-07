# Required Variables

Variables are read from `organization.properties`, `common.tfvars`, and `infrastructure/{cloud}/terraform.tfvars`:

| Variable | Description | Source |
| -------- | ----------- | ------ |
| `organization_id` | Organization ID | organization.properties |
| `account_id` | Nullplatform account ID | Selected via wizard (step 1) |
| `nrn` | Nullplatform Resource Name | common.tfvars |
| `np_api_key` | Nullplatform API key | common.tfvars |
| `organization_slug` | Organization slug. The **only** slug variable — drives cluster and resource names across all clouds. Do not use `var.account` / `var.account_slug` | common.tfvars |
| `tags_selectors` | Tags for agent matching | common.tfvars |

The `nrn` is critical for the Nullplatform modules that consume it (`agent`, `agent_api_key`, and the nullplatform/ and bindings/ layer modules). Without a valid account, the Terraform plan will fail. Note `base` does **not** declare `nrn` — passing it there is an `Unsupported argument`.

## Credential verification by cloud

| Cloud | Command | What to verify |
|-------|---------|----------------|
| AWS | `aws sts get-caller-identity` | Account ID matches tfvars |
| Azure / Azure ARO | `az account show` | Subscription ID matches tfvars |
| GCP | `gcloud config get-value project` + `gcloud config list account` | Project matches `gcp_project_id` in tfvars; account is the intended identity |
| OCI | `oci iam region list` | Tenancy/compartment matches tfvars |
