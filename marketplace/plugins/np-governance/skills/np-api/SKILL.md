---
name: np-api
description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/*.sh)
---

# np-api

Skill to explore and query the Nullplatform API.

## Command: $ARGUMENTS

## Available Commands

| Command | Purpose |
|---------|---------|
| `/np-api` | Entity map and relationships |
| `/np-api check-auth` | Verify authentication with Nullplatform |
| `/np-api search-endpoint <term>` | Search endpoints by term |
| `/np-api describe-endpoint <endpoint>` | Complete endpoint documentation |
| `/np-api fetch-api <url>` | Execute API request |

---

## If $ARGUMENTS is "check-auth" → Verify Authentication

Run the verification script:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh
```

Show the result to the user. If it fails, indicate the options.

Authentication is resolved in this precedence (env/`.env` always win; the
`np login` session is the fallback when no env var is set):

1. **`NP_API_KEY`** env var
2. **`NP_TOKEN`** env var
3. **`np login` session** — picked up automatically via `np token get`

**RECOMMENDED for CI/agents: NP_API_KEY (doesn't expire, token cached in ~/.claude/)**

```bash
export NP_API_KEY='your-api-key'
```

1. Go to Nullplatform UI -> Platform Settings -> API Keys
2. Create new API Key for the organization
3. Add `export NP_API_KEY='...'` to `~/.zshrc` or `~/.bashrc`

**Alternative: NP_TOKEN (expires in ~24h)**

```bash
export NP_TOKEN='eyJ...'
```

1. Go to the Nullplatform UI
2. Click on your profile (top right corner)
3. Click on "Copy personal access token"

**Interactive: np login (browser SSO, stores an auto-renewed refresh token)**

When no env var is set and the `np` CLI is installed, the skill uses the session
established by `np login`. The guidance adapts to the CLI state:

- **CLI not installed** → suggests installing it (`curl https://cli.nullplatform.com/install.sh | bash`)
- **CLI too old** (no `np login`/`np token get`) → suggests `np upgrade`
- **CLI present, not logged in** → suggests logging in:

```bash
np login --np-url https://<your-org>.app.nullplatform.io   # or set NP_LOGIN_URL
```

This opens the browser for company SSO, stores a refresh token locally
(OS keyring, or `~/.np`), and this skill then picks it up automatically —
no token copy/paste needed. Ideal for interactive/agent sessions.

**Selecting a profile:** `np login` can store several profiles. Set
`NP_PROFILE=<name>` (default `default`) and the skill targets that profile's
session automatically — `NP_PROFILE=prod` and the `np token get` fallback both
resolve the same profile. Log a profile in with `np login --np-url ... --profile prod`.

---

## If $ARGUMENTS starts with "search-endpoint" → Search Endpoints

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh search-endpoint <term>
```

Shows a list of endpoints containing the searched term.

---

## If $ARGUMENTS starts with "describe-endpoint" → Endpoint Documentation

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh describe-endpoint <endpoint>
```

Shows complete endpoint documentation: parameters, response, navigation, examples.

---

## If $ARGUMENTS starts with "fetch-api" → API Request

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api <url>
```

Returns the JSON response from the API.

---

## If $ARGUMENTS starts with "resend-notification" → Redirect

> **Moved**: The resend-notification command was moved to `/np-service-craft resend-notification <id> [channel_id]`
> because it requires the admin API key (from `secrets.tfvars`), not the troubleshooting key from np-api.

Inform the user to use `/np-service-craft resend-notification <id> [channel_id]` instead.

For **searching** notifications and **viewing results** (read-only, doesn't require admin):

```bash
# Search notifications
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api "/notification?nrn=<nrn_encoded>&source=service"

# View delivery result per channel
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api "/notification/<id>/result"
```

---

## If $ARGUMENTS is empty → Show Entity Map

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh
```

Shows the Nullplatform entity map and hierarchy.

---

## Recommended Flow

To explore the API safely:

1. **First**: `/np-api` to see the entity map
2. **Second**: `/np-api search-endpoint <term>` to find the endpoint
3. **Third**: `/np-api describe-endpoint <endpoint>` to see the documentation
4. **Fourth**: `/np-api fetch-api <url>` to execute the request

### Checklist before fetch-api

- [ ] Did I run `search-endpoint` to confirm the endpoint exists?
- [ ] Did I run `describe-endpoint` to know the valid parameters?
- [ ] Am I using documented parameters, not inferred ones?

---

## Anti-patterns (DO NOT do)

| Bad | Why | Good |
|-----|-----|------|
| `fetch-api "/scope/123"` directly | You're assuming the endpoint exists | First `search-endpoint scope` |
| `fetch-api "/scope?application_id=X"` | You're assuming query params | First `describe-endpoint /scope` |
| Inferring endpoints from JSON responses | The API may not follow REST conventions | Always verify with `search-endpoint` or `describe-endpoint` |

---

## Additional Scripts

| Script | Purpose |
|--------|---------|
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh <url>` | Direct API fetch |
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/deploy-agent-dump.sh <deployment_id>` | K8s dump of deployment |
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/scope-agent-dump.sh <scope_id>` | K8s dump of scope |
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/agent-kubectl.sh <get\|logs> -- <args>` | Read-only kubectl get/logs via agent |

---

## Document New Endpoints

When you discover a new endpoint or the user asks to document it:

1. Edit the corresponding `.md` file in `docs/` (or create a new one)
2. Add a section with this format:

```markdown
## @endpoint /path/to/endpoint

Brief description of what it does.

### Parameters
- `param1` (path|query, required|optional): Description

### Response
- `field1`: Description
- `field2`: Description

### Navigation
- **→ entity**: `field` → `/other/endpoint`
- **← from**: `/endpoint?filter={id}`

### Example
\```bash
np-api fetch-api "/path/to/endpoint/123"
\```

### Notes
- Non-obvious behaviors
- Common errors
```

The CLI detects `## @endpoint` as a marker and extracts the documentation automatically.

---

## Generate Session Report

When the user asks "generate an np-api report" or "np-api report":

### Step 1: Extract conversation activity

Review the entire conversation and extract:

- User prompts (summarized)
- `/np-api` calls (complete command)
- Results of each call (success/failure)
- Decisions made based on results

### Step 2: Generate activity table

| Secs | Action | Content | Successful |
|------|--------|---------|------------|
| 0 | prompt | User prompt summary | - |
| N | np-api | Executed command | ✓ / ✗ |

### Step 3: Analyze errors

For each failed call:

- **Command**: What was executed
- **Result**: What it returned
- **Cause**: Why it failed (user error vs documentation error)
- **Suggested fix**: If documentation error, indicate file, line, and specific change

### Step 4: Generate improvement suggestions

List of changes to docs/*.md with format:

- [ ] file.md:line - Description of change
