---
name: np-organization-create
description: This skill should be used when the user asks to "create an organization", "new nullplatform org", "onboard a new client", "initialize organization", "bootstrap nullplatform", "first-time setup", "set up a new client", "I need to create an org", "setting up nullplatform from scratch", or needs to create a new nullplatform organization via the onboarding API. This is an irreversible operation.
allowed-tools: AskUserQuestion
---

# Nullplatform Organization Create

Creates a new Nullplatform organization via the onboarding API.

## When to Use

- Creating a new Nullplatform organization from scratch
- First step before any infrastructure configuration

## SECURITY RULES

**Creating an organization is an IRREVERSIBLE action.** Proceed with extreme caution.

1. **ALWAYS** show the complete request to the user before executing
2. **ALWAYS** ask for explicit confirmation before executing the POST
3. **ALWAYS** ask if the organization name was validated with stakeholders
4. **ALWAYS** verify each owner email with the user before sending (real invitations are sent)
5. **NEVER** execute the POST without all the above confirmations
6. **ALWAYS** use AskUserQuestion for confirmations and data gathering (batch up to 4 questions per call)
7. **ALWAYS** create and update the state file (`organization-{name}.md`) to survive context compaction
8. The onboarding POST uses `curl` directly — this is the **one exception** to the "never use curl" rule, because `/np-api` authenticates via `NP_API_KEY` env var against `api.nullplatform.com` and cannot exchange a root API key against the onboarding API (`*.nullapps.io`)

## Prerequisites

1. `jq` installed (used for token extraction in Step 6)
2. File `organization-create-api.key` in the project root
   - Contains an API Key with `organization:create` grant on `organization=0` (root)
   - This file is **highly sensitive** and must be in `.gitignore`
   - To obtain it: contact the Nullplatform team
3. Verify that `organization-create-api.key` is in `.gitignore`
4. VPN connectivity (required for `*.nullapps.io`)

## Endpoint

| Field | Value |
|-------|-------|
| URL | `https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization` |
| Method | POST |
| Auth | Bearer token generated from `organization-create-api.key` |
| Content-Type | application/json |

## Body Schema

```json
{
  "organization_name": "org-name",
  "account_name": "account-name",
  "owners": [
    {
      "email": "user@example.com",
      "name": "FirstName",
      "last_name": "LastName"
    }
  ]
}
```

**IMPORTANT**: Owner fields use `snake_case` (`last_name`, NOT `lastName`).

## Workflow

### Step 0: Check existing state

**First**, check if a state file `organization-*.md` exists in the working directory. If it does and phase is not `complete`, resume from the current phase instead of starting over.

**Then**, check if `organization.properties` already contains an `organization_id`.

If it exists:
1. Ask the user if the org was already created or if they need to create a new one
2. If already created → **skip directly to the next step** (`/np-setup-orchestrator`). Do not execute post-creation verification or any other step of this skill.
3. If they need to create a new one → continue with Step 1

### Step 1: Verify prerequisites

```bash
# Verify that organization-create-api.key exists
ls organization-create-api.key

# Verify it's in .gitignore
grep -q "organization-create-api.key" .gitignore && echo "OK" || echo "MISSING from .gitignore"

# Verify VPN connectivity (MANDATORY before any request)
curl -s --max-time 5 -o /dev/null -w "%{http_code}" "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/health" || true
```

**If the health check fails or doesn't respond** → STOP and indicate:

> There is no connectivity to `*.nullapps.io`. Connect to the Nullplatform VPN before continuing.
>
> Once connected, run `/np-organization-create` again.

**Do not continue with the following steps if the VPN is not connected.**

If `organization-create-api.key` doesn't exist, indicate:

> You need an API Key with `organization:create` grant on `organization=0`.
>
> **How to obtain it:**
> 1. Contact the Nullplatform team
> 2. Request a root API Key with grant: `organization:create` on `organization=0`
> 3. Save it: `echo 'YOUR_API_KEY' > organization-create-api.key`

If it's not in `.gitignore`, add it before continuing.

### Step 2: Gather data (batch 1 — org details)

Use AskUserQuestion (up to 4 questions per call):

1. **Organization name** — will be the permanent identifier
2. **First account name** — e.g., "playground", "production"
3. **Stakeholder validation** — "Has this org name been validated with stakeholders? This name is PERMANENT and cannot be changed."

If stakeholder validation is "No" → pause and wait for the user to confirm before continuing.

### Step 3: Gather data (batch 2 — owners)

Use AskUserQuestion:

1. **Owners** — email, first name, and last name for each one (at least 1)

### Step 4: Verify owners

Show a table with all owners and ask for confirmation:

```markdown
## Owners who will receive invitations

| # | Email | First Name | Last Name |
|---|-------|------------|-----------|
| 1 | user@example.com | FirstName | LastName |
| ... | ... | ... | ... |

WARNING: Real invitations will be sent to these emails.
```

Use AskUserQuestion:

> Are the emails and owner details correct?

### Step 5: Show request and confirm

Show the complete request:

```markdown
## Request to execute

**POST** `https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization`

**Body:**
{formatted complete json}

**Auth:** Token generated from organization-create-api.key
```

Use AskUserQuestion for final confirmation:

> Do you confirm the creation of organization `{organization_name}`?
> This action is IRREVERSIBLE.

Options:
- **Yes, create the organization** → Execute
- **No, cancel** → Abort

### Step 6: Execute

**Do NOT use `/np-api fetch-api` here** — np-api authenticates via `NP_API_KEY` env var against `api.nullplatform.com`. It cannot exchange a root API key against the onboarding API (`*.nullapps.io`). Use `curl` directly with token exchange:

```bash
# 1. Exchange the API key for a bearer token
# NOTE: The onboarding API uses "apiKey" (camelCase), unlike the public API which uses "api_key" (snake_case)
API_KEY=$(cat organization-create-api.key)
TOKEN=$(curl -s -X POST "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/token" \
  -H "Content-Type: application/json" \
  -d "{\"apiKey\": \"$API_KEY\"}" | jq -r '.access_token')

# 2. Validate token before proceeding (this is an IRREVERSIBLE operation)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Token exchange failed. Verify organization-create-api.key and VPN connectivity."
  exit 1
fi

# 3. Create the organization
curl -s -X POST "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"organization_name":"...","account_name":"...","owners":[...]}'
```

### Step 7: Process result

**If successful:**

1. Extract the `id` from the response (`id` field, not `organization_id`)
2. Create `organization.properties`:
   ```bash
   echo "organization_id={id}" > organization.properties
   ```
3. Show summary:
   ```markdown
   ## Organization created

   | Field | Value |
   |-------|-------|
   | Organization ID | {id} |
   | Name | {organization_name} |
   | Account | {account_name} |
   | Invited owners | {count} |

   File `organization.properties` created.
   ```

4. Create the state file `organization-{name}.md` (see `docs/state-file.md` for template):
   - Record org id, name, account name, owners, creation timestamp
   - Set phase to `org-created`

**Next step:** API key creation (Step 8).

### Step 8: Create API key for the new organization

**NOTE:** This step is executed ONLY after creating a new organization (Steps 6-7). If the org already existed and creation was skipped (Step 0), DO NOT execute this step or the verification.

**IMPORTANT:** The root API key (`organization-create-api.key`) **only works against the onboarding API** (`*.nullapps.io`). The public API (`api.nullplatform.com`) rejects root tokens with 403. An API key from the new organization is needed.

Guide the user:

```markdown
## Create API key for the new organization

**Steps:**
1. An invited owner accepts the email invitation and signs in at https://app.nullplatform.com
2. Go to **Platform Settings → API Keys → Create API Key**
3. Configure:
   - **Name:** A descriptive name (e.g., `setup-key`)
   - **Scope:** The newly created organization
   - **Roles:** Select **these** roles:
     - `Admin` — Manage all the resources
     - `Agent` — Role to be used by nullplatform agents
     - `Developer` — Create builds, releases, scopes, start deployments
     - `Ops` — Modify environments and infrastructure-related resources
     - `SecOps` — Modify security ops related resources
     - `Secrets Reader` — Read secret parameters
4. Copy the generated API key (shown only once)
5. Save it to a file in the project root:
   ```bash
   echo '<API_KEY>' > np-api.key
   ```
6. Verify that `np-api.key` is in `.gitignore`:
   ```bash
   grep -q "np-api.key" .gitignore && echo "OK" || echo "np-api.key" >> .gitignore
   ```
```

Use AskUserQuestion:

> Create an API key with the roles listed above (Admin, Agent, Developer, Ops, SecOps, Secrets Reader) in the new organization.
> When you have it saved in `np-api.key`, let me know to continue with verification.

Options:
- **I already have the API key in np-api.key** → Continue with verification (Step 9)
- **Skip verification** → Go directly to `/np-setup-orchestrator`

Update the state file phase to `api-key-created`.

**IMPORTANT:** This API key is reused in the subsequent setup steps (`/np-setup-orchestrator`, infrastructure wizard, bindings, etc.). Assigning only `Admin` is not enough — subsequent skills validate that the key has the specific roles listed above.

#### Available roles (reference)

| Role | Description | Required for setup |
|------|-------------|-------------------|
| Admin | Manage all the resources | Yes |
| Agent | Role to be used by nullplatform agents | Yes |
| CI | Machine user that performs continuous integration | No |
| Developer | Create builds, releases, scopes, start deployments | Yes |
| Member | Read access to resource information | No |
| Ops | Modify environments and infrastructure-related resources | Yes |
| SecOps | Modify security ops related resources | Yes |
| Secrets Reader | Read secret parameters | Yes |
| Troubleshooting | Inspect and gather information to diagnose issues |

For the initial setup, **Admin** is recommended. For later use, create keys with the minimum required permissions.

### Step 9: Post-creation verification

**Before starting:** set `NP_API_KEY` from the org-scoped key so `/np-api` can authenticate:

```bash
export NP_API_KEY=$(cat np-api.key)
```

**Note:** Each `/np-api fetch-api` call below is a **Claude skill invocation**, not a bash command. Do not run it inside a bash code block. The `NP_API_KEY` env var must be set in the shell environment before invoking the skill. If context compaction occurred, re-export it.

#### 9.1 Verify the organization exists

Invoke: `/np-api fetch-api "/organization/{id}"`

Verify that the response contains:
- `id` matches the one returned during creation
- `name` matches `organization_name`
- `status` is `active`

#### 9.2 Verify the account was created (only if `account_name` was provided)

**This step is executed ONLY if the user provided `account_name` in the creation body.**
If `account_name` was not provided, skip this step.

Invoke: `/np-api fetch-api "/account?organization_id={id}"`

Verify that the response contains at least one account with the expected name.

#### 9.3 Verify users/owners were created

Invoke: `/np-api fetch-api "/user?organization_id={id}"`

Compare the returned emails with the owners sent in the creation body.

#### 9.4 Show verification result

```markdown
## Post-creation verification

| Check | Status | Detail |
|-------|--------|--------|
| Organization exists | OK/ERROR | ID: {id}, Name: {name}, Status: {status} |
| Account created | OK/ERROR/N/A | ID: {id}, Name: {name} |
| Users created | OK/ERROR | {count}/{total} owners found |
```

If everything is OK, update the state file phase to `complete` and show:

```markdown
Organization verified successfully.

**Next step:** `/np-setup-orchestrator` to continue with the configuration.
```

If something fails, indicate to contact the Nullplatform team with the organization `id`.

**If it fails:**

Show the error and possible causes:

| Error | Probable cause |
|-------|---------------|
| 401 Invalid token | The personal access token expired or is invalid |
| 403 Forbidden | The token doesn't belong to the newly created organization |
| 400 Schema error | Malformatted fields (verify snake_case) |
| 404 Not found | The organization hasn't finished provisioning yet, wait a few minutes |

## Troubleshooting

| Error | Phase | Cause | Fix |
|-------|-------|-------|-----|
| "Invalid token provided" | Creation | `organization-create-api.key` is invalid or expired | Verify key has `organization:create` grant on `organization=0` |
| 403 Forbidden on creation POST | Creation | API key is not root level | Contact Nullplatform team to verify permissions |
| Connection refused / DNS error | Creation | VPN not connected | Connect to VPN — `*.nullapps.io` endpoints require it |
| "must have required property 'last_name'" | Creation | Body uses camelCase | Use `snake_case`: `last_name`, NOT `lastName` |
| TOKEN is null/empty after exchange | Creation | Wrong API key, VPN dropped, or wrong field name in token request | Run the token exchange curl manually and inspect the raw response |
| 403 on `api.nullplatform.com` | Verification | Using root key (`organization-create-api.key`) against public API | Create org-scoped API key (Step 8) and use `np-api.key` instead |
| Owner didn't receive invitation | Post-creation | Email incorrect or in spam | Verify email, check spam. Contact Nullplatform if no email after 15 min |
| 401 with org API key | Verification | Wrong key in `np-api.key` or wrong scope | Verify `np-api.key` has org-scoped key (not root `organization=0`) |

## Next Step

Once the organization is created, continue with the full configuration:

**Tell Claude**: "Let's configure the organization"

Or invoke directly: `/np-setup-orchestrator`
