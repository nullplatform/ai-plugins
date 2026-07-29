# Roles Required

You don't grant individual permissions in Nullplatform — you assign a
**role** to a user (scoped by NRN), and the role brings its own set of
capabilities. This skill describes which existing roles cover which
parts of the checklist domain so you know what to ask for if you hit a
`403`.

## Who can do what

| Operation | Roles that cover it |
|---|---|
| List / read templates | `secops`, `ops`, `admin`, `developer`, `member`, `troubleshooting` |
| Dry-run a template against a context | `secops`, `ops`, `admin`, `developer` |
| Create / update / delete templates | `secops`, `ops`, `admin` |
| Link or unlink a template to an `ApprovalAction` | `secops`, `ops`, `admin` |
| Migrate an action from policy mode to checklist (and rollback) | `secops`, `ops`, `admin` |
| List / inspect checklist runs (state, events, logs) | `secops`, `ops`, `admin`, `developer`, `member`, `troubleshooting` |
| Approve / reject a manual item on a run | the team that owns the run's NRN (typically `developer`, `ops`, `secops`) |
| Retry a failed `external` item on a run | `secops`, `ops`, `admin`, `developer` |

The Nullplatform role catalog is centrally managed; the above mapping is
the **target distribution** for the checklist domain. If a role on your
account doesn't have a capability yet, it's a role-catalog rollout issue
— not something a user fixes by adjusting a token.

## What this means in practice

- A **developer** in their own namespace can: see all templates available
  to them, dry-run any of them, see the runs created by their deploys,
  approve manual items on those runs, retry failed external items.
- A **secops / ops / admin** can do everything the developer can, plus:
  author templates, wire them to actions, migrate existing policy
  actions, and roll back migrations.
- A **member** or **troubleshooting** role can see templates and runs
  but cannot mutate them.

## NRN scoping (always on)

All role grants in Nullplatform are NRN-scoped. A grant on
`organization=1::account=2` lets the user act on templates and runs
**inside** that subtree, not above it. So a developer with grant on
`organization=1::account=2::namespace=X` can approve items on runs
scoped to `namespace=X` but not to a sibling `namespace=Y`.

Two users can both have role `developer` but see entirely different
templates and runs, depending on the NRNs of their grants.

## "I'm getting 403"

Most likely:

1. **You don't have the role for that operation**. See the table above:
   creating a template requires `secops`/`ops`/`admin`; a `developer`
   account hits 403 on create. Ask the platform team to grant you the
   right role for the NRN you're working in.
2. **Your grant doesn't cover the target NRN**. If you have `developer`
   on `namespace=X` but the action lives in `namespace=Y`, the 403 is
   correct — the API enforces NRN ancestry on every call.
3. **The role catalog hasn't been rolled out yet** to include checklist
   capabilities for your role. This happens during the initial rollout
   of the feature; if it persists, escalate.

Verify your effective role on a given NRN with the standard auth tooling
(`/np-api/scripts/check_auth.sh`).
