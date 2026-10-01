---
name: np-api
description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/*.sh)
---

# np-api

Skill to explore and query the Nullplatform API.

## Command: $ARGUMENTS

## Pre-flight: project context (`.np/`)

Do this once per session, before the first API call, whenever this skill is
triggered. It is read-only and silent when there is nothing to load.

1. Resolve the project root: `git rev-parse --show-toplevel`, or the current
   directory outside a git work tree.
2. If `<root>/.np/` exists, read every file in it into context:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh load
   ```

   Without the script: `cat <root>/.np/*`. Any file counts; nothing is validated.
3. If `.np/application.yaml` is present, its `nullplatform.*` values are the
   session defaults: `application_id`, `namespace_id`, `account_id`,
   `base_url`. Use them directly. Do not ask "which application?" and do not
   walk organization → account → namespace to find out.
4. **`.np/` is guidance, not a lock.** When the user names another
   application, namespace, account or organization in the session, follow the
   user for that task.
5. If there is no `.np/`, nothing happens and nothing is suggested up front.
   The only moment to offer it is after a task has resolved a concrete
   application (the user gave its id, its UI link or its name and you fetched
   it). Then run:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh match-app <application_id>
   ```

   Exit 0 means this repository's git remote is that application's
   repository (and, for monorepos, the current directory is its
   `repository_app_path`). Only then, and once per session, offer: *"This
   repository is `<slug>` (`<id>`). Want me to save that as
   `.np/application.yaml` so future sessions start here?"* On a yes, continue
   with `context init` from step 3 using that id. Exit 1 or 2 (different
   repository, no remote, application not found): say nothing about `.np/`.
   Never offer on a guess, and never run `discover` just to find out.

Reference (file layout, schema, troubleshooting):
`@${CLAUDE_PLUGIN_ROOT}/skills/np-api/docs/project-context.md`

## Available Commands

| Command | Purpose |
|---------|---------|
| `/np-api` | Entity map and relationships |
| `/np-api check-auth` | Verify authentication with Nullplatform |
| `/np-api search-endpoint <term>` | Search endpoints by term |
| `/np-api describe-endpoint <endpoint>` | Complete endpoint documentation |
| `/np-api fetch-api <url>` | Execute API request |
| `/np-api context` | Show the project context loaded from `.np/` |
| `/np-api context init [<ui-link> \| <application-id>]` | Generate `.np/application.yaml` for this repository |

---

## If $ARGUMENTS is "context" → Show Project Context

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh load
```

Show the output. Exit code 3 means there is no `.np/` directory: say so and
mention `/np-api context init`.

---

## If $ARGUMENTS starts with "context init" → Generate `application.yaml`

Goal: write `<root>/.np/application.yaml` for the application this repository
belongs to. The script never prompts; the questions below are yours.

**Step 1 — Hints from the git remote.** Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh discover
```

It normalizes the remote URL and queries `/application?repository_url=`. Output
is JSON: `candidates` (applications whose repository is this remote) and
`match` (the id when exactly one candidate fits, or `null`). No remote, no
git repo or zero candidates is not an error: the hint list is just empty.

**Step 2 — Ask which application.** Skip this step if the user passed a UI
link or an application id as the argument. Otherwise ask with
`AskUserQuestion`, one question:

- One option per candidate, labelled `<name> (<id>)`. If `match` is set, put
  that candidate first with `(Recommended)`.
- The user can always answer "Other" with a nullplatform UI link
  (`https://<org>.app.nullplatform.io/account/<a>/namespace/<n>/application/<id>`,
  any trailing route is fine) or a bare application id.

An answer that is neither a candidate, a link, nor a number: say it was not
understood and ask again.

**Step 3 — Generate.** With an id: `np-context.sh init --app <id>`. With a
link: `np-context.sh init --link "<link>"`. The script fetches the
application, takes account/namespace from its NRN, derives `base_url` from
the link, else `NP_LOGIN_URL`, else the organization slug, and prints the
YAML. Exit code 1 means the application does not exist or is not accessible:
stop and say so.

**Step 4 — Confirm, then write.** Show the YAML and ask the user to confirm.
Only after a yes, re-run the same command with `--write`. If the file already
exists with different content the script exits 4 without touching it: show
the difference, ask again, and use `--write --force` only if the user agrees.

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

## Catalog questions belong to `/np-catalog`

`api.nullplatform.com/catalog` is a different surface from the control plane documented
here: schema-driven specifications and instances, with facets, relevance ranking over
prose, and relation traversal. Those need method selection this skill does not cover,
and reading them the wrong way fails silently rather than erroring.

Route to **`/np-catalog`** whenever the question is about catalog records — "give me the
deployment analysis", "what shipped last month", "which records mention X", "how should
I model this as specifications and relations" — even when the user never says "catalog".
This skill still owns the control plane: applications, scopes, deployments, builds,
releases, services, notifications, parameters.

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
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh <load\|remote-url\|parse-link\|discover\|match-app\|init>` | Project context (`.np/`) and application discovery by git remote |

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
