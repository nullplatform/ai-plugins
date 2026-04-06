# Variables Requeridas

Las variables se leen de `organization.properties`, `common.tfvars` y `infrastructure/{cloud}/terraform.tfvars`:

| Variable | Descripcion | Origen |
| -------- | ----------- | ------ |
| `organization_id` | ID de la organizacion | organization.properties |
| `account_id` | ID del account en Nullplatform | Seleccionado via wizard (paso 1) |
| `nrn` | Nullplatform Resource Name | common.tfvars |
| `np_api_key` | API key de Nullplatform | common.tfvars |
| `organization_slug` | Slug de la organizacion | common.tfvars |
| `tags_selectors` | Tags para matching de agente | common.tfvars |

El `nrn` es critico para los modulos de Nullplatform (base, agent). Sin un account valido, el plan de Terraform fallara.

## Verificacion de credenciales por cloud

| Cloud | Comando | Que verificar |
|-------|---------|---------------|
| AWS | `aws sts get-caller-identity` | Account ID coincide con tfvars |
| Azure / Azure ARO | `az account show` | Subscription ID coincide con tfvars |
| GCP | `gcloud config list account` | Project coincide con tfvars |
| OCI | `oci iam region list` | Tenancy/compartment coincide con tfvars |
