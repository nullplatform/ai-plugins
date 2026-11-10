# Terraform Patterns Reference

## Source of Truth

Always clone and read the modules before generating terraform, pinned at the ref you will
use in `source`:

```bash
git clone --depth 1 --branch <ref> https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref
```

Files to read:
- `nullplatform/service_definition/variables.tf` — the `package` variable carries the whole
  packaging contract in its own description, plus its two validations
- `nullplatform/service_definition_agent_association/variables.tf` — `worker_orchestrator`,
  `package_slug`, and the `entrypoint` default
- `nullplatform/agent/variables.tf` — `worker_orchestrated_packages`, `worker_k8s_packages`,
  `worker_memory_limit`, `worker`, `worker_ingress`, and the legacy `agent_repo`
- `nullplatform/agent/locals.tf` — how `worker` merges over the computed defaults
  (`patches` and `allowedRegistries` concatenate; everything else replaces)

Do not copy examples from this file as a template — generate the terraform by reading the
module variables and adapting to the specific service.

@${CLAUDE_PLUGIN_ROOT}/skills/np-service-creator/docs/packaged-service.md

## CI mode (service run by GitHub Actions)

No `package` block, no agent association, no agent layer. Two resources, one apply, because
the channel filters by **slug** and does not need the spec's id:

```hcl
module "service_definition_<slug>" {
  source = "github.com/nullplatform/tofu-modules//nullplatform/service_definition?ref=<ref>"
  # repository_org / repository_name / repository_branch (a tag) / repository_token as usual —
  # the module still fetches the spec files over HTTPS. No `package` argument.
  # Read the rest of the variables from the module at <ref>.
}

resource "nullplatform_notification_channel" "service_<slug>" {
  nrn         = var.nrn
  type        = "github"
  source      = ["service"]
  description = "<slug> via <owner>/<repo>"   # max 64 chars
  status      = "active"

  configuration {
    github {
      installation_id = var.github_installation_id   # the GitHub App installation for <owner>
      account         = "<owner>"
      repository      = "<repo>"                     # name only, no owner
      reference       = "<branch or tag>"
      workflow_id     = "<file>.yml"                 # file name under .github/workflows
    }
  }

  filters = jsonencode({
    "service.specification.slug" = { "$eq" = "<slug>" }
  })
}
```

Read the block's attributes from the provider docs at the version you pin
(`docs/resources/notification_channel.md`), not from this snippet. Add `telemetry` to `source`
only if the workflow handles metric notifications, and then use the `$or` filter shape the
agent association module emits (`service.specification.slug` or
`arguments.service_specification.slug`).

Where the values come from — never hardcode a client's: `installation_id` from the
`github-configuration` provider (`/provider/<id>` → `attributes.setup.installation_id`) or
from an existing github channel in the NRN; owner, repo, reference and workflow from the user
or from that same existing channel. `np-notification-manager` already asks for these with
autocompletion; reuse its answers.

Apply order collapses to one directory. After the apply, verify with
`/np-api fetch-api "/notification/channel/<id>"` and run the manager's `inspect`.

## Apply Order (agent mode)

Unchanged by packaging — `nullplatform-bindings/` still reads the spec slug out of
`nullplatform/` through remote state, so the order stands:

```bash
# 1. tag, build + push the image, capture the digest
docker buildx imagetools inspect <registry>/<repo>:<tag> --format '{{.Manifest.Digest}}'

# 2. specs + package revision
cd nullplatform && tofu init && tofu apply -var-file=../common.tfvars

# 3. the package-exec channel
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../common.tfvars

# 4. the agent layer, for worker_orchestrated_packages + allowedRegistries
```

## Local vs remote

`git_provider = "local"` versus `"github"` decides **where the module fetches spec files
from**. It still applies in packaged mode: the module reads the specs over HTTPS on every
apply regardless of the image, so a private repo still needs `repository_token`.
