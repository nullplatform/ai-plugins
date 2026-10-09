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

## Apply Order

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
