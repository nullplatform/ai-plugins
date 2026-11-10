# Troubleshooting: who gets what

A notification reaches a person only if every gate below lets it through. Walk them in order and stop at the
first one that explains the case; say which gate it was and how the user can confirm it.

```
the rule fires ─► the rule is on, and its scope covers the resource ─► the person is in a reading's audience
  ─► the person can see the resource ─► the person's Inbox settings keep it ─► (Slack) a delivery destination
  posts it / (email) the person's email setting sends it
```

## What the API can and cannot show you

- You **can** read the rules, their state and scope, the categories, an emission's dry run, the organization's
  announcements, and the deliveries of a notification or of a delivery destination.
- You **cannot** read another person's inbox or Inbox settings: `GET /communications/inbox_setting` and
  `GET /communications/inbox` answer the caller's own only. For someone else, ask them (or have them share a
  screenshot) of their bell and of **Inbox settings** (settings icon in the bell, or User settings > Inbox).
- Delivery counts are counts (`recipients`, `rejected`): the service never answers who exactly received
  something.

## Step 0 — Pin down the case

Ask with `AskUserQuestion` if missing: which notification (rule id or what it was about, or "an
announcement"), who expected it, which resource (application, namespace, account) and roughly when. Then find the
rule: `GET /communications/inbox_rule` and match by `document.category.label` or id. For an announcement go to
"Announcements" below.

## Gate 1 — Did the rule fire?

- **Invoked rule**: the pipeline's emission response is the record. `emitted: []` means nobody was left (keep
  going with gates 3-5); a `4xx` means nothing was sent (see the table at the end). Reproduce with
  `?dry_run=true` and the same body: it answers `would_emit`, `rejected` and `unreached[].reason` without writing.
- **Rule riding an entity** (`source` is a name): the entity must have reached a status the rule's
  `when.conditions` name, and that status must be in the source's `delivered_statuses`
  (`GET /communications/inbox_rule/source`). Check the entity itself (`/np-investigation-diagnostic` or
  `/np-api fetch-api "/deployment/<id>"`). These rules cannot be dry-run.
- **Stale rule**: it fires only after the entity rested in `when_status` for `after`, and only for entities that
  started resting within `within`.
- **Delay or batch**: a `202 { deferred }` or a rule with `behaviors` delivers later, possibly merged into one
  notification.

## Gate 2 — Is the rule on for the organization and that resource?

From the rule row:

| Check | Cause when it fails |
|-------|---------------------|
| Built-in: `organization_state.enabled: false` | The organization deactivated it. Turn it back on with `PUT .../<id>/organization_state` `{ "enabled": true }` (confirm first). |
| Built-in: `organization_state.customized: true` | An edited copy runs instead: read the organization's row with the same id (the one with your `organization_id`) and check gates 1-3 against it. |
| Custom: `status: deprecated` | Deactivated; emissions answer `404`. |
| `document.visible_to` does not contain the resource's NRN | Out of scope: emissions answer `404`, entity events under other resources are ignored. |

## Gate 3 — Is the person in a reading's audience?

Read `document.audience[]` and explain each reading in words.

- `who.user`: only the user id the data names. For built-in rules that is usually the person who caused the
  event: Deployment failed goes to whoever started the deployment (`context.user_id`). A deployment started by a CI
  key or a machine user names no human, so only followers get it.
- `who.can`: everyone holding that action on the resource (Approval pending reaches who can approve).
- No `who`: only **followers**, people who chose **Everything** for that rule on the resource or above it, when
  `category.allows_all` is true.
- `fallback` reaches someone else only when `who` resolved nobody.
- `exclude_actor: true` skips whoever caused the event (you do not get notified of your own action).

"Involving me" means "in a `who` audience". To get everything about an application regardless of who caused it,
the person sets that rule to **Everything** on that application in Inbox settings.

Dry-run evidence (invoked rules): `unreached[].reason` = `nobody` (the reading's `who` resolved nobody: wrong or
missing user id in the context), `no_watchers` (a followers-only reading with no followers).

## Gate 4 — Can the person see the resource?

Recipients of an invoked rule are verified against the emission's `nrn`: whoever has no role on it, above it or
below it, is dropped and counted in `rejected`. Fixes: the person needs a role covering the resource, or the
emission should name a resource they can see. This skill does not read people's roles: ask an administrator to
check the person's roles in the dashboard.

## Gate 5 — Do the person's Inbox settings keep it?

Resolution per rule (its category id) and resource: walk the notification's NRN from the most specific resource
to the organization root; at each level a setting for that rule beats the person's "all rules" setting
(`*`, the **Mute everything from this resource** switch); the first one found decides. With nothing set,
`category.default_mode` applies.

- `default_mode: off` rules reach nobody until people opt in. Built-in rules off by default: **Deployment
  started**, **Deployment finished**, **Build finished**, **Scope ready**, **Service action finished**.
- Mode `off` on the resource or an ancestor (and no more specific setting) drops it. Dry-run evidence:
  `unreached[].reason: preferences`.
- `category.configurable: false` rules ignore Inbox settings entirely.
- Settings apply to **new** notifications only; changing them never adds or removes what is already in the inbox.
- The caller can read their own settings: `/np-api fetch-api "/communications/inbox_setting"` →
  `{ results: [{ id, nrn, category, channel, mode, source, created_at, updated_at }] }`. `channel` is `inbox` (the
  bell) or `email`; read only the channel in question. `source: seed` means nullplatform suggested it from the
  person's activity (for example following the applications they deploy most) and they never changed it;
  `source: user` means they set it. For anyone else, ask them to check Inbox settings: the Default tab and every
  customized resource above the one in question.
- Category defaults (`default_mode`, and `channels.email.default_mode` for email) for every rule:
  `/np-api fetch-api "/communications/category"`.

## Gate 6 — Slack and email

The bell is always the first channel. Slack and email are extra, and each is enabled per nullplatform
installation: `/np-api fetch-api "/communications/delivery/capabilities"` → `{ channels: ["inbox", ...] }`. A channel
missing there is off for everyone, whatever the settings say.

They work differently:

- **Slack** is per organization: a **delivery destination** (Platform Settings > Communications > the rule, "Also
  post to") posts the notifications of some rules' categories, for an NRN and everything under it, to a Slack
  channel. Destinations are Slack only. It needs the organization's Slack app connected and invited to the channel.
  Roles do not apply inside a Slack channel: everyone in it reads what is posted.
- **Email** is per person: one email per notification, to someone already in the audience, when their email
  setting for that rule says so. It is off unless the rule's `category.channels.email.default_mode` turns it on,
  and each person turns it on or off in their Inbox settings (rows with `channel: "email"`). Announcements are never
  emailed.

Reads:

- A notification's deliveries: `/np-api fetch-api "/communications/notification/<notification-id>/delivery"`.
  The id comes from the emission response (`emitted[].id`) or from the person's inbox. Lists are newest first, at
  most 50 per page: `paging: { next_cursor }`, pass it back as `?cursor=` until it is `null`.
- Delivery destinations: `/np-api fetch-api "/communications/delivery_destination?nrn=<nrn>"` lists the ones at
  that NRN **or below it**, not above. To find what posts for an application, query its NRN **and each ancestor up
  to `organization=<id>`** (or query the organization root, which lists them all). Destination ids are UUIDs. One
  destination's history: `/np-api fetch-api "/communications/delivery_destination/<id>/delivery"`.
- Slack installation: `/np-api fetch-api "/communications/slack/status?nrn=<nrn>"`.
- Post a sample to a destination's channel (writes no delivery, confirm first):
  `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data '{}' "/communications/delivery_destination/<id>/test"` →
  `{ ok }` or `{ ok: false, error: { code, message } }`.

Each delivery row has `status`, `skip_reason` and `last_error`. **No row at all** for a person's email means email
was off by default for them (or the email channel is not enabled): nothing was skipped, it was never planned.

| `skip_reason` | Meaning |
|---------------|---------|
| `preference` | The person explicitly turned email off for that rule. |
| `no_address` | No email address or Slack identity to send to. |
| `no_installation` | No Slack app installed on the destination's NRN or above. |
| `rule_inactive` | The delivery destination was deactivated before the send. |
| `audience_restricted` | A delivery destination does not post an announcement limited to some roles (`audience.grants`) to a shared channel. An announcement's own Slack `places` are never skipped for this: they post to everyone in the channel. |
| `expired` | The notification expired before the send. |
| `channel_disabled` | Older rows, and the error code of a test send: the channel was not enabled. |
| `withdrawn` | A broadcast closed before its delivery ran (for example a scheduled one closed before `publish_at`). |
| `duplicate` | Another destination on the same Slack channel (or the announcement's own Slack place) already posted it: a channel is told once per notification. |
| `place_removed` | The announcement no longer lists that Slack channel. |

A destination's `categories` must happen under its `nrn`: a custom rule scoped elsewhere is refused when the
destination is saved. Announcements are never sent through delivery destinations' categories (they use their own
Slack `places`).

Creating or editing delivery destinations, and turning email on, are done in the dashboard (Platform Settings >
Communications, and each person's Inbox settings); this skill reads them.

## Announcements

| Symptom | Check |
|---------|-------|
| Nobody sees it | `GET /communications/notification/<id>`: `status: closed`, `publish_at` still in the future, or `expires_at` already passed. |
| Some people do not see it | `audience.grants`: they hold none of those roles. Role and resource are matched on the same grant. |
| A banner shows to fewer people than the bell | A banner's `surfaces[].nrn` narrows who: only people whose role sits on that resource, above or below it. The bell half is not narrowed. |
| A banner is not where they look | `surfaces[].sections` (`development`, `platform_settings`, `insights`). A resource-targeted banner shows only in `development`. |
| A person stopped seeing the banner | They dismissed it; dismissal is saved per account, in every browser. Set the banner surface `dismissible: false` for must-read notices. |
| Not in Inbox settings | Expected: announcements cannot be muted. |

## Why did someone get it?

The reverse of the gates: they are in a `who` audience (they caused the event, hold the `can` action, or were the
`fallback`), or they chose **Everything** for that rule on that resource or above it (follower), or the rule's
`default_mode` is `all` for an audience they are in, or the category is not configurable. To stop it for them:
they set the rule to **Off** for that resource in Inbox settings; for everyone: deactivate the rule, or narrow its
`who` / `visible_to`.

## Errors

| Error | Where | Cause | Fix |
|-------|-------|-------|-----|
| `400` with `errors: [{ path: "/context/..." }]` | emission | Context fails the rule's `context_schema` | Send the required fields with the declared types |
| `400` "is not invocable" | emission | The rule rides an entity, not `{ kind: invoked }` | Only invoked rules can be emitted |
| `400` on `/nrn` | emission | NRN not valid, outside the organization, or (draft emission) outside the draft's `visible_to` | Use `organization=<id>:...` within your org and the rule's scope |
| `400` `INVALID_NRN` / `403` "belongs to another organization" / `422` "can only be scoped to organization=<id>" | announcement | The announcement's `nrn` is not valid, is another organization's, or is deeper than the root | Leave `nrn` out: announcements live at the organization root |
| `400` "a draft only runs as a dry run..." | `POST /inbox_rule/emission` | Draft emission without `?dry_run=true` or `deliver_to: "me"` | Add one of them; save the rule to emit for real |
| `400` with located `errors` | rule create/update | Definition refused (id format, forbidden keyword, cap reached, unknown field or status) | Run `POST /validate` and fix each `path` |
| `409` "This notification type is active" (`detail`: deactivate it first) | `DELETE /<id>/permanent` | Rule still active | `DELETE /<id>` first |
| `409` "...customization of a default" | `DELETE /<id>` on an edited built-in | Edits are reset, not deactivated | `DELETE /<id>/customization`, or `organization_state` to turn it off |
| `403` `{ statusCode, error: "Root tokens are not valid from public api" }` | any | The public API gateway refuses root (nullplatform-internal) identities | Use an API key or login of the customer's organization (`NP_API_KEY`) |
| `401` `{ message: "You're not authorized to perform this operation." }` | any | The role lacks the action on that NRN (the body does not say which), or the token failed verification | Find the action in the SKILL.md permissions table and grant it; if the role has it, get a fresh token |
| `401` `{ message: "The token has expired" }` | any | Expired token | Get a fresh token |
| `403` | `PUT`/`DELETE` on a built-in rule | Built-in rules are read-only | Edit it (POST with its id) or turn it off with `organization_state` |
| `403` | announcement | `audience.organizations` names another organization | Leave `organizations` out |
| `404` | emission | Rule unknown, deactivated, or out of scope for the `nrn` | Check gate 2 |
| `409` | emission | `context.id` already emitted for another resource | Distinct id per resource; do not retry |
| `409` | rule create | The id already exists (another write won, or you already edited that built-in) | Read it and `PUT /<id>` instead (for an edited built-in that updates your edit) |
| `422` `CATEGORY_DISABLED` | `POST /communications/notification` with a built-in rule's category | The organization turned that built-in rule off | Turn it back on, or use another category |
| `422` (incl. `UNSUPPORTED_CHANNEL`) | `PUT /inbox_setting` (seen in a person's report; this skill does not write settings) | Unknown or non-configurable category, `all` not allowed, NRN outside the org, 500 settings reached, or a channel that is not personal (only `inbox` and `email`) | Pick a configurable rule; use Everything only where `allows_all`; Slack is set with delivery destinations |
