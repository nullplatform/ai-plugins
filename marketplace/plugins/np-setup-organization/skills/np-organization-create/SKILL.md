---
name: np-organization-create
description: This skill should be used when the user asks to "create an organization", "new nullplatform org", "onboard a new client", "initialize organization", or needs to create a new nullplatform organization via the onboarding API. This is an irreversible operation.
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

## Prerequisites

1. File `organization-create-api.key` in the project root
   - Contains an API Key with `organization:create` grant on `organization=0` (root)
   - This file is **highly sensitive** and must be in `.gitignore`
   - To obtain it: contact the Nullplatform team
2. Verify that `organization-create-api.key` is in `.gitignore`
3. VPN connectivity (required for `*.nullapps.io`)

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

### Step 0: Check if the organization already exists

Before starting the creation flow, check if `organization.properties` already contains an `organization_id`.

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

### Step 2: Gather data

Ask the user using AskUserQuestion:

1. **Organization name** (will be the permanent identifier)
2. **First account name** (e.g., "playground", "production")
3. **Owners** (email, first name, and last name for each one)

### Step 3: Stakeholder validation

**MANDATORY** - Use AskUserQuestion:

> The organization name will be `{organization_name}`.
> This name is PERMANENT and cannot be changed afterwards.
>
> Has this name been validated with stakeholders?

Options:
- **Yes, it's validated** → Continue
- **No, I need to validate it first** → Pause and wait

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

Use `/np-api fetch-api` with `--key-file`:

```bash
/np-api fetch-api \
  --key-file organization-create-api.key \
  --method POST \
  --data '{"organization_name":"...","account_name":"...","owners":[...]}' \
  "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization"
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

   **Next step:** Post-creation verification (Step 8).
   ```

### Step 8: Post-creation verification

**NOTE:** This step is executed ONLY after creating a new organization (Steps 6-7). If the org already existed and creation was skipped (Step 0), DO NOT execute this verification.

**IMPORTANT:** The root API key (`organization-create-api.key` with `organization:create` grant on `organization=0`) **only works against the onboarding API** (`*.nullapps.io`). The public API (`api.nullplatform.com`) rejects root tokens with 403. To verify the newly created org, a token from the new organization is needed.

#### 8.1 Create API key for the new organization

The root API key (`organization-create-api.key`) **only works against the onboarding API** (`*.nullapps.io`). To operate with the public API (`api.nullplatform.com`), an API key from the new organization is needed.

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
- **I already have the API key in np-api.key** → Continue with verification
- **Skip verification** → Go directly to the next step

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

#### 8.2 Verify the organization exists

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/organization/{id}"
```

Verify that the response contains:
- `id` matches the one returned during creation
- `name` matches `organization_name`
- `status` is `active`

#### 8.3 Verify the account was created (only if `account_name` was provided)

**This step is executed ONLY if the user provided `account_name` in the creation body.**
If `account_name` was not provided, skip this step.

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/account?organization_id={id}"
```

Verify that the response contains at least one account with the expected name.

#### 8.4 Verify users/owners were created

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/user?organization_id={id}"
```

Compare the returned emails with the owners sent in the creation body.

#### 8.5 Show verification result

```markdown
## Post-creation verification

| Check | Status | Detail |
|-------|--------|--------|
| Organization exists | OK/ERROR | ID: {id}, Name: {name}, Status: {status} |
| Account created | OK/ERROR/N/A | ID: {id}, Name: {name} |
| Users created | OK/ERROR | {count}/{total} owners found |
```

If everything is OK:

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

### Organization creation

#### "Invalid token provided"

- Verify that `organization-create-api.key` contains a valid API key
- Verify that the API key has `organization:create` grant on `organization=0`

#### "Forbidden" / 403 on creation POST

- The API key is not root level
- Contact the Nullplatform team to verify permissions

#### Connection refused / DNS error

- Verify you are connected to the VPN
- Endpoints `*.nullapps.io` require VPN

#### "must have required property 'last_name'"

- The body uses `snake_case`: `last_name`, NOT `lastName`

### Post-creation verification

#### 403 on verification (api.nullplatform.com)

- **Cause:** The root API key (`organization-create-api.key`) is being used against `api.nullplatform.com`. This key only works against the onboarding API (`*.nullapps.io`).
- **Solution:** Create an API key with Admin role in the new organization (see Step 8.1) and save it in `np-api.key`.

#### Owner didn't receive invitation

- Verify the email is correct
- Check the spam folder
- Contact the Nullplatform team if the email doesn't arrive after 15 minutes

#### New org API key returns 401

- Verify that `np-api.key` contains the correct key (not the root one)
- Verify that the key scope is the new organization (not `organization=0`)

## Next Step

Once the organization is created, continue with the full configuration:

**Tell Claude**: "Let's configure the organization"

Or invoke directly: `/np-setup-orchestrator`
