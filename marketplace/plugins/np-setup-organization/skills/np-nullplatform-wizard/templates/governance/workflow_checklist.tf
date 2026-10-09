# Governance cases (approval checklists + the workflows that resolve them).
#
# Each case lives in governance/<slug>/ with an apply.sh (creates/updates the
# resources through the API) and a destroy.sh (removes them). This file only
# orchestrates them: enable cases with var.governance_cases and choose where
# they apply with var.governance_nrn.
#
# Two null_resource per case, on purpose:
#   - governance_case  : anchors the lifecycle (NRN + directory). Only runs
#                        destroy.sh, when the case is disabled or on `tofu destroy`.
#   - governance_apply : runs apply.sh. Replaced whenever the case files change;
#                        apply.sh is idempotent, so that only updates what differs.
# With a single resource, any JSON change would replace it: destroy.sh would
# delete the approval actions and the gate would be off until apply.sh ran again.
#
# Credentials: the scripts read NP_API_KEY from ../common.tfvars (same file as
# this layer) unless exported. It is not passed from tofu so it never lands in
# the state and the script output is not suppressed as sensitive.
#
# Requires curl and jq wherever tofu runs. The hashicorp/null provider is
# resolved implicitly; no change to versions.tf needed.

variable "governance_cases" {
  description = "Governance cases to apply. Each one is a governance/<slug>/ directory with apply.sh and destroy.sh (prod_deploy_gate, nonprod_sizing)."
  type        = list(string)
  default     = []
}

variable "governance_nrn" {
  description = "NRN where the governance cases are created (checklists, approval actions, workflow trigger). Default: var.nrn. Can be more specific, e.g. a namespace."
  type        = string
  default     = null
}

locals {
  governance_nrn   = coalesce(var.governance_nrn, var.nrn)
  governance_cases = { for slug in var.governance_cases : slug => "governance/${slug}" }
}

resource "null_resource" "governance_case" {
  for_each = local.governance_cases

  triggers = {
    nrn = local.governance_nrn
    dir = each.value
  }

  lifecycle {
    precondition {
      condition     = fileexists("${each.value}/apply.sh") && fileexists("${each.value}/destroy.sh")
      error_message = "Governance case '${each.key}' is enabled in governance_cases but governance/${each.key}/{apply.sh,destroy.sh} does not exist."
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers.dir
    command     = "./destroy.sh --yes"
    environment = {
      NP_NRN = self.triggers.nrn
    }
  }
}

resource "null_resource" "governance_apply" {
  for_each = local.governance_cases

  triggers = {
    case  = null_resource.governance_case[each.key].id
    files = sha1(join("", [for f in sort(fileset(each.value, "*")) : filesha1("${each.value}/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = each.value
    command     = "./apply.sh"
    environment = {
      NP_NRN = local.governance_nrn
    }
  }

  depends_on = [module.dimensions]
}

output "governance_cases" {
  description = "Governance cases applied and the NRN they live in."
  value = {
    nrn   = local.governance_nrn
    cases = keys(local.governance_cases)
  }
}
