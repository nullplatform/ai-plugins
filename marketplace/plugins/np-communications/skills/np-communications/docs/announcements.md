# Announcements

An announcement is a message from the organization's admins to everyone in it (or to some roles): a release, a
maintenance window, an incident. It shows in the **Announcements** tab of each person's bell, as a **banner**
across the product, or both. On the wire it is a notification of `kind: "broadcast"`.

Announcements always reach their audience: they are not in Inbox settings and cannot be muted. Once published,
an announcement lands in every matching bell at once; closing it later hides it from new readers but not from
whoever already got it. Confirm every create and every edit of a live announcement (SKILL.md "Confirm before any write").

In the dashboard only the **Admin** role manages announcements (Platform Settings > Communications >
Announcements). Through the API, the permissions in SKILL.md apply.

## Create

```
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @announcement.json "/communications/notification"
```

```json
{
  "kind": "broadcast",
  "category": "platform.maintenance",
  "severity": "maintenance",
  "title": "Scheduled maintenance on Sunday",
  "body": "The API will be read-only between **02:00 and 04:00 UTC**.",
  "key": "maintenance-2026-11-02",
  "group_key": "maintenance-2026-11",
  "cta": { "label": "Read the details", "kind": "link", "url": "https://status.example.com/maintenance" },
  "surfaces": [
    { "type": "inbox", "dismissible": true },
    { "type": "banner", "dismissible": true, "sections": ["development", "platform_settings"] }
  ],
  "audience": { "grants": [] },
  "publish_at": "2026-10-31T12:00:00Z",
  "expires_at": "2026-11-02T04:00:00Z"
}
```

`201` with the stored announcement (it has an `id`, a UUID), or `200` with the existing one when `key` was used
before (so a script can re-run safely).

### Fields

Ask with `AskUserQuestion` for what the user did not say: where it shows (Bell and banner, Bell only, Banner
only), the severity, who sees it (Everyone, Recommended / some roles), and the schedule (Now until closed /
scheduled window).

| Field | Rules |
|-------|-------|
| `kind` | `"broadcast"`. Required. |
| `category` | Required. Use one of the six announcement categories, which label it in the Announcements tab: `platform.release`, `platform.changelog`, `platform.maintenance`, `platform.incident`, `platform.advisory`, `platform.other`. |
| `title` | Required, up to 250 characters. Inline Markdown: `**bold**`, `*italic*`, `` `code` ``. |
| `body` | Optional, up to 2,000 characters. Also takes links (https or mailto) and lists. |
| `severity` | `informational` (blue), `maintenance` (yellow), `degraded` (orange), `outage` (red). Sets the icon and color everywhere. |
| `surfaces` | Where it shows (at most 5 entries). `{ "type": "inbox", "dismissible" }` is the bell; `{ "type": "banner", "dismissible", "sections": [...] }` is a banner. `sections` is required on a banner and refused on the inbox: any of `development`, `platform_settings`, `insights`. |
| `surfaces[].nrn` | Banner only, optional: show the banner only on that resource and what is under it. Requires `sections: ["development"]` exactly. It narrows **who** too: only people whose role (in `grants`) sits on that resource, above it or below it see it. The bell half of the same announcement is not narrowed. |
| `audience` | `{ "grants": ["admin", "ops"] }` with role slugs, or `[]` / omitted for everyone in the organization. A role held anywhere in the organization counts. Leave `organizations` out: it defaults to your organization, and naming another one is a `403`. |
| `nrn` | Leave it out. An announcement lives at the organization root; a deeper `nrn` is refused (`422`). To target a resource, use a banner's `surfaces[].nrn`. |
| `publish_at` / `expires_at` | Optional ISO 8601 UTC. Without `publish_at` it is published now; without `expires_at` it stays until closed. A banner disappears on its own when it expires. |
| `cta` | Optional button, `label` up to 80: `{ "label", "kind": "link", "url" }`, or a guided tour `{ "label", "kind": "tour", "tour_id", "path", "nrn" }`. |
| `key` | Optional, up to 200: makes the create idempotent (a second create with the same key answers the stored one, unchanged). |
| `group_key` | Optional, up to 200: the thread it belongs to, so a later `POST /close` closes every open announcement of it at once (an incident and its updates). |
| `status` | Optional `"open"` (default) or `"closed"` (created already closed: shows nobody anything). |
| `places`, `media` | Optional, Slack only: `places` posts it to up to 10 Slack channels (`{ "channel": "slack", "destination": { "channel_id", "channel_name" } }`) and `media.slack` overrides the title/body there. It needs Slack enabled on the service (`GET /communications/delivery/capabilities` lists `slack`) and the organization's Slack app connected (`GET /communications/slack/status?nrn=organization=<id>`). `audience.grants` does **not** apply to places: everyone in the channel reads it, so warn the user when the announcement is for some roles only. Announcements are never emailed (`media.email` is accepted but unused). |

Never send `organization_id`, `publisher` or `created_by`: the service refuses them.

To preview how it will render in each medium before publishing, `POST /communications/render` with
`{ title, body, severity, cta, media }` answers what the bell, email and Slack would show (an announcement only uses the bell and Slack), and sends nothing (no
confirmation needed; it takes `notification_center:inbox:read`).

Two live banners rotate every 10 seconds. Before publishing a banner, list what is live (below) and warn the user
if another banner is already showing.

## List and read

```
/np-api fetch-api "/communications/notification/manage?kind=broadcast&limit=50&offset=0"
/np-api fetch-api "/communications/notification/<id>"
```

`/manage` lists everything the organization emitted, closed, scheduled and expired included, newest first:
`{ results, pagination: { offset, limit, total } }`, `limit` up to 100. Derive the state the dashboard shows:

| State | Condition |
|-------|-----------|
| Scheduled | `status: open` and `publish_at` in the future. Nobody has seen it; editing is safe. |
| Active | `status: open`, published, not expired. |
| Expired | `expires_at` in the past. |
| Closed | `status: closed`. |

## Edit, close, reopen, delete

| Goal | Request |
|------|---------|
| Edit (partial) | `PATCH /communications/notification/<id>` with any of `title`, `body`, `severity`, `category`, `cta`, `surfaces`, `audience`, `publish_at`, `expires_at`, `places`, `media`, `status` |
| Close one | `PATCH /communications/notification/<id>` with `{ "status": "closed" }` |
| Reopen one | `PATCH /communications/notification/<id>` with `{ "status": "open" }`; for an expired one also send a future `expires_at` (the dashboard does not offer this; through the API it works) |
| Close a whole thread | `POST /communications/notification/close` with `{ "group_key": "<key>" }` → `{ closed: <n> }`. It closes **every** open notification of the organization with that key, personal notifications included, not only announcements: use a `group_key` no inbox rule uses. |
| Delete | `DELETE /communications/notification/<id>` → `204` |

`PATCH` replaces `places` and `media` whole (`null`, `[]` or `{}` clears them); when changing `surfaces` or
`audience`, send the full value too. `nrn` and `action` cannot change.
Editing a live announcement changes what everyone sees in place; closing keeps it for whoever already has it;
deleting removes it from everyone's bell and, with Slack on, deletes the Slack messages it posted. Prefer close.
Confirm before `DELETE` and before `POST /close` (show how many open announcements share the `group_key` first).

## CLI equivalents (for the user to run, when their CLI has `np communications`)

```
np communications notification create --body announcement.json
np communications notification list --kind broadcast --limit 50
np communications notification read --id <id>
np communications notification patch --id <id> --body '{"status": "closed"}'
np communications notification close --body '{"group_key": "maintenance-2026-11"}'
np communications notification delete --id <id>
```

`notification list --all` returns at most the first 100: page with `--offset` instead.

## Not for announcements

- A message to specific people about something that happened → an invoked inbox rule (emission.md), so people
  can tune it in Inbox settings and recipients are checked against the resource.
- A message to a Slack channel for every deployment failure → a delivery destination on the inbox rule's
  category (Platform Settings > Communications), not an announcement.
