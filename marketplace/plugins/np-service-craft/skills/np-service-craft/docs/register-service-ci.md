# Register a service run by CI (GitHub Actions)

In CI mode nothing is built or published. Registering means three things, in this order:

1. The **service specification** (and its link specs) exists for the NRN.
2. A **`github` notification channel** filtered on that spec's **slug** points at a workflow
   in a repository the client owns.
3. That **workflow** exists at the channel's `reference`, accepts `workflow_dispatch` and
   follows the contract.

→ Channel creation, autocompletion, validation, the workflow contract and the payload shape:
@${CLAUDE_PLUGIN_ROOT}/skills/np-notification-manager/docs/github-channel.md
→ Why a filter by slug, and the two repo layouts: `execution-modes.md`.

## Prerequisites

- `<slug>/specs/service-spec.json.tpl` valid (Phase 5 of `create-service.md` passed)
- A repository the client owns, with the workflow that will handle the dispatch — the one
  already running their other services, or a new one written from the contract
- The GitHub App installation for that owner (`installation_id`); the notification manager
  autocompletes it from the `github-configuration` provider or from existing channels
- `gh auth status` succeeds, for the validations
- A nullplatform API key stored as a secret in that repository (or GitHub Environment) with
  permission over services, links and actions in the NRN

## Flow

### 1. Read the spec and check collisions

Steps 1 and 2 of `register-service.md` apply unchanged (spec fields, slug collisions in the
API and in the remote). Skip 2b: in CI mode the spec files are not fetched over HTTPS by a
module unless you register with Terraform — then 2b applies as written.

### 2. Create the specification

Ask with `AskUserQuestion` which tool owns the registration — pick one and use it for the
channel too, so both live in the same state:

- **Terraform `(Recommended)` when the repo already has a `nullplatform/` layer** —
  `service_definition` **without** a `package` block and **without** an agent association.
  Pattern: `np-service-creator`, `docs/terraform-patterns.md`, "CI mode".
- **API** — `POST /service_specification` with the rendered spec (`use_default_actions: true`
  generates the action specs), then each link spec. Use `/np-api fetch-api`, never curl.

Verify, and keep the id:

```bash
/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true" \
  | jq '.[] | select(.slug=="<slug>") | {id, slug, name}'
```

### 3. Create the channel

Same tool as step 2:

- **Terraform** — a `nullplatform_notification_channel` with a `github` block, filtered by
  slug (pattern in `np-service-creator`). It can sit in the same apply as the spec because the
  filter is by slug.
- **API** — delegate to `/np-notification-manager create` and pre-answer what is already
  known: type `github`, source `["service"]`, filter `service.specification.slug = <slug>`.
  The manager asks only for owner, repository, reference, workflow file and installation,
  offering the NRN's existing values as options.

Either way, run the manager's validations (repo, reference, workflow file,
`workflow_dispatch`) before the apply or the POST.

### 4. Make sure the workflow handles this slug

Read the workflow at the channel's `reference` and determine the layout it expects
(`execution-modes.md`, "Two repository layouts"):

```bash
gh api "repos/<owner>/<repo>/contents/.github/workflows/<workflow_id>?ref=<reference>" --jq .content | base64 -d
gh api "repos/<owner>/<repo>/contents/<base-path>/<slug>?ref=<reference>" --jq '.[].name'   # layout 2: slug directory present?
```

If the directory for this slug is missing, the dispatch will be accepted (204) and the run
will fail or, worse, exit 0 without touching the service. Add the service's code to that repo
in the layout the runner expects **before** creating the first instance.

### 4b. Cloud credentials for the job (OIDC gotchas)

When the job assumes a cloud role through GitHub OIDC, two things trip a fresh setup:

- **The trust policy must match the repository's subject claim.** Repositories created
  recently use the *immutable* subject `repo:<owner>@<owner_id>/<repo>@<repo_id>:...`, not
  `repo:<owner>/<repo>:...`. Read it with
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (`sub_claim_prefix`) and put
  **both** forms in the trust condition. "Not authorized to perform
  sts:AssumeRoleWithWebIdentity" with a correct-looking policy is this.
- **Reuse the service's own cloud role.** If the service already assumes a role resolved from
  the IAM provider (the agent-mode pattern), give the OIDC role only `sts:AssumeRole` on that
  role and add the OIDC role to that role's trust. The service then runs with the same
  permissions in both modes and nothing is duplicated.

### 5. Verify end to end

```
1. Create a service instance from the UI. From the CLI it is two calls: `np service create`
   leaves the instance `pending` with no action, so also create the action with the form
   values as `parameters`:
     np service action create --serviceId <id> --body '{"specification_id":"<create action spec id>","parameters":{...}}'
   (action spec ids: /np-api fetch-api "/service_specification/<spec_id>/action_specification")
2. /np-api fetch-api "/notification?nrn=<nrn>&source=service&per_page=5"      → the notification exists
3. /np-api fetch-api "/notification/<id>/result"                              → HTTP 204 = GitHub accepted the dispatch
4. gh run list -R <owner>/<repo> --workflow <workflow_id> --branch <reference> -L 3
5. gh run view <run_id> --log-failed                                           → if red
6. /np-api fetch-api "/service/<service_id>"                                   → status active, attributes with exports
```

A 204 with no run, or a service that stays `pending`, is covered row by row in
`troubleshooting.md` ("CI mode") and in the notification manager's debugging table.

### 6. Releasing a change

No rebuild. If `reference` is a branch, pushing is the release. If it is a tag, cut the new
tag and `PATCH /notification/channel/<id>` (or change the Terraform value) so the channel
points at it. Recommend a branch while iterating and a tag once the client wants pinned
releases — state the trade-off, let the user choose.

Existing service instances are not bound to anything in CI mode: the next action on any
instance runs whatever `reference` resolves to at that moment. Say so when the user is used to
the package model, where instances are pinned to the revision they were born with.
