# Troubleshooting

Consolidated troubleshooting for service development and testing.

## Agent Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| FATAL "bind: address already in use" | Port 8080 occupied | Free the port before starting agent |
| Agent prints help and exits | Missing `-runtime host` | Add the flag (required) |
| "Malformed API key" | Key not in `base64.base64` format | Verify key from UI |
| WebSocket disconnects | Network, token expired | Agent auto-reconnects (1s-20s backoff) |
| Heartbeat 404 | Server evicted agent | Agent auto-re-registers |

## Path & Execution Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| "command not found in any allowed paths" | Script not in basepath | Verify symlink/clone in `~/.np/` |
| "symlink points outside allowed paths" | Target outside basepaths | Add folder with `-command-executor-command-folders` |
| Entrypoint fails silently (exit 1, no output) | SERVICE_PATH relative doesn't resolve | Entrypoint must resolve with `~/.np/` fallback |
| CWD different than expected | Agent child inherits CWD from np-agent start dir | Use absolute paths or fallback pattern |

## Authentication Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| "please login first" | `NULLPLATFORM_API_KEY` not set | Add bridge `NP_API_KEY -> NULLPLATFORM_API_KEY` in entrypoint |
| "np: command not found" in write_outputs | np CLI not in PATH or NULLPLATFORM_API_KEY missing | Verify bridge and np installation |

## Notification & Routing Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Notification delivered but script doesn't run | Agent tags don't match channel selector | Compare `--tags` with `tags_selectors` in binding |
| "There is not a channel for the given parameters" | NRN mismatch between service_definition and binding | Ensure both use same NRN |
| Notification status "success" but script failed | "success" = dispatch succeeded, not script | Check `/notification/<id>/result` for exitCode |

## CI mode (github channel)

| Problem | Cause | Solution |
|---------|-------|----------|
| `/notification/<id>/result` is 204 but no run appears | 204 only means GitHub accepted the dispatch. The GitHub App is not installed on that repo, the workflow is disabled, or `reference` does not exist | `gh run list -R <owner>/<repo> --workflow <file> --branch <ref>`; `/np-notification-manager inspect <id>` validates repo, ref and workflow |
| `/result` is 422 | Payload too large for `workflow_dispatch` inputs, or the input name differs from the workflow's | Check the workflow's `inputs:` name; trim what the spec exports if the context is huge |
| `/result` is 404 | Wrong `account`/`repository`/`workflow_id`, or the App has no access to the repo | Fix the channel config; confirm the App installation covers the repo |
| Run is green, service stays `pending` | The handler never called `np service action update --results` (or `np link action update`) | Add the update call; ensure the run fails loudly on error (`set -euo pipefail`) |
| Run fails with "please login first" | `NULLPLATFORM_API_KEY` secret missing or not exported to the step | Export it at job or step level; the bridge does nothing here |
| Two runs per action | Two active channels match the spec (often one with an empty filter) | List channels for the NRN; fix or delete the broad one |
| Run cannot find the module | Repo layout does not match what the runner expects (`get-exec-path` → `<base>/<slug>/service`) | Add the slug directory, or point `--base-path` at the right folder |
| Run authenticated to the wrong cloud account | Job runs outside the GitHub Environment that holds that account's OIDC role | Derive the Environment from the context (account, namespace, dimensions) before the job that runs tofu |

## Script Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| jq parse error in build_context | VALUES is file path, not JSON | Use `yaml_value()` to read VALUES |
| Empty attributes on create | `.service.attributes` empty on first action | Merge with `.parameters`: `(.service.attributes // {}) * (.parameters // {})` |
| "MalformedPolicyDocument: Resource must be in ARN format" | ARN variable empty | Derive ARNs from resource names, don't read from attributes |
| app_role_name empty in permissions | No deployed app with IAM role (local testing) | Make `app_role_name` optional: `count = var.app_role_name != "" ? 1 : 0` |

## Link Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Link pending, no action created | `use_default_actions` only creates specs, not instances | Create action manually: `POST /link/{id}/action` |
| Link spec schema empty in API | Used `specification_schema` instead of `attributes.schema` | Move schema inside `attributes.schema` in template |
| Parameters not appearing after link | Missing `export: true` on spec fields | Add export config, redeploy spec |
| Some parameters missing (e.g., kms_key_arn) | Field value is empty | NP only creates parameters for non-empty attributes |
| Secret appears as null in API response | Normal for `export: {secret: true}` | Value IS stored, just hidden in API. Check UI parameters |

## Cloud Provider Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| "config profile (X) could not be found" | The agent inherits `AWS_PROFILE` (or other env var) from the shell where it was started, and that profile doesn't exist or isn't correct | Configure the correct profile in `values.yaml`. The `build_context` must always override (without `[ -z ]` check). See `np-service-workflows` docs/build-context-patterns.md |
| Cloud credentials error running tofu | No active cloud session for the configured profile | `aws sso login --profile <name>` or `az login` before starting the agent |
| Scripts create auxiliary resources that fail | The build_context may create resources (e.g., tfstate bucket) that aren't in deployment/main.tf and require extra permissions | Review scripts in addition to terraform to understand all required permissions |
| AWS lifecycle rule "missing filter" | AWS provider requires explicit `filter {}` | Add `filter {}` even when applying to all objects |

## Terraform Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Type inconsistency with link-spec.json.tpl | service_definition module v1.21.0 bug | Upgrade to v1.32.0 |
| `api_key` parameter not found in agent_association | Using v1.32.0 which renamed the parameter | Use v1.21.0 for agent_association |

## Publishing Issues (`services-*` template repos)

| Problem | Cause | Solution |
|---------|-------|----------|
| Public ECR: "does not exist on GitHub, or is private" | Repo born private | Org admin makes it public; run the Public ECR service's `update` |
| Preflight: `AWS_ROLE_ARN_ECR_PUSH` / `NP_ARTIFACT_NRN` missing | Public ECR service not added / variable never set | Add the service (or `update` it); set the variable by hand |
| Image published as `…/my-service` | Template slug never scaffolded | `git mv my-service <slug>` and align `image_name` |
| Every check red on the release-please PR | Bot-opened PR runs are held | Expected; `auto-merge-release` merges it |
| Repo missing from the docs index | Not named `services-*` / `scopes-*`, private, no release yet, template placeholders still in the spec, or the daily sync PR is still pending | Fix the name, visibility or placeholders, cut a first release, then review the sync PR in `nullplatform/docsite` (its summary lists repos skipped for placeholders or without a release). Don't add the row by hand |

## Diagnostic Commands

```bash
# Find notifications for a service
/np-api fetch-api "/notification?nrn=<app_nrn_encoded>&source=service&per_page=5"

# Check notification delivery result
/np-api fetch-api "/notification/<id>/result"

# Resend notification without recreating service
/np-service-craft resend-notification <notification_id>

# Check service spec exists
/np-api fetch-api "/service_specification?slug=<slug>"

# Check agent is registered (agent mode)
/np-api fetch-api "/controlplane/agent"

# CI mode: which channel handles the spec, then the runs it triggered
/np-api fetch-api "/notification/channel?nrn=<nrn>&status=active&limit=100" | jq '(.results // .)[] | select(.type=="github")'
gh run list -R <owner>/<repo> --workflow <workflow_id> --branch <reference> -L 5
```
