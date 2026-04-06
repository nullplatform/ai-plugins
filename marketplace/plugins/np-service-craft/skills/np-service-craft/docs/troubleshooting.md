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

# Check agent is registered
/np-api fetch-api "/controlplane/agent"
```
