# Metadata specifications (catalog). One per entry of metadata.json, which holds
# only the specifications the user selected in the wizard. The key of each entry
# is the metadata key; schema is a JSON object, encoded here.
resource "nullplatform_metadata_specification" "this" {
  for_each = jsondecode(file("${path.module}/metadata.json"))

  nrn = var.nrn

  entity      = each.value.entity
  metadata    = each.key
  name        = each.value.name
  description = each.value.description
  schema      = jsonencode(each.value.schema)
}
