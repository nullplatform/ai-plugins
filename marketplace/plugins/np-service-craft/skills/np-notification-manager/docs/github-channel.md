# GitHub notification channels

A `github` channel makes nullplatform dispatch a GitHub Actions workflow (`workflow_dispatch`) for every
matching event, instead of sending a command to an agent. It is the way to run service provisioning in a
client's own CI, with the client's own credentials, without installing the nullplatform agent.

Nothing here is specific to one client: every value is asked or discovered for the NRN at hand.

## Prerequisites

- A **GitHub App installed on the GitHub organization that owns the repository**, with permission to
  dispatch workflows (`actions: write`) on that repository. nullplatform uses its `installation_id`.
  Setup: `docs/providers/supported-integrations/code-repository/github-configuration` in the docsite.
- A workflow file in that repository, on the reference the channel will point at, that declares
  `workflow_dispatch` with one **string** input for the notification context (see *Workflow contract*).
- The service specification the channel will filter on, or at least its final slug.

## Phase 0 — What to look up before asking

| Need | Source | How to use it |
|------|--------|---------------|
| `installation_id`, GitHub org | `/np-api fetch-api "/provider?nrn=<nrn>&limit=100"`, then `/provider/<id>` for each provider whose specification is `github-configuration` (list results carry `attributes: null`; the read has them) → `attributes.setup.installation_id`, `attributes.setup.organization` | Offer each pair as an option: `<organization> (installation <id>)`. Walk up the NRN (account → organization) if the exact NRN has none |
| Repository, reference, workflow, installation | Existing `github` channels in the NRN: `/np-api fetch-api "/notification/channel?nrn=<nrn>&status=active&limit=100"` filtered by `type == "github"` | Offer `Same as channel <id>: <account>/<repository>@<reference>, <workflow_id>` — picking it fills all five fields at once |
| Default branch, branch list | `gh repo view <account>/<repository> --json defaultBranchRef` / `gh api repos/<account>/<repository>/branches` | Default branch as `(Recommended)` option for `reference` |
| Workflow files | `gh api "repos/<account>/<repository>/contents/.github/workflows?ref=<reference>"` then read each file and keep the ones containing `workflow_dispatch` | Options for `workflow_id`; show the input name the workflow declares |
| Specifications | `/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"` | Options for the filter (slug, name, id) |

If `gh auth status` fails, ask the same questions with "Other" only and warn that the existence checks are
skipped. If `gh` is authenticated but the repository returns 403/404, say so: the user may need another
account, VPN or an IP allow-list exception; do not guess the values.

## Batch 2 — GitHub questions (`AskUserQuestion`, up to 4 per call)

Ask in this order; each answer narrows the next lookup.

1. **GitHub installation / organization** — options: the `github-configuration` pairs found, the pairs used
   by existing github channels, "Other" (user types `owner` and `installation_id`). The GitHub owner is not
   necessarily the nullplatform organization name, and a client can have more than one GitHub org: never
   assume.
2. **Repository** — options: repositories used by existing github channels in the NRN, "Other". When a
   repository is typed, confirm it exists with `gh repo view` before continuing.
3. **Reference (branch or tag)** — options: the repository default branch `(Recommended)`, references used
   by existing channels for this NRN (clients often map one branch per account/environment), "Other".
4. **Workflow file** — options: the `workflow_dispatch` workflows found at that reference (file name plus
   its input name), "Other". Store the exact file name including extension; GitHub also accepts the
   numeric workflow id but the file name is what people recognise.

If the user picked "Same as channel <id>" in question 1, skip 2–4 and show the five values for confirmation.

## Validation before confirmation

Run what `gh` allows and report each line as PASS/WARN/FAIL:

```bash
gh repo view <account>/<repository> --json name,defaultBranchRef               # repo reachable
gh api "repos/<account>/<repository>/git/ref/heads/<reference>"               # branch exists (or /tags/<ref>)
gh api "repos/<account>/<repository>/contents/.github/workflows/<workflow_id>?ref=<reference>" --jq .content | base64 -d \
  | grep -nE 'workflow_dispatch|inputs:|type: *string'                        # dispatchable, string input
gh api "repos/<account>/<repository>/actions/workflows" --jq '.workflows[] | select(.path | endswith("<workflow_id>")) | .state'   # active, not disabled
```

What cannot be verified from here, say explicitly: that the GitHub App behind `installation_id` is installed
on **this** repository (only the client's GitHub org admin or an installation token can list that), and that
the workflow's secrets/variables are configured. Both show up later as "204 delivered, nothing ran".

Also check the filter: the value is not empty, and the slug matches a specification in the list (or the slug
the spec will have — a channel filtered by slug may legitimately exist before its spec, which is what lets
both be declared in one Terraform apply). Say explicitly when the spec is not there yet, so the user
re-checks the channel with `inspect` once it is.

## Channel JSON

```json
{
  "nrn": "<nrn>",
  "description": "<description>",
  "source": ["service"],
  "type": "github",
  "status": "active",
  "configuration": {
    "installation_id": "<numeric string>",
    "account": "<github owner>",
    "repository": "<repository name, without owner>",
    "reference": "<branch or tag>",
    "workflow_id": "<file name in .github/workflows>"
  },
  "filters": {
    "service.specification.slug": { "$eq": "<spec slug>" }
  }
}
```

Variants:

- Filter by id when wiring a channel by hand onto a spec that already exists and must survive a slug
  change: `"filters": {"service.specification.id": "<spec uuid>"}`.
- Leave custom actions to another channel: add `"type": {"$ne": "custom"}` to `filters`.
- Several specs on one workflow: one channel per spec is the safe default (clear filter, easy to retire one
  service). A single channel with `"service.specification.slug": {"$in": [...]}` also works; the workflow then
  routes by `notification.service.specification.slug` (the **service** spec — `notification.specification`
  is the *action* spec, e.g. `create-<slug>`, and is the wrong key to route on).

Create with:

```
/np-api fetch-api "POST /notification/channel" with body: <channel-json>
```

## Workflow contract (what the repository must implement)

Print this after creating the channel; it is what the client's workflow has to satisfy.

1. **Trigger:** `on: workflow_dispatch: inputs: <name>: {type: string, required: true}`. nullplatform
   sends the whole notification JSON in that input (the usual name is `context`). The payload must fit
   GitHub's input size limit or the dispatch fails with `422`.
2. **Expose it as `NP_ACTION_CONTEXT`:** `env: NP_ACTION_CONTEXT: ${{ inputs.<name> }}`.
3. **Authenticate the np CLI:** `NULLPLATFORM_API_KEY` from a repository/environment secret. Install the CLI
   with `curl -fsSL https://cli.nullplatform.com/install.sh | sh`.
4. **Run the action and report back:** `np service-action exec --live-report --live-output --script <handler>`.
   The CLI parses `NP_ACTION_CONTEXT`, exports `ACTION_*` variables (`ACTION_TYPE`, `ACTION_SERVICE_ID`,
   `ACTION_SERVICE_SLUG`, `ACTION_SERVICE_SPECIFICATION_ID`, `ACTION_LINK_ID`, `ACTION_LINK_SLUG`,
   `ACTION_SERVICE_DIMENSIONS_*`, `ACTION_TAGS_*`), runs the handler, and PATCHes the action status. Outputs
   go back with `np service action update --results '<json>'` (or `np link action update` for links).
   Without this step the service stays `pending` forever: the platform never times it out.
5. **Resolve the module path** with `np service-action get-exec-path --lookup-by descend-by-action-and-link-slug`
   (optionally `--base-path <dir>`); it returns `<spec-slug>/service` or `<spec-slug>/link/<link-slug>`.
6. **Fail loudly:** on any precondition failure, still run `np service-action exec` with a script that
   exits non-zero so the action is marked `failed` with a message, instead of leaving it pending.

Payload shape the workflow receives (top level and `notification`):

```
{ id, source: "service", event: "service:action:create", created_at,
  notification: { action, id, name, slug, status, type (create|update|delete|custom), managed,
                  parameters {...form values...}, results {}, specification {id, slug},
                  service {id, slug, attributes, dimensions, specification}, link | null,
                  user {id, email}, tags {organization, account, namespace, application + *_id}, entity_nrn } }
```

Per-environment credentials usually come from GitHub Environments keyed on something derived from the payload
(for example `tags.account_id`, `tags.namespace_id` and `service.dimensions.environment`); the key format is
the client's decision and the skill does not impose one.

## Debugging a github channel

`/notification/<id>/result` shows GitHub's HTTP response. `204` means GitHub accepted the dispatch and no more.
Then, in GitHub:

```bash
gh run list -R <account>/<repository> --workflow <workflow_id> --branch <reference> --limit 20 \
  --json databaseId,status,conclusion,createdAt,url
gh run view <run-id> -R <account>/<repository> --log | grep -E 'Error|failed|np service'
```

| Finding | Meaning | Action |
|---------|---------|--------|
| No run at the dispatch minute | GitHub dropped it: Actions disabled, workflow disabled, concurrency group, App not installed on the repo, rate limit | Fix in GitHub, then `/np-notification-manager resend <notification-id> <channel-id>` |
| Run failed | The handler failed; nullplatform only knows if the run PATCHed the action | Read the run log; resending repeats the failure until the workflow is fixed |
| Run queued | Self-hosted runner down | Do not resend; each resend queues another run |
| Run succeeded, service still pending | The run never called `np service-action exec` / `update` on this action (wrong token, wrong account branch) | Check the step that reports back and which `NULLPLATFORM_API_KEY` it used |
| Service `updated_at` seconds after `created_at` and never again | Nothing ever reported back | Same as above |

Related: in the troubleshooting KB, *service-actions.md* ("204 but the service stays creating") and
*notifications.md* (entity hooks on `workflow_dispatch`, payload size `422`).
