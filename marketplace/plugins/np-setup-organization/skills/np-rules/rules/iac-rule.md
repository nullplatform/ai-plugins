### Rule: Infrastructure changes only via IaC

**NEVER create, modify, or destroy cloud resources (AWS/Azure/GCP/OCI) or nullplatform
entities modeled in Terraform outside of the project's IaC code.** Every change goes
through `tofu/terraform plan` + `apply` against the repo's modules (`infrastructure/`,
`nullplatform/`, `nullplatform-bindings/`, `services/`, `scopes/`).

**Allowed (read-only, unrestricted)**:
- `kubectl get/describe/logs/top`, `kubectl exec` only for read-only commands inside the
  pod (`ls`, `cat`, `grep`, `curl` to GET endpoints — never `curl -X POST/PUT/DELETE`)
- `aws describe-*`, `aws * list-*`, `gcloud * describe`, `az * show`, `az * list`
- `/np-api fetch-api` without `--method` (GET by default), or with `--method` only on
  endpoints explicitly allowlisted by the `np-api` skill (governance action items,
  notification resend, agent_command, lake query)
- `np-lake` SQL queries (read-only by construction)
- Reading TF state (`tofu show`, `tofu state list`)

**Not covered by this rule — operate normally** (workflow-managed entities, not TF-modeled):
scopes, deployments, parameters, builds, releases, service/link instances, assets. These
are created and mutated through registered nullplatform workflows (themselves modeled in
TF), typically via `np-developer-actions` or the API.

**Prohibited (requires going through TF code)**:
- `kubectl edit/patch/apply -f/delete/replace`, `kubectl cp` against agent pods
- `aws/gcloud/az/oci` CLI create/delete/put/modify/update subcommands
- `POST`/`PATCH`/`DELETE` ad-hoc against `api.nullplatform.com` on entities modeled in TF
  (service_specifications, scope_types, notification_channels, bindings, dimensions)
- `np` CLI write subcommands that bypass registered workflows
- `helm install/upgrade/uninstall` outside of the corresponding TF module

**Correct sequence for applying TF**: always `tofu plan` first, show the diff to the user
(add/change/destroy counts + resources that change), wait for confirmation, and only then
propose `tofu apply` in a follow-up message. Never `plan + apply` in a single run.

**Why**: a live patch disappears on the next rollout and leaves the runtime out of sync
with the repo. If something cannot be expressed in TF yet, that is a gap to close in the
modules — not a reason to mutate by hand.

**Exceptions**: require explicit user authorization ("yes, go ahead and do this manually")
and must be recorded in a PLAN or gotcha in the corresponding repo, explaining why the
runtime diverges from the code.
