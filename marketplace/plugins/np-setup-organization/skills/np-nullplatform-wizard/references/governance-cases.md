# Governance cases (workflows + checklists)

Optional step of the wizard: adds approval checklists (and, when needed, the workflow that
resolves them) to the `nullplatform/` layer. They are applied by `tofu apply` through
`workflow_checklist.tf`, which runs each case's `apply.sh` / `destroy.sh`.

Templates: `${CLAUDE_PLUGIN_ROOT}/skills/np-nullplatform-wizard/templates/governance/`

## Questions

`AskUserQuestion` allows at most 4 options per question.

1. **"Which governance use cases (workflows + checklists) do you want?"** — `multiSelect: true`:

   | Option | Case slug |
   |--------|-----------|
   | Production deploy gate | `prod_deploy_gate` |
   | Limit resources for non-prod environments | `nonprod_sizing` |
   | None (no checklists or workflows) | — |

   If the user picks **None** (or nothing), skip this step entirely: do not copy any file.
   If **None** comes together with a case, ask again — the answers contradict each other.

2. With **Production deploy gate**, `multiSelect: true` — **"Which checks before a production
   deploy?"** (one file each in `prod_deploy_gate/items/`):

   | Option | Item file | Kind | Needs |
   |--------|-----------|------|-------|
   | Release running in lower environments | `release_in_lower_env.json` | `external` (workflow) | — |
   | Allowed source branch | `source_branch.json` | `condition` | — |
   | Minimum code coverage | `code_coverage_minimum.json` | `condition` | build metadata **Coverage**, reported by CI ([metadata.md](metadata.md)) |
   | No critical vulnerabilities | `no_critical_vulnerabilities.json` | `condition` | build metadata **Security**, reported by CI ([metadata.md](metadata.md)) |

   `hotfix_override.json` (a manual override that unblocks a failed gate with a mandatory
   justification) is always added.

3. For each selected check, one question (up to 4 in the same call) — **"`<check>`: gate or
   informational?"**:
   - **Gate** — a failure blocks the deploy (until fixed, or a hotfix override is approved).
   - **Informational** — a failure is shown on the approval (in red, with its message), but never
     blocks.

4. Parameters, only for the selected checks (the first option is the default):
   - Allowed source branch → `main, master` / `main`
   - Minimum code coverage → `80` / `70`
   - Release running in lower environments → which lower environments: by default every value of
     the environment dimension except the protected one (e.g. `development,staging`).

**Coverage and vulnerabilities read build metadata.** If the user selects one of them as a
**gate** but not the matching build metadata in the metadata step (or the CI does not report it
yet), every production deploy fails that item, because a build with no data does not meet the
condition. Add the build metadata, or choose **informational** until the CI reports it.

## What each case creates

| Case | Rule | Approval actions (on `governance_nrn`) | Resources |
|------|------|----------------------------------------|-----------|
| `prod_deploy_gate` | A production deploy has to pass the selected checks | `deployment:create` `{environment: production}`, `on_checklist_fail: pending` (resumable fail: the requester fixes and redeploys, or asks for manual review) | checklist `poc-prod-deploy-gate` (the selected items + hotfix override). With *release running in lower environments*: workflow `poc-release-in-lower-env-<last NRN segment>` (e.g. `-namespace-3`, one per `governance_nrn`), its notification channel and secret `NP_API_KEY` |
| `nonprod_sizing` | In `development`/`staging`: autoscaling off, max 128 MB (request and limit), max 1 instance | `scope:create` and `scope:write` for each non-prod value, `on_checklist_fail: deny` (the request lands `auto_denied`) | checklist `poc-nonprod-sizing` (3 conditions, no workflow) |

*Release running in lower environments* passes when, for every lower environment, some active
scope of the application runs the release being deployed **or another release of the same
build**. It reads each scope's active deployment (not the latest finalized one) and returns a
Markdown explanation of the check with the result.

## Precondition: dimension name and values

Both cases assume a dimension named `environment` with the values `development`, `staging`
and `production`. Compare with the dimensions chosen in this wizard:

- **Same name and values** → nothing to adapt.
- **Different name or values** (e.g. a dimension `env` with `dev`/`qa`/`prod`) → ask the user
  the mapping with `AskUserQuestion` and change it in the copied files. The approval actions
  only match scopes that carry exactly that dimension: a wrong name or value does not fail,
  the gate simply never runs.

  | Case | File | What to change |
  |------|------|----------------|
  | `prod_deploy_gate` | `apply.sh`, `destroy.sh` | `DIMENSION`, `GATED_VALUE` (top of the file) |
  | `prod_deploy_gate` | `checklist.json` | in every item, the key of `applies_when` (`scope.dimensions.<name>`) and its value; in `release_in_lower_env`, `external.inputs.dimension` and `required_values` |
  | `nonprod_sizing` | `apply.sh`, `destroy.sh` | `DIMENSION`, `NONPROD_ENVS` (top of the file) |

  After changing, nothing but the intended matches must remain:

  ```bash
  grep -rn 'environment\|development\|staging\|production' nullplatform/governance/
  ```

## Generation

```bash
TPL="${CLAUDE_PLUGIN_ROOT}/skills/np-nullplatform-wizard/templates/governance"
mkdir -p nullplatform/governance
cp "$TPL/workflow_checklist.tf" nullplatform/
cp -R "$TPL/<slug>" nullplatform/governance/        # once per selected case
chmod +x nullplatform/governance/*/*.sh
```

For `prod_deploy_gate`, build `checklist.json` from the selected items (plus the override), then
apply the answers to questions 3 and 4:

```bash
cd nullplatform/governance/prod_deploy_gate
jq -s '{items: .}' items/release_in_lower_env.json items/source_branch.json \
  items/code_coverage_minimum.json items/hotfix_override.json > checklist.json

edit() { jq "$1" checklist.json > checklist.json.new && mv checklist.json.new checklist.json; }

# Question 3: informational instead of gate (per item id; severity drops to "info")
edit '(.items[] | select(.id == "code_coverage_minimum")) |= (.behavior = "informational" | .severity = "info")'

# Question 4: parameters (only when they differ from the defaults)
edit '(.items[] | select(.id == "source_branch") | .query."build.branch"."$in") = ["main"]'
edit '(.items[] | select(.id == "code_coverage_minimum")) |= (.query."build.metadata.coverage.code.coverage"."$gte" = 70 | .title = "Minimum code coverage (70%)")'
edit '(.items[] | select(.id == "release_in_lower_env") | .external.inputs.required_values) = "staging"'
```

Keep the item `title`s in line with the parameters, as in the coverage example. The `items/`
folder can stay: only `checklist.json` is published.

Add to `nullplatform/terraform.tfvars` (only the selected slugs):

```hcl
governance_cases = ["prod_deploy_gate", "nonprod_sizing"]

# Optional: where the cases live. Default: nrn from common.tfvars (account level).
# governance_nrn = "organization=<id>:account=<id>:namespace=<id>"
```

Then validate as the rest of the layer (`tofu init -backend=false && tofu validate`). The plan
adds 2 `null_resource` per case.

## Verification

After `tofu apply`, the output of each case's `apply.sh` is in the tofu log (`local-exec`
lines ending with `Listo: ...`). Then:

```bash
tofu output governance_cases
```

And with `/np-api`, the approval actions of `governance_nrn` must show
`checklist_specification_id` set.

## How it behaves day to day

- Re-running `tofu apply` is a no-op; editing a case file (e.g. `checklist.json`) re-runs only its
  `apply.sh`, which publishes a new checklist version.
- Removing a slug from `governance_cases` runs its `destroy.sh` (deletes approval actions and
  checklists; the workflow definition cannot be deleted by API, it is left inactive). Remove the
  slug and `tofu apply` **first**, and only then delete `governance/<slug>/`: `destroy.sh` runs
  from that folder.
- `apply.sh` only reuses an existing approval action when it is linked to a checklist of the case
  (same name). If a matching `(nrn, action, dimensions)` action belongs to something else, it stops
  with an error instead of adopting it, and `destroy.sh` never deletes it.
- An **approved** request still needs to be executed: "Start deployment" in the UI
  (`POST /approval/:id/execute`).
- With `nonprod_sizing`, creating a non-prod scope asks for two approvals: `scope:create` and
  the internal `scope:write` nullplatform does right after (sets the domain). Both auto-approve
  when the sizing is compliant, but both must be executed.
- A non-prod scope that was **already** oversized before enabling `nonprod_sizing` is rejected on
  any `scope:write` that does not bring its resources within the limits.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-------|
| `Error running command './apply.sh'` with `ERROR <METHOD> <path> -> {...}` | The API rejected a call; the body says why | Read the body in the tofu log; the most common is a 403 (API key without admin/ops/secops on `governance_nrn`) |
| `falta checklist.json` (`prod_deploy_gate`) | The case folder was copied but `checklist.json` was not built | Build it from `items/` (see Generation) |
| `jq: command not found` / `curl: command not found` | Tools missing where tofu runs | Install `jq` and `curl` |
| `el trigger no quedo live` (`prod_deploy_gate`) | The workflow alias activated but its trigger did not register the notification channel | Re-run `tofu apply` (apply.sh re-activates the alias); if it persists, the API key lacks `notification_channel:create` |
| Every production deploy fails *Minimum code coverage* / *No critical vulnerabilities* | The build has no `coverage` / `security` metadata: the CI does not report it, or the specification does not exist | Report it from CI ([metadata.md](metadata.md)), or make the item informational |
| `Governance case '<x>' is enabled ... does not exist` | Slug in `governance_cases` without its directory | Copy the case from the templates or remove the slug |
| Deploy/scope stuck in `creating_approval` / `pending_approval` / `updating_approval` | The approval was granted but not executed | Execute it ("Start deployment" or `POST /approval/:id/execute`) |
| `ERROR: ya existe la approval action <id> ... y no es de este caso` | An approval action with the same `(nrn, action, dimensions)` already exists and is not linked to this case's checklist | Delete it, or unlink it from its checklist, if the case should own that gate; otherwise leave the case disabled on that NRN. If the link to the case's checklist fails right after `apply.sh` creates an action, the script deletes that action itself, so a re-run starts clean |
| `ERROR: no se pudo leer la checklist <spec> de la approval action <id>` | The API failed while checking which checklist an existing action belongs to | Transient: re-run `tofu apply`. Nothing was adopted or deleted |
| *Release running in lower environments* fails with `NP GET … -> 401`/`403` after rotating `np_api_key` | The workflow secret keeps the old key: `apply.sh` only re-runs when the case files change | `tofu apply -replace='null_resource.governance_apply["prod_deploy_gate"]'` |
| Two cases on the same `(entity, action, dimensions)` | An approval action holds a single checklist: the last `apply.sh` wins | Put every production check in `prod_deploy_gate`'s single checklist |
