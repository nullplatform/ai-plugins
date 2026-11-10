---
name: np-service-guide
description: Use when the user asks about creating, understanding, or working with nullplatform services. This is the entry point for all service development tasks — it provides the architecture overview and routes to specialized skills for specs, scripts, terraform, and testing.
---

# Nullplatform Service Development Guide

Entry point for developing nullplatform services. A **service** is a cloud resource (database, cache, storage, messaging, etc.) that is provisioned via terraform and connected to applications via links. Its actions are run either by a nullplatform **agent** (worker from a packaged image) or by the client's **CI** (a GitHub Actions workflow dispatched through a `github` notification channel) — the service code is the same in both; see `np-service-craft`, `docs/execution-modes.md`.

## Critical Rules

1. **ALWAYS invoke the specialized skill** before doing work in that area. This guide provides context; the specialized skills have detailed conventions.
2. **ALWAYS review examples from the reference repository** before creating a new service (see Reference Repository section).
3. **NEVER use `specification_schema`** as a top-level field in specs — always `attributes.schema`.
4. **NEVER write scripts without `set -euo pipefail`** and error handling.
5. **NEVER use `curl` against the API** — always `/np-api fetch-api`.

## Reference Repositories

Each sample service lives in its own repo with independent versioning. **Choose from the docs
table, not by crawling repos**: the **Samples** table of the docs' Sample services page already
gives, per service, its name (with its platform), slug, category and `repo/path` (read it as the catalog explains:
`${CLAUDE_PLUGIN_ROOT}/skills/np-rules/references/scopes-services-catalog.md`). Then clone only the repo that was picked:

```bash
# <repo> and <path> from the table row; <tag> resolved per the catalog (notes 3–3a)
git clone --depth 1 --branch <tag> https://github.com/nullplatform/<repo>.git /tmp/np-<repo>-reference
ls /tmp/np-<repo>-reference/<path>/specs      # path "." = specs at the repo root
```

> A repo can hold more than one service (`services-postgresql-rds` has the server and the
> database): the table lists each one as its own row with its own path.

Do not hardcode the repo structure — always explore dynamically because it can change.

## Routing Table

| Task | Skill |
|------|-------|
| Create/list/register/test services (full cycle) | `np-service-craft` |
| Register or test a service run by GitHub Actions (CI mode) | `np-service-craft` (`register-service-ci.md`) + `np-notification-manager` (github channel) |
| Conventions for service-spec.json.tpl, link specs, values.yaml | `np-service-specs` |
| Conventions for YAML workflows, build_context, do_tofu, entrypoints | `np-service-workflows` |
| Terraform registration (service_definition, bindings) | `np-service-creator` |
| Local agent setup for testing (agent mode only) | `np-agent-local-setup` |
| Notification channel management, github channels | `np-notification-manager` |
| Nullplatform API queries | `np-api` |

## Service Philosophy

### 1. Developer-First Design
- Spec fields should be understandable to a developer who doesn't know the cloud provider
- Example: ask for `storage_size: 100` (GB) instead of `allocated_storage: 100`
- Advanced fields go in `values.yaml`, not in the spec

### 2. Minimal Schema
- Only expose in the spec the fields the developer needs to decide
- Infrastructure settings (VPC, subnets, profiles) go in `values.yaml`
- Fewer fields = fewer errors when creating instances

### 3. Terraform-First Provisioning
- Most services are provisioned with terraform (via do_tofu)
- For REST APIs without a terraform provider, use `null_resource` with provisioners or direct scripts
- Always use remote state per instance (key based on service name)

### 4. Links = Permissions + Credentials
- A link connects an app to a service
- The link workflow executes the permissions module (IAM/RBAC) and optionally generates credentials
- Fields with `export: true` become env vars of the app

## Service Structure

```
services/<service-name>/
+-- specs/
|   +-- service-spec.json.tpl       # UI schema + selectors
|   +-- links/
|       +-- connect.json.tpl        # How apps connect
+-- deployment/
|   +-- main.tf                     # Cloud resources
|   +-- variables.tf, outputs.tf, providers.tf
+-- permissions/
|   +-- main.tf                     # IAM/RBAC for linking
|   +-- locals.tf, variables.tf
+-- workflows/<provider>/
|   +-- create.yaml, delete.yaml, update.yaml
|   +-- link.yaml, link-update.yaml, unlink.yaml, read.yaml
+-- scripts/<provider>/
|   +-- build_context               # Parses context -> env vars
|   +-- do_tofu                     # Runs tofu init + apply/destroy
|   +-- write_service_outputs       # (optional) Writes outputs post-tofu
|   +-- write_link_outputs          # (optional) Writes credentials post-link
|   +-- build_permissions_context   # (optional) Context for permissions module
+-- entrypoint/
|   +-- entrypoint                  # Main router (bridges NP_API_KEY; no-op in CI mode)
|   +-- service                     # Service action handler
|   +-- link                        # Link action handler
+-- values.yaml                     # Static config (region, profiles, etc)
```

## Decision Tree: What Type of Service

```
Who runs the actions? ──Agent──> image + package + agent channel  (np-package-builder, np-agent-local-setup)
  │                    ──CI────> client workflow + github channel (np-notification-manager, register-service-ci.md)
  │   (look at /controlplane/agent and the NRN's channels before asking)
  ▼
Has terraform provider? ──Yes──> Terraform-based service
  │                                (deployment/ with main.tf)
  No
  │
Has REST API? ──Yes──> API-based service
  │                      (scripts/ with do_provision)
  No
  │
Existing resource? ──Yes──> Import service
                             (only specs + link)
```

## Provider-Specific Gotchas

Load only when relevant to the service's provider:

- AWS: see `docs/gotchas-aws.md`
- Azure: see `docs/gotchas-azure.md`
