---
name: np-workflow
description: Build, publish, run, and debug workflows on the Nullplatform workflow engine via REST API. Use when the user asks to "create a workflow", "publish a workflow", "list workflow plugins", "trigger a webhook", "check an execution", "manage workflow secrets", "scaffold a workflow YAML", or any workflow-engine task. Requires NP_TOKEN or NP_API_KEY (same as np-api); NP_WORKFLOW_URL only for self-hosted engines (defaults to api.nullplatform.com).
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/*.sh)
---

# np-workflow

Skill to interact with a deployed Nullplatform workflow engine. Talks REST against `$NP_WORKFLOW_URL` and authenticates with the same credentials as `np-api` (`NP_TOKEN` or `NP_API_KEY`).

## Configuration

| Variable | Required? | Default | Purpose |
|---|---|---|---|
| `NP_WORKFLOW_URL` | no | `https://api.nullplatform.com` | Base URL of the workflow engine. The production engine is mounted publicly behind the NP control plane — override only for self-hosted deployments |
| `NP_WORKFLOW_BASE_PATH` | no | `/workflows` | REST prefix the engine serves under. Match this to the engine's `basePath` config — override only when the deployment lives behind a path-rewriting proxy |
| `NP_TOKEN` or `NP_API_KEY` | yes | — | Resolved by the np-api skill (which this skill depends on). NP_API_KEY is exchanged + cached in `~/.claude/` |

This skill delegates ALL auth resolution to `np-api/scripts/fetch_np_api_url.sh`; it does not implement its own token logic. `np-api` MUST be installed alongside `np-workflow` (the `np-workflow-craft` bundle includes both).

## URL conventions

The engine follows the Nullplatform API style:
- The host serves the workflow engine, the prefix `/workflows` namespaces the resources under it (e.g. `${NP_WORKFLOW_URL}/workflows/definitions/:id`).
- Infra is at root: `/health`, `/ready`, `/metrics`, `/openapi.json`.
- **Identity is NOT served by the engine.** The bearer token carries the identity; if you need to inspect it, decode the JWT or hit the Nullplatform auth API directly.

In this skill's scripts you write **bare resource paths** (without the `/workflows` prefix) and `workflow-api.sh` adds it. So `workflow-api.sh GET /definitions/abc` resolves to `${NP_WORKFLOW_URL}/workflows/definitions/abc` on the wire.

## Critical Rules

1. **NEVER write directly to the workflow API with raw curl.** Always go through `${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/workflow-api.sh` so auth, base URL, and error handling stay consistent.
2. **The engine URL defaults to the public NP API** (`api.nullplatform.com`, engine under `/workflows`). Only set `NP_WORKFLOW_URL` for self-hosted deployments — never guess a URL; if the default 404s, ask the user.
3. **Publishing is three idempotent REST calls** (create/update workflow → set alias → activate). Use `publish.sh`; do not skip the activate step unless the user passes `--no-activate`.
4. **Webhook URLs are token-bearing and alias-scoped** — the trailing segment is an opaque capability token minted at activation; a registration without a token has NO reachable URL (re-activate the alias to mint one). Always surface URLs via `GET /workflows/triggers?workflowId=...&status=active`. Never invent webhook paths.
5. **Put node fields in `config:`, run params on the trigger.** See "Authoring: config vs inputs" below — getting this wrong silently produces a node with empty fields in the canvas and a workflow whose RUN dialog asks for nothing.
6. **Retried starts need an `idempotencyKey`.** `POST .../execute` accepts `"idempotencyKey": "<unique-per-logical-event>"` — the engine guarantees ONE execution per `(workflow, key)` via a storage unique constraint (holds across API replicas). First call → 202 + new execution; any repeat → 200 + the SAME execution with `"deduplicated": true`. Use it whenever the caller may retry (queues, webhook redeliveries, cron overlap). The Slack trigger applies this automatically (`slack:<team_id>:<event_id>`); custom trigger plugins pass `ITriggerHandlerContext.idempotencyKey`. The key is visible on the execution record and in the canvas observer.
7. **New non-trivial workflow → START FROM THE CORPUS, not from scratch.** `github.com/nullplatform/workflows` holds production-grade suites (cost, deploy, governance, runtime-lifecycle, ami-drift) WITH their E2E tests and system docs. Clone it, copy the nearest suite's YAML + test file, and adapt — the suites encode the house patterns (streaming pagination, metadata spine, item idempotency, deciders/joins, error routing). Use `scaffold` only for trivial one-or-two-step workflows.
8. **Validate and test locally with the kit before publishing.** `npx @nullplatform/workflow-kit` (bin `np-workflow`) — see "Local kit" below. A workflow that passes `validate` + its vitest E2E locally is what runs hosted; iterating against the live API is the slow path.

## Local kit: `npx @nullplatform/workflow-kit`

The public npm package runs the SAME engine + validation + test harness the
platform uses, locally. No install needed beyond node 20+:

```bash
npx np-workflow validate my-workflow.yaml     # parse/normalize/schema + DUAL graph pass
                                              # ("runtime-parity" findings = would pass submit, fail hosted)
npx np-workflow publish my-workflow.yaml --alias live   # validate → new revision → alias repoint+activate
npx np-workflow run <id> --inputs '{"k":"v"}' # execute on the platform + poll to terminal
npx np-workflow normalize my-workflow.yaml    # canonical IWorkflowDefinition JSON
```

Auth: same envs as this skill (`NP_API_KEY` or `NP_TOKEN`).

E2E tests (vitest) import the harness from the kit — plugin-level stubs, real
engine underneath:

```ts
import { runWorkflowE2E } from '@nullplatform/workflow-kit/test';
```

Every test in the corpus is an example of the pattern; the full loop
(author → validate → test → publish) is documented in the corpus's
`AUTHORING.md`. Prefer `publish.sh` (this skill) OR `np-workflow publish` —
they are equivalent; use whichever is already in the user's flow.

## Authoring: config vs inputs (READ before writing a step)

The engine and canvas distinguish three places a value can live. Putting a value
in the wrong one is the #1 authoring bug (empty canvas fields, RUN prompts for
nothing, code-exec/log/agent steps that fail because they read from `config`).

- **A node's own `configSchema` fields → `config:`.** `sql` (np-lake-query),
  `code` (code-exec), `url`/`method`/`headers` (http-request), `model` +
  `systemPrompt` + `userPrompt` + `outputSchema` (claude-code-agent),
  `level`/`message` (log), etc. The canvas renders these in their proper field,
  and `code-exec` / `log` / `claude-code-agent` read **only** from `config` (not
  from the input merge). `config` resolves `${{ ... }}` expressions, including
  cross-step `${{ steps.X.outputs.* }}`, `${{ workflow.inputs.* }}`,
  `${{ secrets.* }}`. Run `plugins.sh describe <type>` to see which fields are
  config (and which are `x-advanced`, i.e. collapsed).
- **Data a `code-exec` sandbox reads via `$item` → `inputs:`.** The sandbox's
  `inputs`/`$item` binding is the step's `inputs` only. So pass `row`,
  `payload`, etc. under `inputs:` and read them as `$item.row`. (`code` stays in
  `config`.)
- **Run-time parameters → declared on the trigger, not as `variables`.** To make
  the **RUN dialog prompt** for values, declare them on the **manual trigger's
  `config.inputs`** (`{ <name>: { type, required, description, default,
  placeholder } }`) and reference them in steps as `${{ workflow.inputs.<name> }}`.
  `variables:` is internal mutable state with an `initialValue` — it does NOT
  prompt at run. A workflow whose params are `variables` will show an empty RUN
  dialog.

## Secrets & variables (config entries)

Credentials and shared constants NEVER go in YAML. Reference **config
entries** instead and manage them via `/np-workflow config …`:

- `${{ secrets.NAME }}` — always redacted in logs/steps/history; the value is
  **write-only** (no API returns it; rotate by re-setting).
- `${{ vars.NAME }}` — plain shared value, readable.

Entries live at ONE scope — a folder path (`/`, `/jira`) or a `wf_…` workflow
id — and resolve with precedence `workflow → deepest folder → ancestors → /`
(same name at two scopes = shadowing, most specific wins; the `effective`
subcommand shows which scope won). Publishing a definition that references an
entry with no value at any visible scope succeeds with a
`CONFIG_ENTRY_UNRESOLVED` **warning** (surfaced by `publish.sh`) — set the
value and re-run, no republish needed. At runtime a missing referenced entry
fails with a clear error naming it, never a silent `undefined`.

`publish.sh` normalizes authoring YAML (steps list + `dependsOn`) into the
canonical engine shape (steps keyed by id + `connections`) and sends the create
as a RAW body / updates as `{definition:…}` — author in the natural list form.

## Command: $ARGUMENTS

| Command | Action |
|---|---|
| `/np-workflow ping` | Verify the URL is a workflow engine + token works |
| `/np-workflow plugins [filter]` | List plugins (filter is substring or `--type trigger`) |
| `/np-workflow plugin <name>` | Show full plugin descriptor + examples |
| `/np-workflow list` | List workflows on this deployment |
| `/np-workflow describe <id>` | Workflow + revisions + aliases + webhook URLs |
| `/np-workflow scaffold <id> [template]` | Starter YAML for TRIVIAL workflows only — for anything real, copy a suite from `github.com/nullplatform/workflows` instead (rule 7) |
| `/np-workflow publish <file.yaml> [--alias=live] [--no-activate]` | Create/update + activate |
| `/np-workflow run <id> [--alias=live] [--input k=v ...] [--timeout=120]` | Start manual execution + poll until done |
| `/np-workflow trigger <id> [--alias=live] [--trigger=<tid>] [--body='{...}']` | Fire the public webhook URL |
| `/np-workflow execution <eid>` | Show execution record + state + steps |
| `/np-workflow executions [workflow-id]` | List recent executions (optionally scoped) |
| `/np-workflow config list --path=/jira \| --workflow=<ref> [--ancestors]` | Entries defined at a place; `--ancestors` = whole chain with winner/shadowed flags |
| `/np-workflow config set <name> --path=P\|--workflow=W [--secret]` | Create/rotate an entry (value via stdin) |
| `/np-workflow config get\|rotate\|delete <cfg_id>` | Inspect / rotate / delete by id |

---

## If $ARGUMENTS is empty or "help" → Show overview

Print the table above and mention that auth + URL come from environment variables (`NP_WORKFLOW_URL`, `NP_TOKEN`/`NP_API_KEY`). Recommend `/np-workflow ping` first.

---

## If $ARGUMENTS is "ping" → Sanity check

Run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/ping.sh
```

Report the API version, plugin count, and whether `whoami` resolves. The URL
defaults to the public `api.nullplatform.com`; for a self-hosted engine:

```bash
export NP_WORKFLOW_URL='https://workflow.example.np.io'
```

If auth fails, fall back to the np-api guidance:

```bash
export NP_TOKEN='eyJ...'        # bearer token
# or
export NP_API_KEY='...'         # API key, exchanged automatically
```

---

## If $ARGUMENTS starts with "plugins" → Catalog browsing

Two modes:

**List (default):**

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/plugins.sh <rest of args after "plugins">
```

Accepts `--type trigger|module|decider`, `--q <substring>`, or a bare substring to filter on category/name.

**Describe one:**

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/plugins.sh describe <name>
```

When the user mentions a plugin by name without saying "describe", default to listing first then ask whether to drill in.

---

## If $ARGUMENTS starts with "plugin " → Describe single plugin

Treat as alias for `plugins describe <name>`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/plugins.sh describe <name>
```

---

## If $ARGUMENTS starts with "list" → Workflows index

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/workflows.sh list
```

---

## If $ARGUMENTS starts with "describe " → Workflow detail

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/workflows.sh describe <id>
```

The output includes active triggers with their webhook URLs.

---

## If $ARGUMENTS starts with "scaffold " → New YAML

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/scaffold.sh <id> [template]
```

Templates: `hello-http` (default), `webhook-echo`, `signal-wait`, `claude-agent`. After scaffolding remind the user to edit the file, then publish.

For details on the YAML grammar see @${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/docs/yaml-cheat.md.

---

## If $ARGUMENTS starts with "publish " → Push to the engine

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/publish.sh <file.yaml> [flags]
```

If the response is HTTP 422 with `errors[]`, present the validation errors to the user. Common causes: missing `id`, unknown `pluginType`, expression referencing a step that doesn't exist, missing `dependsOn` chain.

If the server is multi-org and the user's token resolves to org X but the YAML hard-codes a different `organizationId`, prefer **removing** the org from the YAML so the server takes it from the identity.

---

## If $ARGUMENTS starts with "run " → Manual execution

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/run.sh <workflow-id> [flags]
```

This polls until terminal. If you only need to start without waiting, use `workflow-api.sh POST /definitions/<id>/execute` directly (paths inside the skill are bare resource names — `workflow-api.sh` prepends `/workflows`).

---

## If $ARGUMENTS starts with "trigger " → Fire webhook

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/trigger.sh <workflow-id> [flags]
```

For signed webhooks (HMAC), pass `--header 'X-Hub-Signature-256: ...'` etc. The response carries no executionId by design — use `/np-workflow executions <workflow-id>` to find the resulting run.

---

## If $ARGUMENTS starts with "execution " → Inspect one run

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/execution.sh <execution-id>
```

Shows the record (`status`, timing) plus the live state document (per-step status, item counts, and any error).

---

## If $ARGUMENTS starts with "executions" → List runs

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/execution.sh list [<workflow-id>]
```

Optionally pass a workflow id to scope. Note: terminal executions are pruned
after the deployment's retention window (default **7 days**) — an old
execution returning 404 is expected, not a bug.

---

## If $ARGUMENTS starts with "config" → Secrets & variables

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/config.sh <list|effective|set|delete> [...]
```

Entries have a server-minted `cfg_…` id; a place is `--path=` (folder) XOR
`--workflow=` (wf_ id or client key).

- `config list --path=/jira | --workflow=<ref>` — entries DEFINED at that
  place; var values shown, secret values never (write-only by design).
  Add `--ancestors` to see the whole chain a workflow (or folder) sees:
  each row shows its origin place and `winner`/`shadowed` — this is the
  effective view AND the shadowing debugger in one.
- `config set <name> --path=P|--workflow=W [--secret]` — idempotent
  create/rotate by (name, place). **Pass the value on stdin**
  (`printf '%s' "$TOKEN" | … config.sh set …`) so secrets never land on
  argv or in shell history. `--value=` exists for non-sensitive vars.
  `secret` flag and `name` are immutable (delete + recreate to change).
- `config get <cfg_id>` / `config rotate <cfg_id>` (value via stdin) /
  `config delete <cfg_id>` — id-addressed operations; ids come from `list`.

When a user pastes a credential to store, prefer stdin, confirm the place
(folder for shared, workflow for one workflow), and NEVER echo the value back.

---

## Agent node (LLM agent)

To run an LLM agent inside a workflow, look for an agent plugin in the engine's
catalog — typically **`claude-code-agent`** (Claude), with a generic `agent`
plugin as the multi-provider reference. **Availability is per-deployment**, so
discover it dynamically instead of assuming:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/plugins.sh --q agent
${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/scripts/plugins.sh describe claude-code-agent
```

The descriptor's `configSchema` is **authoritative** — it tells you the required
fields and the optional ones, so always read it (`plugin describe`) rather than
hardcoding config. How the engine actually runs the agent (in-process, sandbox,
which models, which credentials) is a **deployment concern of the engine**, not
something this skill configures — if the plugin shows up in `/plugins`, you can
use it.

Typical config you'll see on `claude-code-agent`: `systemPrompt` + `userPrompt`
(required, free text with `${{ }}` expressions), `model`, `env` (credentials for
the agent's tools, e.g. `${{ secrets.np_token }}`), `skillsEnabled` /
`mcpServersEnabled`, `outputSchema` (optional — omit to get plain text under
`result`), and `toolPlugins`. Scaffold a starter with
`/np-workflow scaffold <id> claude-agent`, then `plugin describe` to confirm the
exact fields for your deployment.

## Reference

- @${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/docs/api-shapes.md
- @${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/docs/yaml-cheat.md
- @${CLAUDE_PLUGIN_ROOT}/skills/np-workflow/docs/state-and-persistence.md —
  choosing between variables / nodeContext / catalog metadata / action items /
  config entries; the metadata-as-data-spine pattern for durable state.
- **Example corpus**: `github.com/nullplatform/workflows` — production-grade
  reference suites (cost tracking + right-sizing, progressive deploy,
  governance gates, AMI drift). When authoring a non-trivial workflow, find
  the nearest suite there and copy its patterns (streaming pagination,
  metadata spine, item idempotency, deciders/joins) instead of inventing.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ping` returns non-200 | Overridden URL isn't a workflow engine, or DNS/VPN | Default is `api.nullplatform.com`; verify any override has no path suffix, network OK |
| `whoami` returns 401 | Token invalid/expired | Re-export `NP_TOKEN` or refresh via NP_API_KEY |
| Publish 422 | YAML failed validation | Fix `errors[]`; re-run `publish` |
| Publish 403 | Token lacks `workflow:write` | Use an admin token or update RBAC |
| `trigger` reports no webhook | Alias not activated, or trigger pluginType isn't `webhook` | `/np-workflow describe <id>` to inspect alias state |
| Execution stuck `running` | Waiting on a signal | `execution <eid>` shows pending-signals |
| Webhook returns `503 "trigger not started"` | Replica got a transient handler it didn't activate; or worker/api deployed from different commits | Trigger plugin must honor `handler.transient` in `start()`; deploy worker + api from the same commit |
| `CONNECTION_SOURCE_PORT_UNKNOWN` at run time (passed create-time validation) | Edge routed off a module plugin's non-default output port (e.g. signal-wait `timeout`); in-sandbox graph validation doesn't know module ports | Don't route off module ports — use `onTimeout: error` + `error_handling.fallback_step`. See yaml-cheat "Error handling & joins" |
| Execution failed, cause unclear | — | Read `execution.error` — it carries the real error type + message + graph-validation issues. A single resolve node joining success+failure edges deadlocks; use a dedicated resolve node per failure path (yaml-cheat) |
| Old execution 404s | Terminal executions pruned after the retention window (default 7 days) | Expected; export what you need before it ages out |
| Trigger shows `(no public URL)` after publish | Token-only webhook routing: registrations without a token have no URL | Re-activate the alias (`publish.sh` does this) to mint the token |
| Alias activation fails on a cron trigger | 6-field (seconds) cron expression — Temporal Schedules only accept 5 fields | Rewrite `config.schedule` as 5-field cron; see yaml-cheat "Cron triggers" |
| Publish prints `CONFIG_ENTRY_UNRESOLVED` | A referenced `secrets.X`/`vars.X` has no value at any visible place | `config set X --path=…|--workflow=… [--secret]` — no republish needed |
| `config` routes return 503 | Deployment has no NP storage backend configured (`WORKFLOW_NP_STORAGE_API_KEY` unset) | Deployment concern — flag it to the operator |
| Step failed with `CONFIG_ENTRY_UNRESOLVED` at runtime | Entry referenced by the step has no value visible to THIS workflow | `config list --workflow=<ref> --ancestors` to see what resolves, then set at the right place |
