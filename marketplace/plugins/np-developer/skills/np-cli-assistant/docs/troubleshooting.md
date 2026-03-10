# CLI Assistant — Troubleshooting

## User asks about a command not in the docsite

**Cause:** Command may be internal tooling not exposed to customers.
**Solution:** Do not surface it. Say: "That command is not part of the customer-facing CLI."

## CLI flag names differ from what user expects

**Cause:** CLI flag names may differ from API field names.
**Solution:** Recommend the user run `np <resource> <action> --help` to see exact flag names. Do not guess flag names from memory or API conventions.

## Assumed a flag from one resource works in another (e.g., `--nrn` in `application list`)

**Cause:** Some flags like `--nrn` appear in examples for one resource but are not universal.
**Solution:** Always check [cli-commands.md](cli-commands.md) for known flags first. If not listed, recommend running `np <resource> <action> --help`. Never assume flag availability across resources.

## Command not found in `cli-commands.md`

**Cause:** `cli-commands.md` is a partial reference. The CLI generates dynamic commands from OpenAPI specs not fully enumerated there.
**Solution:** Do NOT declare the command unsupported. The user can run `np --help` and `np <resource> --help` to check. Only after confirming the command doesn't appear there should you suggest the API alternative.

## Operation exists in the API but not the CLI

**Cause:** CLI coverage lags behind API capabilities.
**Solution:** If a command is in the unsupported list and not found via `np --help`, provide the cURL/API equivalent. Include the documentation link.

## Authentication fails (401)

**Cause:** No credentials configured, token expired, API key invalid, or env vars not visible in non-interactive shells.
**Solution:** Guide the user through these steps:

1. **Check credentials are set**: `echo $NULLPLATFORM_API_KEY` (should not be empty)
2. **Check token isn't expired**: if using `NP_TOKEN`, personal tokens expire in ~24h
3. **Try inline auth**: `np <command> --api-key your_api_key` (bypasses env var lookup)
4. **Regenerate if needed**: nullplatform UI → Settings → API Keys

**Important:** The `np` CLI uses `NULLPLATFORM_API_KEY` (not `NP_API_KEY`). Using the wrong variable name is a common mistake.

## CLI returns 401 despite valid API key — expired `NP_TOKEN` in shell profile

**Cause:** The `np` CLI prioritizes `NP_TOKEN` over `NULLPLATFORM_API_KEY`. If an expired JWT token is set in `~/.zshrc`, the CLI uses it instead of the valid API key, resulting in 401 errors.
**Solution:** Remove the expired token:
- **macOS**: `sed -i '' '/export NP_TOKEN/d' ~/.zshrc && source ~/.zshrc`
- **Linux**: `sed -i '/export NP_TOKEN/d' ~/.bashrc && source ~/.bashrc`

Then retry the CLI command.

## Setting environment variables by platform

- **macOS (zsh)**: `echo 'export NULLPLATFORM_API_KEY=your-key' >> ~/.zshrc && source ~/.zshrc`
- **Linux (bash)**: `echo 'export NULLPLATFORM_API_KEY=your-key' >> ~/.bashrc && source ~/.bashrc`
- **Windows (PowerShell)**: `[System.Environment]::SetEnvironmentVariable('NULLPLATFORM_API_KEY','your-key','User')` — then restart the terminal
- **Windows (Git Bash / WSL)**: same as Linux

For current session only (no persistence): `export NULLPLATFORM_API_KEY='your-key'` (Unix) or `$env:NULLPLATFORM_API_KEY = 'your-key'` (PowerShell).

## `np` CLI not installed

**Cause:** The `np` binary is not in the user's PATH.
**Solution:** Guide the user to install it:
- Linux/macOS: `curl https://cli.nullplatform.com/install.sh | sh`
- Windows: `Invoke-WebRequest -Uri https://cli.nullplatform.com/install.ps1 -OutFile install.ps1; .\install.ps1`

After installation, restart the terminal so the PATH changes take effect. Verify with `np --version`.

## 401 Unauthorized on a resource that exists

**Cause:** Token belongs to a different organization than the target resource.
**Solution:** Compare the organization in the token with the `organization=` segment in the resource's NRN. If they differ, the user needs a token or API key scoped to the target organization.

## Command returns fewer results than expected

**Cause:** Comma-separated filter flags (e.g., `--namespace_id`) silently truncate beyond their limit (typically 10 values). The CLI does not warn or error.
**Solution:** Batch the filter values into chunks of 10 and iterate. Combine results client-side. See Example 7 in [examples.md](examples.md) for a template.

## Links reference applications that return 404

**Cause:** Links can persist after the owning application is deleted. When resolving app names via `np application read --id <id>`, deleted apps return 404.
**Solution:** Handle 404s gracefully — display the application ID instead of the name. The app may have been deleted. If looking for a specific number of accessible apps, keep iterating past 404s until the target count is reached.
