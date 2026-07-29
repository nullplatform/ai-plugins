# Workflow YAML cheat sheet

A minimal workflow has an `id`, a `name`, and a list of `steps`. Optional fields:
`description`, `inputs`, `variables`, `outputs`, `triggers`, `metadata`.

```yaml
id: my-workflow                # authoring-time only — the SERVER mints the real id (wf_…) on create
key: my-workflow               # optional stable slug (lowercase, ≤63); PUT /definitions/<key> UPSERTS — the GitOps handle
name: My Workflow              # required, human-readable
description: One-line summary  # optional

inputs:                        # optional; UI uses this for "Run with inputs"
  url:
    type: string
    default: "https://..."
  count:
    type: number

variables:                     # optional; mutable workspace under `variables.*`
  total:
    initialValue: 0

triggers:                      # optional; passive triggers (webhook, manual, etc.)
  - id: incoming
    type: trigger
    pluginType: webhook
    config:
      path: /my-hook
      method: POST

steps:                         # required; the DAG body
  - id: do-thing
    type: module               # module | decider | trigger
    pluginType: http-request
    inputs:
      url: "${{ workflow.inputs.url }}"
      method: GET
    # config:                  # static plugin configuration
    # dependsOn: [other-step]  # explicit edges (default: linear from previous step)
    # metadata:
    #   fanOutPerItem: true    # turn an executeMode=all plugin into per-item dispatch

outputs:                       # optional; surfaces variables.* at execution end
  result: "${{ variables.total }}"
```

## Expression language

Inside `${{ ... }}` you have:

| Root | What |
|---|---|
| `workflow.inputs.X` | Inputs the caller passed |
| `variables.X` | Variables (mutable across steps) |
| `steps.X.outputs.Y` | First item's `Y` field of step `X` |
| `steps.X.items[n].Y` | n-th item explicit access |
| `$item` | Current item when the step is in `each` mode |
| `$items` | The whole batch when the step is in `all` mode |
| `$itemIndex` | 0-based index of the current item |
| `execution.id` | The current execution id (e.g. for callback URLs) |
| `secrets.NAME` | Config-entry secret — always redacted in logs/steps/history |
| `vars.NAME` | Config-entry variable — plain shared value |

`${{ workflow.inputs.X }}` is the **workflow input** the caller/trigger passed.
Bare `${{ inputs.X }}` is the **step's own resolved inputs** — not the same thing.
Use `workflow.inputs.*` for run params; only reach for `inputs.*` when you mean the
current step's merged input.

Built-in functions: `lower(s)`, `upper(s)`, `length(x)`, `now()`, `uuid()`, `pluck(arr, key)`, `sum(arr)`, `join(arr, sep)`, `contains(arr, x)`. See `docs/guide/07-expressions.md` in the engine repo for the full list.

> The expression parser has **no array/object literals**. You cannot write
> `contains(["ok","done"], $item.status)`. Declare the array in `variables:` (with
> `initialValue`) and reference it: `contains(variables.okStatuses, $item.status)`.

### `default` vs `initialValue` at runtime

The runner applies `variables.X.initialValue` but does **not** apply an input's
`default` at run time (defaults are a UI/RUN-dialog affordance only). So any
runtime constant the trigger will not send must live in `variables:`, not as an
`inputs:` default — otherwise it resolves to undefined in expressions.

### Secrets & variables (config entries)

Credentials/API tokens NEVER go in YAML or step config — reference config
entries and set the values out-of-band (`/np-workflow config set`):

```yaml
- id: create-issue
  type: module
  pluginType: http-request
  config:
    url: "${{ vars.JIRA_BASE_URL }}/rest/api/3/issue"
    headers:
      authorization: "Bearer ${{ secrets.JIRA_TOKEN }}"
```

- `secrets.*` and `vars.*` are disjoint namespaces on purpose: `secrets.*`
  always implies redaction, so a secret can't leak by being referenced
  through the wrong root.
- Entries are scoped (folder path or `wf_…` id) with precedence
  `workflow → deepest folder → ancestors → /`. Same name at two scopes is
  shadowing, not merging.
- Publish-time: unresolved references produce a `CONFIG_ENTRY_UNRESOLVED`
  **warning** (set the value; no republish). Run-time: a missing referenced
  entry fails loudly with the entry name.

## Common patterns

### Iterate every item of a paginated source

```yaml
- id: fetch
  type: module
  pluginType: paginated-fetch
  config:
    mode: stream            # one item per page
    url: https://api.example.com/items?cursor=${{ steps.fetch.outputs.cursor }}

- id: each-item
  type: module
  pluginType: sub-workflow
  config:
    childWorkflowId: process-item
  metadata:
    fanOutPerItem: true     # per-item dispatch

- id: accumulate
  type: module
  pluginType: set-variable
  config:
    variable: total
    expr: "${{ variables.total + 1 }}"
  dependsOn: [each-item]
```

### Branch on a condition

```yaml
- id: route
  type: decider
  pluginType: conditional
  config:
    expr: "${{ steps.fetch.outputs.statusCode == 200 }}"
  outputPorts:
    - id: yes
    - id: no
```

`conditional` (if) and `case` steps are both `type: decider`.

- **`case` needs a UNIQUE output port per match** — you cannot collapse several
  statuses onto one port. To group values (e.g. "any of these statuses → success"),
  use a `conditional` with `contains(variables.okStatuses, $item.status)` and chain
  `conditional` steps for the remaining buckets, rather than a fat `case`.

### Pause until a signal arrives

```yaml
- id: wait-for-approval
  type: module
  pluginType: signal-wait
  config:
    channel: approval
    timeoutMs: 86400000
```

Resume with `POST /workflows/signals { workflowId, executionId, channel: "approval", payload: {...} }`.

Timeout handling for `signal-wait` (and module plugins in general):

- A `config.timeout` like `"2h"` normalizes to ms internally, but the schema wants
  a **string** — when POSTing an already-normalized JSON definition to the API,
  keep the timeout as a string, not the numeric ms value.
- **Do not route an edge off a module plugin's non-default output port** (e.g.
  signal-wait's `timeout` port). The worker's in-sandbox graph validation may not
  know module output ports and throws `CONNECTION_SOURCE_PORT_UNKNOWN` at **run
  time** even though create-time validation passed. Instead handle timeouts with
  `onTimeout: error` plus `error_handling.fallback_step` (see "Error handling &
  joins" below).

### Run an LLM agent (claude-code-agent)

```yaml
- id: agent
  type: module
  pluginType: claude-code-agent
  config:
    model: claude-sonnet-4-5
    systemPrompt: "You are a concise nullplatform assistant."
    userPrompt: "${{ workflow.inputs.task }}"
    # optional:
    skillsEnabled: [np-developer]    # nullplatform skills, if the deployment ships them
    env:                             # credentials handed to the agent's tools
      NP_TOKEN: "${{ secrets.np_token }}"
    # outputSchema: { type: object, properties: { summary: { type: string } } }
  dependsOn: [start]
```

`systemPrompt`/`userPrompt` are required; everything else is optional. Without an
`outputSchema` the reply comes back as plain text under `steps.agent.outputs.result`.
**Run `/np-workflow plugin claude-code-agent` to see the live config schema** —
optional fields and how the engine runs the agent are deployment-specific.

### code-exec that needs network or npm packages

`code-exec` runs inline and isolated by default (no network, no packages).
Declare **needs** in `config:` and the engine provisions an isolated runtime
(microVM) for the step automatically — where it runs is a deployment concern,
not something the YAML controls:

```yaml
- id: enrich
  type: module
  pluginType: code-exec
  inputs:
    repo: "${{ workflow.inputs.repo }}"
  config:
    network:
      allowedHosts: ["api.github.com"]        # outbound fetch allowlist
    libraries: ["zod@^3"]                      # npm name@range (scoped ok)
    code: |
      const res = await fetch(`https://api.github.com/repos/${$item.repo}`);
      const data = await res.json();
      return { ...$item, stars: data.stargazers_count };
```

Plain transform steps should NOT declare needs — inline execution is much
faster. (`runtime:` is the deprecated spelling of these fields; prefer
`network`/`libraries`.)

## Cron triggers

```yaml
triggers:
  - id: nightly
    type: trigger
    pluginType: cron
    config:
      schedule: "0 2 * * *"          # 5-field cron ONLY (no seconds field)
      timezone: America/New_York     # IANA name; defaults to UTC
```

- The config field is **`schedule`**, not `expression`. **6-field (seconds) cron
  is rejected at activation** — the error is loud, fix the expression to 5 fields.
- In production, activating the alias creates a **Temporal Schedule**; each tick
  starts the workflow through the normal execute route with
  `idempotencyKey: cron:<triggerId>:<tick>` — exactly one execution per tick,
  across replicas and retries. Overlap policy is SKIP: if a run is still going
  when the next tick lands, that tick is skipped (no pile-up).
- Deactivating the alias deletes the schedule — firing stops immediately, even if
  the pod that activated it is gone.
- Each firing passes `firedAt` (ISO-8601 scheduled tick) and `schedule` as
  workflow inputs.
- `catchUpMissed` is declared but **not yet enforced** — missed ticks while the
  system is down are skipped regardless.

## Error handling & joins (from real bugs)

These rules are subtle and cause deadlocks/false validation errors if ignored.

- **`error_handling.fallback_step` requires a DECLARED edge to its target.** Add an
  explicit edge `{ from: <step>, to: <fallback>, condition: "false" }` (or the
  authoring-form `dependsOn` equivalent) — otherwise the engine cannot route to the
  fallback even though the field is set.
- **Join semantics:**
  - `join_strategy: any` fires only on a **`completed`** predecessor. A **FAILED**
    edge does NOT satisfy `any`.
  - `join_strategy: all` waits for all **non-skipped** predecessors.
  - A `fallback_step` arrives as a **FAILED** edge, and `condition:false` /
    not-reached edges are **not reliably skipped**. So a single resolve node that
    mixes completed + failed predecessors will **deadlock**.
- **Use a DEDICATED single-predecessor resolve node per failure path** (one for
  discard, one for timeout, one for create-error, etc.) instead of one fan-in node
  that joins success and failure edges together.
- **Reentry/back-edge loops:** the looped (re-entered) node must declare
  `join_strategy: any`, otherwise it blocks waiting for the back-edge predecessor.

## Pitfalls (from real bugs)

- `code-exec` defaults to `executeMode: 'all'` — set `metadata.fanOutPerItem: true` for per-item.
- Don't reach into `steps.X.outputs` from another step's `config:` block; use `inputs:` or store via `variables.*`.
- For streaming-pagination, accumulate in `variables.X` via `set-variable`, never in `steps.X.outputs`.
- Re-entry/loop edges must target ports with `reentry: true` on the input port definition.
- Don't put `${{ Date.now() }}` or `Math.random()` in expressions — non-deterministic and replay-unsafe. Use `now()` / `uuid()` helpers.
- Deploying via API: POST/PUT `/workflows/definitions` with **normalized JSON**
  (camelCase). `latest` is auto-tracked — create a **named** alias and **activate**
  it; don't rely on `latest` for a live/test endpoint.
- When debugging, read `execution.error` — it surfaces the real cause (error type
  + message, including graph-validation issues) rather than a generic failure.

## Building plugins / triggers (engine-side, not YAML)

If you are extending the engine (writing a plugin or trigger), not just authoring
workflows:

- **Trigger plugins MUST honor `handler.transient` in `start()`.** When the handler
  is transient (a per-webhook rebind on a replica), **skip the activation
  side-effects** — just bind the handler and return. Otherwise webhooks fail with
  `503 "trigger not started"` on any replica that didn't perform activation.
  Webhooks are stateless and can land on any replica, so deploy worker + api from
  the **same commit**.
- **`validateConfig()` runs before `execute()`** — put config shape checks there.
- **Workflow-sandbox code must not import `node:async_hooks`/`ajv`** or call
  `Date.now()`/`Math.random()` in the workflow body (replay-unsafe; use
  `ctx.helpers.*` / DSL primitives).
- Make user-actionable failures **non-retryable `ApplicationFailure`s** so a bad
  config doesn't poison-pill the shared worker (the engine relies on this).
- **NP checklist trigger** auto-creates a `notification_channel` on activation —
  the activating token needs `notification_channel:create`. The Jira callback is a
  custom field holding the per-execution callback URL (`${{ execution.id }}`) plus
  an Automation rule, and the engine's `WORKFLOW_PUBLIC_BASE_URL` must be publicly
  reachable for the callback to land. (verify against engine for your deployment.)
