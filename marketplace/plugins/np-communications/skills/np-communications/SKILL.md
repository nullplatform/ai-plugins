---
name: np-communications
description: Operate nullplatform Communications (formerly the Notification Center) through the public API under /communications or the np communications CLI. Use when the user mentions the dashboard bell or inbox, inbox rules or custom notification types (write, validate, test, turn off, reset a built-in), emitting a notification to people from CI or a workflow, announcements and banners (publish, schedule, close), inbox settings or notification preferences, Slack delivery destinations or email notifications, or why someone did or did not get a notification. Does NOT cover agent notification channels under /notification/channel, which route platform events to agents, webhooks or CI runners (use /np-notification-manager).
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/*.sh), Read, Write, AskUserQuestion
---

# np-communications

Communications is how nullplatform reaches people inside the product: each person's **inbox** (the bell),
**announcements** from the organization's admins (in the bell, as a banner, or both), and **inbox rules**
that decide what triggers a notification, who receives it and what it says. This skill is for a customer's
platform team operating it through the public API or the CLI.

## Critical Rules

1. **Scope check first, by direction.** Platform events delivered *to* agents, webhooks or CI runners (agent
   notification channels, `/notification/channel`, `/notification`) are a different service: say so and hand off
   to `/np-notification-manager`. Anything that reaches *people* (the bell, inbox, announcements, banners, inbox
   rules, inbox settings, Slack or email about those notifications) is this skill, including a CI job that
   notifies people's inboxes.
2. **Every API call goes through np-api, never `curl`.** Reads:
   `/np-api fetch-api "/communications/..."`. Writes (POST/PUT/PATCH/DELETE):
   `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method <M> --data @<file.json> "/communications/..."`.
   `/communications` is not in np-api's endpoint catalog yet: skip `search-endpoint` / `describe-endpoint` for these
   routes and use the docs below as the reference. Write request bodies to a file first (`Write`), then pass
   `--data @<file>`. The `np communications ...` CLI is for the user to run in their terminal or pipeline; this
   session does not run it.
3. **Confirm before any write that changes something.** Show the full body (the inbox rule definition, the
   emission, the announcement) and the exact request, then wait for an explicit yes. A published announcement and
   an emitted notification cannot be taken back from the people they already reached. Checks that write nothing
   need no confirmation: `POST .../validate`, any `?dry_run=true`, `POST /communications/render`. A send test
   (`"deliver_to": "me"`) reaches only the caller's own bell: say so before running it, no confirmation needed.
4. **Test before activating.** An invoked rule goes `POST /validate` → emission `?dry_run=true` →
   `"deliver_to": "me"` → save. A rule that rides a nullplatform entity (a source name, or stale) cannot be
   emitted: it goes `POST /validate` → save with `?dry_run=true` → save. Never skip straight to saving, and never
   emit for real to try a rule out.
5. **Idempotency is by `context.id`, one id per resource.** Retrying the same `id` for the same `nrn` is safe
   (`200`, `existing: true`); the same `id` for another `nrn` is a `409`. Build the id from the event, never a
   random value per attempt.
6. **Read the body, not the status line.** The np-api script prints only the response body. Tell outcomes apart
   by shape: `emitted[]` with `existing: true` (a retry), `{ deferred }` (202), `would_emit` (dry run),
   `test: true` (send test). Errors carry no status field; tell them apart by shape too:
   `{ message, errors: [{ path, message }] }` is a located 400 (fix each `path`);
   `{ message, id, detail }` is a business error (403, 404, 409, 422; `detail` says what to do when it is set);
   a bare `{ message }` is a denied permission (401, see Permissions); `{ statusCode, error }` comes from the
   public API gateway (a root token, see troubleshooting.md).
7. **Use the product's words** with the user: Communications, Inbox rules, Announcements, Inbox settings,
   Delivery destinations. The wire keeps older names (`kind: broadcast`, `type_id`, `organization_state`) and the
   permissions are still `notification_center:*`.
8. **Wizards use `AskUserQuestion`**, at most 4 questions per call, recommended option first.

## Commands

| Command | What it does | Reference |
|---------|--------------|-----------|
| `/np-communications rules` | List inbox rules (built-in and custom) with state and scope | inbox-rules.md |
| `/np-communications rule <id>` | Read one inbox rule and explain when it fires and who it reaches | inbox-rules.md |
| `/np-communications new-rule` | Guided: write an inbox rule from the schema, validate, dry-run, test, save | inbox-rules.md |
| `/np-communications emit <id>` | Wire an invoked rule into a workflow or CI step, with retries | emission.md |
| `/np-communications announce` | Guided: publish, schedule or update an announcement or banner | announcements.md |
| `/np-communications close <group_key>` | Close every open announcement of a thread | announcements.md |
| `/np-communications why <who> <what>` | Diagnose why someone did or did not get a notification | troubleshooting.md |

## Inbox rules

List, read, write from `GET /communications/inbox_rule/schema` and the sources from
`GET /communications/inbox_rule/source`, validate, dry-run, send a test to yourself, save, deactivate, delete,
edit or reset a built-in rule, turn a built-in rule off for the organization.

@${CLAUDE_PLUGIN_ROOT}/skills/np-communications/docs/inbox-rules.md

## Emitting from a workflow or CI

`POST /communications/inbox_rule/<id>/emission` with `{ nrn, context }`: idempotency, status codes, credentials,
the CLI form and a retry-safe pipeline step.

@${CLAUDE_PLUGIN_ROOT}/skills/np-communications/docs/emission.md

## Announcements

Broadcasts to the organization in the bell (`inbox` surface), as a banner (`banner` surface), or both;
`publish_at` / `expires_at`; editing, closing by `group_key`, deleting.

@${CLAUDE_PLUGIN_ROOT}/skills/np-communications/docs/announcements.md

## Troubleshooting

"Why didn't X get this notification?" and "why did Y get it?": the order to check things in, what the API can
and cannot show you, and the error table.

@${CLAUDE_PLUGIN_ROOT}/skills/np-communications/docs/troubleshooting.md

## Permissions

The caller's role must grant these actions (names keep the old prefix). A missing one answers **`401`** with
`{ "message": "You're not authorized to perform this operation." }`: the body never names the action, so match
the request against this table to find it. The same `401` also answers a token that failed verification; an
expired one says `"The token has expired"` instead.

| Operation | Action | Over |
|-----------|--------|------|
| List / read inbox rules, schema, sources, `POST /validate` | `notification_center:type:read` | organization |
| Create / update / deactivate / delete an inbox rule, dry-run or test a draft | `notification_center:type:write` | the rule's scope (`visible_to`) |
| Emit an invoked inbox rule (also its dry run and send test) | `notification_center:notification:create` | the emission's `nrn` |
| Create an announcement | `notification_center:notification:create` | the organization |
| List / read announcements and notifications | `notification_center:notification:read` | organization |
| A notification's deliveries | `notification_center:notification:read` | the notification's `nrn` |
| Edit or close announcements (`PATCH`, `POST /close`) | `notification_center:notification:write` | organization |
| Delete an announcement | `notification_center:notification:delete` | organization |
| Delivery destinations (read / write) | `notification_center:type:read` / `notification_center:type:write` | the destination's `nrn` |
| Categories, channel capabilities, `POST /render` | `notification_center:inbox:read` | organization |
| Own inbox and inbox settings | `notification_center:inbox:read` / `notification_center:inbox:write` | organization |

This skill reads inbox settings but never writes them: each person changes their own in the dashboard.

In the dashboard, Communications under Platform Settings is shown to Admin and Ops, and announcements to Admin
only. A CI key needs only `notification_center:notification:create` to emit.

## Docs

- Product docs: `https://docs.nullplatform.com/docs/communications`, `.../communications/inbox-rules`,
  `.../communications/announcements`
- CLI: `np communications ...` is not in every released CLI yet. If `np communications --help` fails on the
  user's machine, give them the API request instead.
