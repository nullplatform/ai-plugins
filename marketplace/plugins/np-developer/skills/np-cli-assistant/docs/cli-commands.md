# CLI Command Reference

Source of truth for what is and isn't supported by the `np` CLI. Detailed per-resource commands and flags are in `resources/`.

## Resource Reference

| Resource | Commands | Reference |
|----------|----------|-----------|
| [account](resources/account.md) | 5 | create, delete, list, read, update |
| [application](resources/application.md) | 6 | create, current, list, patch, read, update |
| [approval](resources/approval.md) | 18 | actions, policies, is_required |
| [asset](resources/asset.md) | 4 | create, list, push, read |
| [build](resources/build.md) | 8 | asset-url, create, list, patch, read, start, update |
| [deployment](resources/deployment.md) | 4 | create, list, patch, read |
| [dimension](resources/dimension.md) | 11 | CRUD + dimension values |
| [link](resources/link.md) | 22 | links, link actions, link specifications |
| [namespace](resources/namespace.md) | 4 | create, list, read, update |
| [parameter](resources/parameter.md) | 12 | CRUD + values, versions |
| [provider](resources/provider.md) | 12 | CRUD + categories, specifications |
| [scope](resources/scope.md) | 22 | scopes, actions, dimensions, domains, types, specifications |
| [service](resources/service.md) | 31 | services, actions, specifications, workflows, service-action |
| [misc](resources/misc.md) | 50+ | action, agent, api-key, authz, entity-hook, log, metadata, notification, nrn, organization, release, runtime-configuration, template, token, user, version |

**241 commands across 30 resources** (discovered from np CLI v2.4.2).

## Installation

### Linux / macOS

```bash
# Latest version
curl https://cli.nullplatform.com/install.sh | sh

# Specific version
curl https://cli.nullplatform.com/install.sh | VERSION=<n.n.n> sh

# Verify
np --version
```

### Windows

```powershell
# PowerShell (recommended)
Invoke-WebRequest -Uri https://cli.nullplatform.com/install.ps1 -OutFile install.ps1; .\install.ps1
```

```cmd
# Command Prompt
curl -o install.bat https://cli.nullplatform.com/install.bat
install.bat
```

After installation, restart the terminal so the PATH changes take effect.

## Authentication

Before running any command, the CLI must be authenticated. Two methods are supported:

### API key (recommended for CI/CD)

```bash
# Recommended: add to ~/.zshrc or ~/.bashrc for persistence
export NULLPLATFORM_API_KEY='your_api_key_here'

# Or pass as a flag per command
np [command] --api-key your_api_key
```

Generate API keys in the nullplatform UI under Settings → API Keys.

### Access token (personal use)

```bash
# As an environment variable
export NP_TOKEN='your_access_token'

# Or pass as a flag per command
np [command] --access-token your_access_token
```

To get your personal access token: log in to nullplatform → click your user avatar (top-right) → **Copy personal access token**.

## Command Syntax

```
np <resource> <action> [--flag value] [--flag value]
```

Resources map to API path segments. Actions map to HTTP methods:

| Action | HTTP method | Notes |
|--------|-------------|-------|
| `list` | GET (collection) | |
| `read` | GET (single item) | Usually requires `--id` |
| `create` | POST | |
| `update` | PATCH/PUT | |
| `delete` | DELETE | |
| `push` | POST | Asset deployment |
| `start` | POST | Build trigger |

## Useful Flags (available on all commands)

| Flag | Description |
|------|-------------|
| `--api-key` | API key for authentication |
| `--access-token` | Access token for authentication |
| `--format json` | Output response as JSON |
| `--help` | Show available flags for a command |

## Unsupported Operations

These operations have no `np` CLI equivalent. Explain the limitation and provide the API/cURL alternative when asked. Resource-specific unsupported operations are also listed in each resource file.

| Operation | Notes |
|-----------|-------|
| `action-context generate` | Use API instead |
| `application delete` | Use `DELETE /application/:id` |
| `approval approve` | Use `POST /approval/approve` |
| `approval deny` | Use `POST /approval/deny` |
| `asset patch` | Use `PATCH /asset/:id` |
| `asset replace` | Use `PUT /asset/:id` |
| `asset update` | Use `PUT /asset/:id` |
| `user grant bulk` | Use `POST /user/:id/grant` |
| `user grant list` | Use API instead |
| `user grant update` | Use API instead |
| `authz user-role list` | Use API instead |
| `metadata specification create` | Use API instead |
| `metadata specification delete` | Use API instead |
| `metadata specification list` | Use API instead |
| `metadata specification patch` | Use API instead |
| `metadata specification read` | Use API instead |
| `metadata specification update` | Use API instead |
| `metadata update` | Use `PATCH /metadata/:id` |
| `namespace delete` | Use `DELETE /namespace/:id` |
| `notification list` | Use `GET /notification` |
| `notification read` | Use `GET /notification/:id` |
| `notification resend` | Use `POST /notification/resend` |
| `organization patch` | Use `PATCH /organization/:id` |
| `parameter patch` | Use `PATCH /parameter/:id` |
| `parameter value compare` | Use API instead |

## Gotchas

- **Comma-separated filter limits**: flags like `--namespace_id`, `--account_id`, and `--application_id` accept up to 10 comma-separated values. Exceeding this silently truncates — no error or warning. Batch in chunks of 10.
- **Authentication variable**: Both the `np` CLI and the skill's scripts read `NULLPLATFORM_API_KEY` as the primary variable. `NP_API_KEY` and `NP_TOKEN` are supported as fallbacks. When generating scripts for users, always use `NULLPLATFORM_API_KEY`.
- **Flags are resource-specific**: do not assume a flag from one resource works in another. Check the resource file or run `np <resource> <action> --help`.

## Efficient Search Strategies

When searching for resources across a broad scope (e.g., "find all apps with links in this account"), use higher-level NRNs with `--show_descendants` instead of iterating through each child entity individually.

**Pattern: Account-level or namespace-level search**

```bash
# Instead of iterating 100+ namespaces one by one:
#   for ns in $NAMESPACES; do np link list --nrn "...namespace=$ns" ...; done

# Use a single call at the account level:
np link list \
  --nrn "organization=<org_id>:account=<account_id>" \
  --show_descendants \
  --limit 200 \
  --format json
```

This returns all links across all namespaces and applications in the account in one request. Group the results by `entity_nrn` to identify which application each link belongs to.

> This strategy works with any command that supports `--nrn` and `--show_descendants` (e.g., `link list`, `deployment list`).

## Dynamic OpenAPI Commands

The CLI dynamically generates additional commands from OpenAPI specs embedded in the binary. These cover:

- `api-spec.yml` — core entities (applications, scopes, releases, deployments)
- `approval.yml` — approval workflows
- `authentication.yml` — API keys and tokens
- `authorization.yml` — user roles and grants
- `controlplane.yml` — deployments, releases, scopes
- `entity-hooks.yml` — entity hooks
- `notifications.yml` — notifications (mostly unsupported — see above)
- `parameters.yml` — parameter management
- `scope.yml` — scope management
- `services-api.yml` — service management
- `users.yml` — user management

For dynamic commands, the user can run `np --help` or `np <resource> --help` to discover available subcommands.
