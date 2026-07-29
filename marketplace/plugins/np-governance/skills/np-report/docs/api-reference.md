# Reports API — endpoint reference

Base URL `https://api.nullplatform.com`, no path prefix. All calls go through the sibling np-api
script `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh` (auth via
`NP_API_KEY`/`NP_TOKEN`). Reports are stored per-organization, resolved from the token. `schema`,
`ui_schema`, and `queries` are stored verbatim (opaque) — the API does not validate their internal
shape.

| HTTP | Path | Body | `fetch_np_api_url.sh` invocation |
|---|---|---|---|
| GET | `/report?visibility=&category_id=&limit=&offset=` | — | `fetch_np_api_url.sh "/report?visibility=<v>&category_id=<c>&limit=<n>&offset=<o>"` |
| GET | `/report/<id>` | — | `fetch_np_api_url.sh "/report/<id>"` |
| POST | `/report` | full definition (`name` required) | `fetch_np_api_url.sh --method POST --data @<file> "/report"` |
| PATCH | `/report/<id>` | partial definition | `fetch_np_api_url.sh --method PATCH --data @<file> "/report/<id>"` |
| DELETE | `/report/<id>` | — | `fetch_np_api_url.sh --method DELETE "/report/<id>"` |
| POST | `/report/<id>/publish` | `{}` (ignored) | `fetch_np_api_url.sh --method POST --data '{}' "/report/<id>/publish"` |
| GET | `/report/<id>/versions` | — | `fetch_np_api_url.sh "/report/<id>/versions"` |
| POST | `/report/<id>/versions/<vid>/rollback` | `{}` | `fetch_np_api_url.sh --method POST --data '{}' "/report/<id>/versions/<vid>/rollback"` |
| POST | `/report/<id>/versions/<vid>/restore` | `{}` | `fetch_np_api_url.sh --method POST --data '{}' "/report/<id>/versions/<vid>/restore"` |
| GET | `/report_category` | — | `fetch_np_api_url.sh "/report_category"` |

In short: create a report with `POST /report`; update one with `PATCH /report/<id>`.

## Draft vs published

`create`/`update` write the **draft**. The draft is not visible as a published report until you call
`publish`, which snapshots the current draft as a new published version. `rollback` re-points the
published version to an earlier snapshot (draft untouched); `restore` copies a version back into the
draft (published untouched). Platform-visibility reports cannot be published/rolled back.

## Create/update body fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | **required** on create |
| `slug` | string | URL-friendly id |
| `description` | string | |
| `schema` | object | JSON Schema (see `json-schema-reference.md`) |
| `ui_schema` | object | DynamicForm layout — **snake_case key** |
| `queries` | object | query-id → `{ source, params?, target, mapping? }` |
| `visibility` | enum | `user` (default) \| `organization` \| `platform` |
| `category_id` | uuid\|null | from `fetch_np_api_url.sh "/report_category"` |
| `nrn_level` | enum | `organization` (default) \| `account` \| `namespace` \| `scope` |

## Note

Write access to `/report` requires `report` / `report/*` in the `ALLOWED_MODIFY` allowlist of
`${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh` (added by this skill's install).
