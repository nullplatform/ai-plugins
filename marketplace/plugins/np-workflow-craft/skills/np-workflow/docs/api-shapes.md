# Workflow Engine REST API — quick reference

This document captures the request/response shapes used by the `np-workflow` skill scripts. It is intentionally terse — pair it with [`14-rest-api-quickstart.md`](https://github.com/nullplatform/workflow-system-demo/blob/main/docs/guide/14-rest-api-quickstart.md) in the engine repo for prose.

## Authentication

Every protected endpoint accepts `Authorization: Bearer <token>` where the token can be:

- `NP_TOKEN` (a JWT issued by Nullplatform's RBAC/Cognito or a dev HS256 token)
- A token exchanged from `NP_API_KEY` via `POST https://api.nullplatform.com/token` (cached under `~/.claude/.np-token-<hash>.cache`)

`workflow-api.sh` delegates this entirely to `np-api/scripts/fetch_np_api_url.sh` (via the `NP_API_BASE_URL` + `NP_API_BASE_PATH` env overrides). Single source of truth for auth across all NP skills.

`GET ${NP_WORKFLOW_BASE_PATH:-/workflows}/metadata` is anonymous — no token required.

## Base path

All paths in this skill are written **without** the `/workflows` prefix. `workflow-api.sh` prepends `NP_WORKFLOW_BASE_PATH` (default `/workflows`) before issuing the request. To target an engine deployed behind a path-rewriting proxy (e.g. `/wf/`), set:

```bash
export NP_WORKFLOW_BASE_PATH=/wf
```

Internally a call like `workflow-api.sh GET /plugins` resolves to `GET ${NP_WORKFLOW_URL}${NP_WORKFLOW_BASE_PATH}/plugins`.

## Discovery

| Method | Path | Purpose |
|---|---|---|
| GET | `/workflows/metadata` | Anonymous capabilities snapshot |
| GET | `/workflows/plugins` | List plugin descriptors (`?type=`, `?q=`, paginated) |
| GET | `/workflows/plugins/:name` | Single descriptor (configSchema, examples, ports, executeMode) |
| GET | `/workflows/triggers?workflowId=&status=active` | Trigger bindings with `runtimeMetadata.webhookUrl` |

## Workflow refs: `wf_` ids vs client keys

Every `/definitions/:ref` param resolves deterministically (never a fallback
chain):

- `wf_…` → server-minted immutable id (returned on create; safe in URLs/UI).
- lowercase slug matching `^[a-z0-9][a-z0-9-]{0,62}$` → the **client-chosen
  key** from the definition (`key:` field), org-scoped. `PUT /definitions/<key>`
  **upserts**: creates on first push, new revision after — ideal for GitOps.
- anything else → legacy id lookup.

The alphabets are disjoint (keys have no underscore/uppercase), so a ref is
never ambiguous.

## Authoring + publishing

| Method | Path | Body | Purpose |
|---|---|---|---|
| POST | `/workflows/definitions` | `{ definition: {...} }` | Create workflow (new id) at revision 1 |
| PUT | `/workflows/definitions/:id` | `{ definition: {...} }` | Push a new revision (N+1) |
| GET | `/workflows/definitions/:id` | — | Workflow + latestRevision |
| GET | `/workflows/definitions/:id/revisions` | — | All revisions |
| GET | `/workflows/definitions/:id/revisions/:n` | — | Specific revision definition |
| GET | `/workflows/definitions/:id/aliases` | — | All aliases + triggerStates |
| PUT | `/workflows/definitions/:id/aliases/:alias` | `{ revision: N }` | Point an alias at a revision |
| POST | `/workflows/definitions/:id/aliases/:alias/activate` | `{}` | Activate (registers triggers) |
| POST | `/workflows/definitions/:id/aliases/:alias/deactivate` | `{}` | Deactivate |
| POST | `/workflows/definitions/:id/validate` | `{ definition }` | Validate against the server's schema |

A `publish` is the orchestration of:

1. `POST /workflows/definitions` (or `PUT /workflows/definitions/:id`) → returns `{ id, revision, ... }`
2. `PUT /workflows/definitions/:id/aliases/:alias { revision }` → idempotent
3. `POST /workflows/definitions/:id/aliases/:alias/activate` → idempotent

## Execution lifecycle

| Method | Path | Body | Purpose |
|---|---|---|---|
| POST | `/workflows/definitions/:id/execute` | `{ alias?, inputs? }` | Start execution → `{ execution: {...} }` |
| GET | `/workflows/executions?workflowId=&status=&limit=&offset=` | — | List executions (default sort: `started_at DESC`) |
| GET | `/workflows/executions/:id` | — | Lifecycle record |
| GET | `/workflows/executions/:id/state` | — | Step state, storage-backed (works on BOTH runtimes; no executor round-trip) |
| GET | `/workflows/executions/:id/steps` | — | Step records (live-reported by activities as they start/complete) |
| GET | `/workflows/executions/:id/pending-signals` | — | Signal envelopes the run is waiting on |
| POST | `/workflows/signals` | `{ workflowId, executionId, channel, payload }` | Resume a signal-wait |
| POST | `/workflows/executions/:id/cancel` | `{}` | Best-effort cancellation |

Executions are subject to a **retention window** (deployment-configured,
default 7 days): terminal executions plus their steps/logs are pruned after
it. Trigger steps run in-sandbox and produce no step rows — a missing trigger
row in `/steps` is expected.

## Config (secrets + variables)

Referenced from YAML as `${{ secrets.NAME }}` / `${{ vars.NAME }}`. Entries
are addressed by a server-minted `cfg_…` id; the pair (name, place) is
unique, where the place is a folder `path` XOR a `workflow` ref (wf_ id or
client key). Precedence `workflow → deepest folder → ancestors → /`.

| Method | Path | Body | Purpose |
|---|---|---|---|
| POST | `/workflows/config` | `{ name, value, secret, path\|workflow }` | Idempotent upsert by (name, place): 201 created / 200 rotated. `secret` + `name` immutable |
| GET | `/workflows/config/:id` | — | One entry; `value` only for vars (secrets are write-only) |
| PATCH | `/workflows/config/:id` | `{ value }` | Rotate by id |
| DELETE | `/workflows/config/:id` | — | Remove (bodyless 204 on success) |
| GET | `/workflows/config?path=/jira` | — | Entries DEFINED at that folder |
| GET | `/workflows/config?workflow=<ref>` | — | Entries DEFINED at that workflow |
| GET | `…&ancestors=true` | — | The whole chain (works on BOTH axes), each row with its origin place + `effective: true\|false` (winner vs shadowed) |
| GET | `/workflows/executions/:id/config` | — | Runtime resolution (execution service token only) |

503 on these routes ⇒ the deployment has no NP storage backend configured.

## Webhooks

Webhook triggers expose their public URL via `runtimeMetadata.webhookUrl` on the trigger binding once the alias is activated. The URL is **token-bearing and alias-scoped**: `…/<wfId>-<slug>/<alias>/<token>` where the trailing segment is an opaque capability token minted at activation (the routing is token-only — the id/slug segments are cosmetic, and a registration without a token has NO reachable URL until its alias is re-activated). `live` and `test` aliases of the same workflow get different URLs. POST to the URL with whatever body the trigger expects; the engine creates an execution asynchronously and the webhook response carries no executionId.

## Common errors

| Status | Meaning |
|---|---|
| 401 | Token missing / invalid / expired |
| 403 | Token is valid but the identity lacks the action's permission |
| 404 | Workflow id, alias, revision, or execution not found |
| 409 | Idempotency conflict (e.g. re-activating with a different revision) |
| 422 | Definition failed schema validation; inspect `errors[]` |
| 503 | Route requires a runtime collaborator (executor/triggerManager) that isn't wired |

Bodies are RFC 7807 Problem Details:

```json
{
  "type": "https://workflow.nullplatform.com/problems/validation-failed",
  "title": "Validation failed",
  "status": 422,
  "detail": "...",
  "errors": [{ "path": "steps.0.pluginType", "message": "required" }]
}
```
