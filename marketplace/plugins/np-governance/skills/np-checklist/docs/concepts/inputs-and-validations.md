# Manual item inputs & validation rules

> Feature branch status (2026-07-31): implemented on
> `main-approval-api#feat/manual-inputs-validations`, frontend PR
> admin-dashboard#2073, workflow plugins PR governance-workflow-system#150.
> Remove this note once merged.

Manual items can declare **structured inputs** (what the user must fill in)
and **validation rules** (whether the submission *counts*). Both live in the
template definition and are snapshotted into the run like everything else.

## `inputs` — JSON Schema + optional JSONForms ui_schema

```yaml
- id: cab_approval
  type: manual
  behavior: gate
  title: Change Advisory Board approval
  inputs:
    schema:                      # JSON Schema draft-07; top-level type MUST be object
      type: object
      required: [cab_ticket, risk_level]
      properties:
        cab_ticket: { type: string, title: CAB ticket, pattern: "^CAB-\\d{4}-\\d{4}$" }
        risk_level: { type: string, title: Risk level, enum: [low, medium, high] }
    ui_schema:                   # OPTIONAL — JSONForms UISchema, NOT RJSF "ui:*" keys
      type: VerticalLayout
      elements:
        - { type: Control, scope: "#/properties/cab_ticket" }
        - { type: Control, scope: "#/properties/risk_level" }
```

- Same convention as service specifications / metadata specs; the admin UI
  renders it with `DynamicForm` (JSONForms engine). **`"ui:placeholder"`-style
  RJSF keys break rendering** ("No applicable renderer found"); omit
  `ui_schema` to get an auto-generated vertical layout.
- Save-time: schema compiled with ajv (`input.schema.invalid`), top-level
  `type: object` enforced (`input.schema.type`).
- Submit-time: posted `inputs` values validated with ajv; failures come back
  as `422` with `errors[]` entries `input.<field>.required` /
  `input.<field>.invalid`.
- Values persist on the item state (`input_values` on reads) — audit trail.
- `require_comment: true` still works and is independent of inputs.

## `validations` — same query language as policies

```yaml
  validations:
    - id: four_eyes
      rule: { actor.user_id: { $ne: "$approval.requested_by.id" } }
      message: Someone other than the requester must confirm
    - id: peer_role
      rule: { actor.effective_roles: { $in: [developer, admin] } }
      message: Requires developer or admin on this scope
    # Phase 2 — delegated to an external system (workflow). XOR with `rule`.
    - id: jira_check
      external: { kind: jira-ticket-check, inputs: { ticket: "{{ inputs.ticket }}" } }
      message: The external system did not confirm the ticket
```

Key semantics (all server-side, evaluated on item submit):

- **Validations gate ONLY the positive outcome.** They run when a user
  submits `status: passed`. A `failed` (reject) or revert-to-`pending`
  submit applies without running rules — rejecting must never be blocked.
- Rule document roots: `inputs.*`, `actor.*` (`user_id`, `effective_roles`
  resolved for the approval's NRN), `approval.*`, `run.items.<id>.*`, plus
  the same context catalog conditions use. `$path` string values
  (e.g. `"$approval.requested_by.id"`) are resolved as value references
  before evaluation.
- Failures → `422` with `errors[]` (`validation.<id>.failed` + the
  template's `message`). Authorization stays separate: a rule failure is
  never a `403`.
- `aggregation: any | all` on groups composes with this — e.g. "either a
  peer developer or an account admin signs off" is a group with
  `aggregation: any` and one role-rule child each. `any` + `override`
  children is rejected at save (`group.aggregation.any_with_override`).

## Phase 2 — external validations and the `validating` status

Only items with `external` validations ever enter the transient
`validating` status:

```
pending → (submit passed, sync rules ok) → validating
validating → all external passed  → the submitted status (e.g. passed)
validating → any external failed  → pending (failure recorded on the card)
validating → dispatch failed      → pending (validations.<id>.status = dispatch_failed)
```

Dispatch rides the same notification-channel machinery as external items but
with a **different action and contract**:

| | external item | external validation |
|---|---|---|
| Action | `checklist:item:dispatched` | `checklist:item:validation_dispatched` |
| Payload extra | — | `validation_id` |
| Callback | `PATCH …/items/{itemId}` body `{status,…}` | `POST …/items/{itemId}/validations/{validationId}` body `{passed, message?, details?}` |
| Token scope | item | validation (`scope: "validation"`) |
| Item's fate decided by | the workflow | the approval-api |

Workflow-system side (PR #150): subscribe with `np-checklist-trigger`
setting `action: checklist:item:validation_dispatched` (the trigger
surfaces `validationId`, `callbackUrl`, `callbackToken`, `inputs`), do the
check with any plugin (`jira-get-issue`, `http-request`, …), and close with
**`np-checklist-validation-resolve`** (`passed: true|false`). If no channel
matches the kind, the dispatcher records `dispatch_failed` and the item
reverts to `pending` — visible on the item card, nothing hangs.

## Read surface

Run reads expose per item: `inputs` (the schema declaration),
`input_values` (what the user submitted), `validations` (summary of
declared rules), `validation_states` (per-validation status/message for
externals), and `resolved_by` (`{user_id, effective_roles, at}` snapshot of
who resolved a manual item — every actor interaction is attributed).

## Common mistakes

1. **RJSF-style `ui_schema`** — breaks the renderer; use JSONForms UISchema
   or omit.
2. **Expecting rules to block a Reject** — they don't, by design; the state
   machine stays uniform and `failed` is always reachable.
3. **`timeout_seconds` / `on_timeout` on external validations** — rejected
   at save (`validation.external.timeout_unsupported`); Phase 2 ships
   without validation timeouts (item-level mechanisms still apply).
4. **Reusing `np-checklist-item-resolve` for a validation callback** — wrong
   verb and body; validations need `np-checklist-validation-resolve`.
5. **`context.`-rooted paths in rules** — same rejection as conditions
   (`validation.rule.context_rooted_path` family); address the catalog
   directly (`build.metadata.coverage`).
