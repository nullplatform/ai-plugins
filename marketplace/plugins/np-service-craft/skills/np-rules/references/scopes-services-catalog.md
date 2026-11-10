### Reference: Scope & service repository catalog

Each base scope and sample service lives in its own repository, with its own releases and CI. This
file does **not** list which ones exist — that inventory is public documentation and changes
without a skills release. It holds the wiring data the setup layers need for the ones we have
verified, and the gotchas behind them.

#### Inventory: which scopes and services exist

Two public docs pages, read as raw markdown (no auth, ~1–3k tokens each):

```bash
# Services: one row per service (a repo with a server and a DB is two rows)
curl -fsSL https://docs.nullplatform.com/docs/services/sample-services.md    # page "Sample services", table under "Samples"
# Scopes: one row per scope type (a repo can hold several)
curl -fsSL https://docs.nullplatform.com/docs/agent-backed-scopes/sample-scopes.md # page "Sample scopes", table under "Samples"
```

Use the raw `.md` URLs — not the HTML pages and not `WebFetch`, which costs ~10× more and
returns a summary that can drop rows. **Read the table instead of crawling repos**: it already
carries what a choice needs, so clone only the repo that was picked. Then:

- **Services** ("Sample services" — working examples to adopt or start from, not the limit of
  what runs): columns `Service | Slug | Category | Subcategory | Repository`, read from each
  `service-spec.json.tpl` at the latest release. The name ends with its platform in
  parentheses (`(AWS)`, `(Kubernetes)`, `(Istio)`) when it doesn't already say it. **Repository**
  is a link whose text is `repo/path` — the link points at `github.com/nullplatform/<repo>/tree/<tag>/<path>`
  — or just `repo` when `specs/` is at the repo root (`service_path` = `.`). The key is
  **repo + slug** — names change, the slug does not. That **path is the `service_path`**: prefer
  it over the wiring table below, and if they differ say so.
- **Scopes** ("Sample scopes"): columns `Scope | Description | Repository`, read from each
  `scope-type-definition.json.tpl` at the latest release — the name and description a developer
  sees when picking a scope type. Scope specs carry no platform, so if two names ever repeat
  each gets its directory in parentheses. The page shows a curated subset in a fixed order (for
  example, `scopes/azure` and `scopes/azure-aro` are left out): a scope type missing from it may
  still exist in its repo — say so instead of treating it as nonexistent. **Repository** works
  as for services (`repo/path`, linked at the tag), and its **path is the scope's `service_path`**.
  The key is **repo + path** (scopes have no slug). Requirements module and selector still come
  from the wiring table.
- A row marked **Deprecated** (at the start of its name) no longer exists for new work: say so,
  never offer it.
- An entry not in the wiring table exists, but its requirements module and selector are
  unverified: read them from the repo at its resolved tag (notes 3–6) and confirm with the
  user. Never guess.
- If a fetch fails, or a page lacks its table or section, stop and tell the user. Do not fall
  back to the wiring table as an inventory.

Both pages are kept up to date by a daily sync in `nullplatform/docsite` that opens a reviewed
PR: it takes the public `services-*` / `scopes-*` repos **with a release**, skips those whose
spec still has the template's placeholders (`My Service`, `Other` / `Other`, `my-scope/`),
builds the rows from each spec **at the repo's latest release** (`scopes-*` repos without a
scope type, such as the `scopes-networking` override, are left out), and marks archived,
private or deleted repos **Deprecated**. Two consequences:

- **A public `services-*` / `scopes-*` repo with a release that is not on a page yet is not an
  error** — it may be waiting in the pending sync PR (up to a day). Treat it as existing but
  unindexed and tell the user. One without a release, or still with template placeholders,
  is not ready for use.
- **Never edit the pages to add or remove entries** — that is the sync's job, and a manual row
  conflicts with it.

`nullplatform/services` is a legacy index (and, in old setups, a monorepo some agents still
clone): don't use it as an inventory and don't clone it looking for implementations.

#### Wiring data for the setup layers

This catalog is the single source of truth for **wiring** the three setup layers. They must agree on
`(repo, ref, service_path)` — and, for packaged entries, on the image tag, package name and
entrypoint: when they don't, `tofu` reports nothing and the scope registers successfully in
nullplatform, then fails on the first deploy.

**Every entry with a worker image runs as a package** (see [Packaged mode](#packaged-mode-default)).
Only entries without one fall back to the legacy model, where the agent clones the repo.

| Entity | Kind | Repo | Worker image (`public.ecr.aws/…`) | `service_path` | Requirements module | IAM selector | `create_scope_configuration` |
|---|---|---|---|---|---|---|---|
| Containers | scope | `nullplatform/scopes` | `nullplatform/scopes/containers` | `k8s` | `k8s/specs/requirements/aws` | `containers` | `false` |
| Scheduled Tasks | scope | `nullplatform/scopes` | `nullplatform/scopes/scheduled-task` | `scheduled_task` | — none | — | `false` |
| Static Files | scope | `nullplatform/scopes-static-files` | `nullplatform/scopes/static-files` | `static-files` | `static-files/specs/requirements/aws` | `static-files` | `true` |
| AWS Lambda | scope | `nullplatform/scopes-lambda` | `nullplatform/scopes/lambda` | `lambda` | `lambda/specs/requirements` | `lambda` | `true` |
| AWS S3 Bucket | service | `nullplatform/services-s-3` | `nullplatform/services/s3` | `aws-s3-bucket` | `aws-s3-bucket/specs/requirements/aws` | `s3` | n/a |
| RDS Postgres Server | service | `nullplatform/services-postgresql-rds` | `nullplatform/services/rds-postgres-server` | `rds-postgres-server` | `rds-postgres-server/specs/requirements/aws` | `rds-postgres-server` | n/a |
| RDS Postgres DB | service | `nullplatform/services-postgresql-rds` | `nullplatform/services/rds-postgres-db` | `rds-postgres-db` | `rds-postgres-db/specs/requirements/aws` | `rds-postgres-db` | n/a |
| PostgreSQL (K8s) | service | `nullplatform/services-postgresql-k-8-s` | `nullplatform/services/postgresql-k8s` | `postgres-db` (see note 8) | — none | — | n/a |
| Endpoint Exposer | service | `nullplatform/services-endpoint-exposer` | `nullplatform/services/endpoint-exposer` | `""` (repo root — see note 9) | `specs/requirements/aws` | ⚠️ verify | n/a |
| Azure Cosmos DB | service | `nullplatform/services-azure-cosmos-db` | — none: legacy | `azure-cosmos-db` | — none (Azure) | — | n/a |
| Networking overrides | override | `nullplatform/scopes-networking` | — none: legacy | `lambda` | — none | — | n/a |
| Parameter Store | provider | `nullplatform/parameters-provider` | — none: legacy | `parameters/providers/aws-parameter-store` | `parameters/providers/aws-parameter-store/specs/requirements` | `parameter_store` | n/a |
| Secrets Manager | provider | `nullplatform/parameters-provider` | — none: legacy | `parameters/providers/aws-secrets-manager` | `parameters/providers/aws-secrets-manager/specs/requirements` | `secret_manager` | n/a |

**There is no `Ref` column on purpose.** For packaged entries the ref is the image tag, resolved
when the setup is generated (see [Packaged mode](#packaged-mode-default)); for legacy entries it is
resolved the same way from git tags (note 3a). A pinned ref in this table went stale within weeks
every time it was tried.

> **RDS moved repos.** `nullplatform/services-rds` stopped at `v0.1.1`; the `v0.6.0` images are built
> from `nullplatform/services-postgresql-rds`, which has the same `rds-postgres-server/` and
> `rds-postgres-db/` layout. Reading specs from the old repo fails the tag check below.

⚠️ marks a value that could **not** be verified against an applied reference setup. Ask the
user or verify against the repo — never fill one in with a plausible guess.

#### Packaged mode (default)

Each scope and service repo publishes a **worker image** on every semver tag, and its CI registers
it as a global `oci_image` artifact (`visible_to organization=*`) carrying that release tag. A
packaged entry is wired like this across the three layers:

| Layer | What it gets |
|---|---|
| `infrastructure/` | `agent` with `worker_orchestrator = true`; the package name in `worker_orchestrated_packages` (runs the worker under the agent's IRSA identity); requirements module pinned `?ref=<tag>` |
| `nullplatform/` | `scope_definition` / `service_definition` with `package = { slug, version = <tag>, artifacts = [lookup by tag] }`; spec, actions and links read from `refs/tags/<tag>` |
| `nullplatform-bindings/` | association with `worker_orchestrator = true`, `package_slug`, `entrypoint` — a `package-exec` channel instead of a git-clone one |

**One tag governs everything.** The image tag, the git ref the specs are read from, the
requirements module ref and `package.version` (minus its `v`) are the same value, so the registered spec and the
code the worker runs belong to one release.

**Resolve it when generating, never at plan time.** The wizard resolves the latest published
`vX.Y.Z` of each enabled entry's image and writes it as a literal to `packages` in
`common.tfvars`. An upgrade is a reviewed change to that file, not drift picked up by an unrelated
plan.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-infrastructure-wizard/scripts/resolve-worker-package.sh \
  <catalog_slug> <worker image> --git-repo <repo> --service-path <service_path>
```

The script prints the `packages` entry and fails when the image has no worker env or the spec does
not exist in git at that tag. **The package name and entrypoint are read from the image, never
derived:** they come from its `NP_PACKAGE_NAME` and `NP_SCOPE_ENTRYPOINT`, and they do not follow
the repo or slug (verified 2026-10-15):

| Catalog slug | Tag | `package_slug` | `entrypoint` |
|---|---|---|---|
| `containers` | `v1.18.0` | `containers` | `/app/pkg/entrypoint` |
| `scheduled_tasks` | `v1.18.0` | `scheduled-task` | `/app/pkg/entrypoint` |
| `static_files` | `v4.1.0` | `scopes-static-files` | `/app/pkg/entrypoint` |
| `aws_lambda` | `v0.9.1` | `scopes-lambda` | `/app/pkg/lambda/entrypoint` |
| `aws_s3_bucket` | `v0.5.4` | `aws-s3-bucket` | `/app/pkg/aws-s3-bucket/entrypoint/entrypoint` |
| `rds_postgres_server` | `v0.6.0` | `rds-postgres-server` | `/app/pkg/rds-postgres-server/entrypoint/entrypoint` |
| `rds_postgres_db` | `v0.6.0` | `rds-postgres-db` | `/app/pkg/rds-postgres-db/entrypoint/entrypoint` |
| `postgres_db_k8s` | `v1.2.0` | `postgres-db` | `/app/pkg/postgres-db/entrypoint/entrypoint` |
| `endpoint_exposer` | `v1.0.0` | `endpoint-exposer` | `/app/pkg/entrypoint/entrypoint` |

These are a snapshot to recognise a wrong value, not defaults: re-run the script. A channel whose
`package_slug` or `entrypoint` differs from the image routes to a worker that does not exist and
fails on the first action, not at apply.

`common.tfvars` then carries, next to the toggles, one entry per packaged slug exactly as the script
printed it:

```hcl
packages = {
  containers = {
    tag          = "<latest vX.Y.Z of the image>"
    package_slug = "<NP_PACKAGE_NAME of that image>"
    entrypoint   = "<NP_SCOPE_ENTRYPOINT of that image>"
  }
}
```

`package.version` is the tag **without** its `v` (`1.18.0`): the API accepts `v1.18.0`, but the
console prepends its own `v` and shows `vv1.18.0`. Only `package.version` drops it — the image tag,
the git ref and the requirements `?ref=` keep it.

If the plan fails with `no oci_image artifact visible at <nrn> matches meta {…}` although the tag is
published, an artifact with the same identity owned closer to the NRN is shadowing the global one:
pin the global artifact's ids instead of the lookup (`np-nullplatform-wizard`'s generation guide).

**Legacy fallback.** An entry with no worker image (the "none: legacy" rows) keeps the git-clone
model: the agent clones `<repo>#<tag>` through `agent_repo` and its channel uses `repo_path` (note
7). Both models run on the same agent at once.

#### 1. Catalog slug drives the toggle

The catalog slug is the key used across all three layers:

`containers`, `scheduled_tasks`, `static_files`, `aws_lambda`, `aws_s3_bucket`,
`rds_postgres_server`, `rds_postgres_db`, `postgres_db_k8s`, `endpoint_exposer`,
`azure_cosmos_db`

From it comes the toggle variable `enable_<catalog_slug>`, which lives in **`common.tfvars`**
because all three layers read it. **Containers has no toggle** — it is the base scope of any
setup and is always generated; do not ask the user about it.

#### 2. Shared repos

RDS Server and RDS Database share `services-postgresql-rds`. Containers and Scheduled Tasks share
`scopes`. Do not look for a separate repo for those — each still has its own worker image.

#### 3. Refs are tags, resolved at generation time

Packaged entries take their ref from the image tag (see [Packaged mode](#packaged-mode-default)).
Legacy entries resolve theirs from git with 3a. Either way the ref is a **tag**, read through
`refs/tags/`: a branch moves under an applied setup.

#### 3a. Resolve the latest release (legacy entries)

A hand-copied ref fails two ways: it no longer exists (the `1.0.0` this table once carried for AWS
S3 Bucket never existed in the repo — `git clone --branch` simply fails), or it predates the
package model and hands you a legacy implementation with no `Dockerfile`.

So resolve the latest release at the moment of use:

```bash
REF=$(git ls-remote --tags https://github.com/nullplatform/$REPO \
      | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' | sort -V | tail -1)
```

If the repo turns out to publish a worker image, it is not a legacy entry: move it to the packaged
model and add its image to the table. Known at the time of writing: `services-s-3` is packaged
from `v0.3.0` on; `services-postgresql-k-8-s` from `v1.0.2` on; `services-blob-storage` from
`v0.1.0` on — its `0.0.1` tag still points at a pre-service scaffold.

**The GitHub organization is always `nullplatform`.**

#### 4. Requirements module paths are NOT derivable

There is no inferable pattern. Verified at the tags in the packaged-mode table (2026-10-15):

| Repo | Requirements module path | Irregularity |
|---|---|---|
| `scopes` | `k8s/specs/requirements/aws` | — |
| `scopes-lambda` | `lambda/specs/requirements` | **no** `/aws` segment |
| `scopes-static-files` | `static-files/specs/requirements/aws` | — |
| `services-s-3` | `aws-s3-bucket/specs/requirements/aws` | — |
| `services-postgresql-rds` | `rds-postgres-server/specs/requirements/aws`, `rds-postgres-db/specs/requirements/aws` | two modules, one repo |
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
config at runtime, and it varies by repo and ref: older applied setups publish `k8s` for the
Containers scope. On `scopes` from `v1.18.0` the workflow reads `CONTAINERS_ASSUME_ROLE_SELECTOR`,
default `containers` (`k8s/utils/assume_role_step`). Read the workflow at the tag you pin to confirm
the selector before generating the `identity-access-control` module.

**The selector is not the spec slug.** The slug is how the platform registers the specification;
the selector is a default baked into the workflow code. They differ in most repos (verified at the
packaged tags, 2026-10-15):

| Entry | Spec slug | Selector (workflow default) |
|---|---|---|
| AWS S3 Bucket | `aws-s3-bucket` | `s3` (`*_ASSUME_ROLE_SELECTOR`) |
| RDS Postgres Server | `rds-postgres` | `rds-postgres-server` |
| RDS Postgres DB | `rds-postgres-db` | `rds-postgres-db` — matches here by coincidence |
| AWS Lambda | derived from `"AWS Lambda"` | `lambda` (`ASSUME_ROLE_SELECTOR`) |
| Static Files | derived from `"Static files"` | `static-files` (`STATIC_FILES_ASSUME_ROLE_SELECTOR`) |

Deriving the selector from `scope_definitions.slug` publishes the role under a key no workflow reads:
the deploy fails on credentials with no `tofu` error. So the selector is **catalog data**: each entry
in the `nullplatform/` catalog carries it as `iam_selector` (`null` for entries with no permissions
role, e.g. Scheduled Tasks), the layer exports it, and bindings builds the provider config from it —
never a literal in bindings.

#### 7. `repo_path` depends on the agent's clone layout (legacy entries only)

Packaged entries have no `repo_path`: the worker image carries the code. For a legacy entry, the
`agent` module turns `agent_repo` (a list of `<url>#<ref>`) into
`--command-executor-git-command-repos`, and the agent clones each entry into
`$HOME/.np/<org>/<repo>`. `$HOME` depends on the agent image: `/root` for the root images,
**`/home/agent`** for the non-root ones (`aws-X.Y.Z-nonroot`, UID 1001) the infrastructure wizard
pins. Module defaults still say `/root/.np/...`, so a legacy `repo_path` has to be passed
explicitly.

`agent_repo` is empty by default in `tofu-modules` v8: nothing is cloned unless listed. A repo
referenced by a legacy channel cmdline that is not listed fails at runtime with
`stat: no such file or directory` — while the scope still shows as active in nullplatform.

#### 8. `service_path` for PostgreSQL-K8s depends on the ref

That repo restructured: older refs used `postgres/k8s/`, while `v1.2.0` has its spec under
`postgres-db/` — also the `NP_SERVICE_PATH` its image bakes. Packaged setups read the spec at the
image tag, which the resolver script checks, so a layout change surfaces at generation time. If an existing setup has
`postgres/k8s`, check which ref it reads before calling it a bug.

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
