# Emitting an invoked inbox rule

An organization announces something nullplatform does not observe (a scanner finding, a budget alert, a
failed nightly job) by emitting one of its **invoked** inbox rules (`source: { kind: invoked }`). The rule
decides who receives it and what it says; the emission only names the resource and carries the data.

```
POST /communications/inbox_rule/<id>/emission
{ "nrn": "<resource the event is about>", "context": { "id": "<event id>", ...fields the rule's context_schema declares } }
```

From this session (the dry run needs no confirmation; confirm the real one first, SKILL.md "Confirm before any write"):

```
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @emission.json "/communications/inbox_rule/<id>/emission?dry_run=true"
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh --method POST --data @emission.json "/communications/inbox_rule/<id>/emission"
```

## Before wiring it

1. `GET /communications/inbox_rule/<id>`: the rule exists, `status: active`, `source.kind: invoked`, and its
   `visible_to` covers the NRN the pipeline will send. Note `context_schema.required`.
2. Run it once with `?dry_run=true` and a realistic body. Check `would_emit[].recipients`, `rejected` and
   `unreached`. Fix the data or the rule until the right readings reach someone.
3. Run it once with `"deliver_to": "me"` in the body to see the real notification in your own bell.

## The request

- **`nrn`**: valid, starting with `organization=<your org>`, and under the rule's `visible_to`. The most
  specific resource the event is about (an application rather than its namespace): access checks, Inbox settings
  per resource and followers are all resolved against it.
- **`context`**: must pass the rule's `context_schema`. `context.id` is required and is the idempotency key.
  `context.status`, if the rule declares it, is what `when.conditions` on `to.status` compare against.
- **`deliver_to: "me"`** (optional): send the first reading to the caller only, as a test. `?dry_run=true` wins
  over it.
- **Permission**: `notification_center:notification:create` over the `nrn`. A CI key needs nothing else.

## Idempotency: `context.id`

Emissions are idempotent by `context.id`, so a pipeline can retry on timeouts or 5xx without notifying anyone
twice.

- Same `id`, same `nrn` again → `200`, each `emitted[]` entry has `"existing": true`, nothing new is created.
- Same `id`, different `nrn` → `409`. Use a distinct id per resource.
- Build the id from the event itself (`finding-8812`, `<pipeline>-<run>-<job>`, `budget-<account>-<yyyy-mm>`),
  never from a timestamp or random value per attempt: that defeats the retry safety.
- For a rule with `delay` or `batch`, a second emission with the same id while the first is still pending is
  folded into it (`202` again, one delivery, carrying the first call's context and nrn).

## Responses

The np-api script prints only the body (SKILL.md "Read the body, not the status line"); the shapes are unambiguous.

| Status | Body | Meaning |
|--------|------|---------|
| `201` | `{ emitted: [{ id, as, recipients }], rejected }` | At least one notification was created. |
| `200` | `{ emitted: [{ ..., existing: true }], rejected }` | A retry of an earlier emission; nothing new. |
| `200` | `{ emitted: [], rejected }` | Nobody was left: conditions, Inbox settings or access checks removed everyone. Diagnose with `?dry_run=true`. |
| `202` | `{ deferred: "delay" \| "batch" }` | The rule delays or batches; delivery happens later. |
| `200` | `{ would_emit, rejected, deferred?, unreached? }` | `?dry_run=true`. Nothing written. A `would_emit[]` entry with `existing: true` means this `context.id` was already emitted for this `nrn`. |
| `201`/`200` | `{ emitted, rejected: 0, test: true }` | `deliver_to: "me"`. `200` with `emitted: []` when the conditions rejected the context. |
| `400` | `{ message, errors: [{ path, message }] }` | Context fails `context_schema` (`/context/...`), NRN not valid or outside your organization (`/nrn`), or the rule is not invoked. |
| `404` | `{ message, id, detail }` | Rule unknown, deactivated, or its `visible_to` does not cover the `nrn`. |
| `409` | `{ message: "This context id was already emitted for another resource", id, detail }` | Not retryable: change the id. A dry run answers it too. |
| `401` | `{ message }` | The key's role lacks `notification_center:notification:create` on that `nrn`. |

`recipients` and `rejected` are counts, never user ids. `rejected` counts recipients dropped because they cannot
see the resource at `nrn` (the emission names recipients through the context, so every one is verified).

A reading that reached nobody is left out of `emitted`. On a `201`, followers (people who chose Everything for
the rule on that resource or above) are added when the rule allows it.

## In a pipeline

Retry policy for the step: retry `5xx` and network errors with backoff, reusing the same body; treat `200`,
`201` and `202` as success; fail the step on `400`, `401`, `404` and `409` (retrying them gives the same answer).
Never fail a deployment because a notification could not be sent unless the user asks for that.

Credentials: an API key of the organization whose role grants `notification_center:notification:create` on the
resources the pipeline emits for, stored as a CI secret. Exchange it for an access token as the pipeline already
does for other nullplatform calls, or let the CLI do it.

CLI, when the user's CLI has `np communications` (it reads the key from `NULLPLATFORM_API_KEY` or `--api-key`):

```
np communications inbox rule emission create --id acme.security_finding --body emission.json
np communications inbox rule emission create --id acme.security_finding \
  --body '{"nrn": "organization=1:account=2:namespace=3:application=4", "context": {"id": "finding-8812", "service": "payments-api", "summary": "CVE-2026-1234", "owner_id": 50}}'
```

The CLI does not send `dry_run` (the generator drops query parameters on POST); test with `"deliver_to": "me"`
in the body instead. When the user's pipeline calls the HTTP API directly, the request is the one above with
`Authorization: Bearer <access token>` and `Content-Type: application/json`; the dashboard's rule editor
(**Emission** tab) shows a ready-to-run command for each rule.

From a nullplatform workflow, the emission is one HTTP step with the same body; use `/np-workflow` for the
workflow itself and keep the step's `context.id` derived from the workflow's input.

## Checklist to hand the user

- [ ] Rule is active, invoked, and its scope covers the NRNs the pipeline sends.
- [ ] `context.id` is stable per event and distinct per resource.
- [ ] Dry run shows the expected readings and recipient counts; send-test looks right in the bell.
- [ ] The CI key grants `notification_center:notification:create` and lives in the CI secret store.
- [ ] Retries reuse the body; `400/401/404/409` fail the step without retrying.
