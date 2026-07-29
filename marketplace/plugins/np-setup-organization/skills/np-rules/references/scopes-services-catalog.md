### Reference: Scope & service repository catalog

`nullplatform/services` is an **index**, not code. Each base service and scope lives in its
own repository with independent versioning (release branches like `1.0.0`, migrating to
tags) and its own CI/security checks. The correct use of the index is to *resolve* which
repo a service lives in — never to clone it expecting to find implementations inside.

This catalog is the single source of truth for the three setup layers. They must agree on
`(repo, ref, service_path)`: when they don't, `tofu` reports nothing and the scope registers
successfully in nullplatform, then fails on the first deploy inside the agent.

| Entity | Kind | Repo | Ref | `service_path` | Requirements module | IAM selector | `create_scope_configuration` |
|---|---|---|---|---|---|---|---|
| Containers | scope | `nullplatform/scopes` | `main` | `k8s` | `k8s/specs/requirements/aws` | ⚠️ `k8s` or `containers` | `false` |
| Scheduled Tasks | scope | `nullplatform/scopes` | `main` | `scheduled_task` | — none | — | `false` |
| Static Files | scope | `nullplatform/scopes-static-files` | `1.0.0` (branch) | `static-files` | `static-files/specs/requirements/aws` | `static-files` | `true` |
| AWS Lambda | scope | `nullplatform/scopes-lambda` | `1.0.1` | `lambda` | `lambda/specs/requirements` | `lambda` | `true` |
| AWS S3 Bucket | service | `nullplatform/services-s-3` | `1.0.0` | `aws-s3-bucket` | `aws-s3-bucket/specs/requirements/aws` | `s3` | n/a |
| RDS Postgres Server | service | `nullplatform/services-rds` | `1.0.0` | `rds-postgres-server` | `rds-postgres-server/specs/requirements/aws` | `rds-postgres-server` | n/a |
| RDS Postgres DB | service | `nullplatform/services-rds` | `1.0.0` | `rds-postgres-db` | `rds-postgres-db/specs/requirements/aws` | `rds-postgres-db` | n/a |
| PostgreSQL (K8s) | service | `nullplatform/services-postgresql-k-8-s` | `main` | `postgres/k8s` (ref-dependent — see note 8) | — none | — | n/a |
| Azure Cosmos DB | service | `nullplatform/services-azure-cosmos-db` | `main` | `azure-cosmos-db` | — none (Azure) | — | n/a |
| Endpoint Exposer | service | `nullplatform/services-endpoint-exposer` | `v0.2.1` | `.` (repo root — see note 9) | `specs/requirements/aws` | ⚠️ verify | n/a |
| Networking overrides | override | `nullplatform/scopes-networking` | `main` | `lambda` | — none | — | n/a |
| Parameter Store | provider | `nullplatform/parameters-provider` | `main` | `parameters/providers/aws-parameter-store` | `parameters/providers/aws-parameter-store/specs/requirements` | `parameter_store` | n/a |
| Secrets Manager | provider | `nullplatform/parameters-provider` | `main` | `parameters/providers/aws-secrets-manager` | `parameters/providers/aws-secrets-manager/specs/requirements` | `secret_manager` | n/a |

⚠️ marks a value that could **not** be verified against an applied reference setup. Ask the
user or verify against the repo — never fill one in with a plausible guess.

#### 1. Catalog slug drives the toggle

The catalog slug is the key used across all three layers:

`containers`, `scheduled_tasks`, `static_files`, `aws_lambda`, `aws_s3_bucket`,
`rds_postgres_server`, `rds_postgres_db`, `postgres_db_k8s`, `endpoint_exposer`,
`azure_cosmos_db`

From it comes the toggle variable `enable_<catalog_slug>`, which lives in **`common.tfvars`**
because all three layers read it. **Containers has no toggle** — it is the base scope of any
setup and is always generated; do not ask the user about it.

#### 2. Shared repos

RDS Server and RDS Database share `services-rds`. Containers and Scheduled Tasks share
`scopes`. Do not look for a separate repo for those.

#### 3. Refs are suggested defaults, not fixed

Confirm the ref with the user before generating. Note that `1.0.0` in `scopes-static-files`
is a **branch** (`refs/heads/1.0.0`), not a tag — the repos are mid-migration from release
branches to tags, so do not assume `?ref=` values are tags.

#### 4. Requirements module paths are NOT derivable

There is no inferable pattern. Verified against an applied AWS reference setup:

| Repo | Requirements module path | Irregularity |
|---|---|---|
| `scopes` | `k8s/specs/requirements/aws` | — |
| `scopes-lambda` | `lambda/specs/requirements` | **no** `/aws` segment |
| `scopes-static-files` | `static-files/specs/requirements/aws` | — |
| `services-s-3` | `aws-s3-bucket/specs/requirements/aws` | — |
| `services-rds` | `rds-postgres-server/specs/requirements/aws`, `rds-postgres-db/specs/requirements/aws` | two modules, one repo |
| `services-endpoint-exposer` | `specs/requirements/aws` | specs live at the repo root, so there is no `service_path` prefix |
| `parameters-provider` | `parameters/providers/aws-parameter-store/specs/requirements` | — |
| `parameters-provider` | `parameters/providers/aws-secrets-manager/specs/requirements` | was misspelled `requeriments` upstream until 2026-07-27 |

**Verify before generating — the paths move.** The secrets-manager row is the cautionary example: it
was genuinely `requeriments` for months, then upstream renamed it to `requirements`
(`nullplatform/parameters-provider` commit `a4e4345`, 2026-07-27). Any setup that pinned
`?ref=main` and hardcoded the old path broke at `tofu init` the moment that landed. A setup pinned to
a tag or SHA still needs the old spelling. Never copy one of these paths from an existing setup
without checking it:

```bash
gh api "repos/<org>/<repo>/contents/<service_path>/specs?ref=<ref>" --jq '.[].name'
```

#### 5. Requirements module I/O contracts differ

| Module family | Required input | Optional inputs | Output |
|---|---|---|---|
| Scope/service requirements | `cluster_name` | `agent_role_arn`, `additional_agent_role_arns`, the role-name override (see below), `policies_name_prefix`, `iam_create_role`, `iam_resource_tags_json` | `permissions_role_arn` (also `permissions_role_name`, `permissions_role_id`) |
| `parameters-provider` requirements | `iam_role` (object, see below) | — | `iam_role_arn` |

Do not assume one contract from the other.

**The role-name override is not named consistently across repos**: `scopes` (Containers / `k8s`) calls
it `permissions_role_name`, while `scopes-lambda`, `scopes-static-files` and `services-s-3` call it
`role_name`. Passing the wrong one is a hard `tofu` "Unsupported argument" error. Read the module's
`variables.tf` before generating an override.

The `parameters-provider` `iam_role` object requires **both** `enable` and `name` — passing
`{ enable = false }` alone fails validation with `attribute "name" is required`:

```hcl
iam_role = {
  enable             = true
  name               = "nullplatform-<cluster>-secrets-manager-role"
  mode               = "default"          # or "kms", which then requires kms_key_arn
  trusted_principals = []                 # defaults to the account root
}
```

`agent_role_arn` is **optional**: when empty the module derives
`arn:aws:iam::<account>:role/nullplatform-${cluster_name}-agent-role` itself, which is the same
naming convention that breaks the module cycle. Pass it explicitly only when the agent role name
was overridden — otherwise the derived trust points at a role that does not exist, and the failure
appears as `AccessDenied` on the first deploy rather than a `tofu` error.

#### 6. The IAM selector is verified, not assumed

The selector is the key the scope's workflow looks up in the `aws-iam-configuration` provider
config at runtime, and it varies by repo and ref: one applied reference setup publishes
`k8s` for the Containers scope while another publishes `containers`. Read the scope's workflow
to confirm the selector before generating the `identity-access-control` module.

#### 7. `repo_path` depends on the agent's clone layout

The `agent` module turns `agent_repos_extra` into `--command-executor-git-command-repos`, and
the agent clones each entry into `/root/.np/<org>/<repo>`. Every `repo_path` in the bindings
layer is derived from that convention, so if the layout changes in the agent image, all of
them break at once.

`scopes` is cloned by default because it is the module default for `agent_repos_scope` — not because
it ships inside the agent image. Any repo referenced by
a channel cmdline that is not listed in `agent_repos_extra` fails at runtime with
`stat: no such file or directory` — while the scope still shows as active in nullplatform.

#### 8. `service_path` for PostgreSQL-K8s depends on the ref

That repo is mid-restructure, and the two branches have different layouts:

| Ref | Layout | `service_path` |
|---|---|---|
| `main` | `postgres/k8s/{specs,entrypoint}` | `postgres/k8s` |
| `proposal/align-with-services-s-3` | `postgres-db/{specs,entrypoint}` | `postgres-db` |

An applied AWS reference setup uses **both** and is correct to do so: its `nullplatform/` layer reads
the spec from `main` (`postgres/k8s`) while the agent clones the proposal branch (`postgres-db`). If
you see those two values disagree in an existing setup, check which ref each layer points at before
calling it a bug.

#### 9. Endpoint Exposer keeps its specs at the repo root

It is the only entry whose `specs/` is not nested under a `service_path` directory — the spec,
entrypoint and workflows all sit at the top level. So `service_path` is the repo root, and its
requirements module path is `specs/requirements/aws` rather than `<service_path>/specs/requirements/aws`.

It **does** participate in the assume-role model: that module creates an IAM role and outputs
`permissions_role_arn`, described upstream as "Pass to the agent (`assume_role_arns`) and publish to
the AWS IAM provider." Its IAM selector could not be determined from the repo — read the service's
workflows to confirm it before generating `identity-access-control`.

#### 10. The assume-role model is AWS-only

Azure entries have no requirements module because the model depends on AWS IAM roles and
`sts:AssumeRole`. If Azure gains an equivalent (Workload Identity + role assignment), this
table needs a second requirements column per cloud rather than a rewrite.
