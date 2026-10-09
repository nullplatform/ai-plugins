# Registering packaged services/scopes with the tofu modules

Repo: `nullplatform/tofu-modules`. Three modules publish packages (provider
`nullplatform/nullplatform` **>= 0.0.102** for the lookup features):

| Module | For |
|---|---|
| `nullplatform/service_definition` | a service (spec + actions + LINKS tier) |
| `nullplatform/scope_definition` | a scope type |
| `nullplatform/packaged_service` | pass whole resources, module builds the BOM |

Source form:
`git::https://github.com/nullplatform/tofu-modules.git//nullplatform/<module>?ref=<release>`

## The `package` block (service_definition / scope_definition)

```hcl
module "postgres" {
  source          = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition?ref=<ref>"
  nrn             = var.nrn
  repository_org  = "nullplatform"
  repository_name = "services-postgresql-rds"
  service_path    = ""
  service_name    = "PostgreSQL (RDS)"

  package = {
    version = "0.2.0"        # bump to publish a new immutable revision
    default = true           # promote to package default on apply
    artifacts = [ ... ]      # see the three forms below
  }
}
```

Each apply with a new `version` publishes ONE immutable revision whose BOM pins
the service spec, every action spec (default actions included), every link
spec, and the artifacts. Re-applying the same version + components is an
idempotent no-op. Interchangeable with `np package publish`.

## The three artifact reference forms (XOR-validated)

```hcl
# 1 · REGISTER a new revision here
{ name = "worker-image", type = "oci_image",
  meta = { registry = "public.ecr.aws", repository = "nullplatform/services/rds-postgres-server",
           digest = "sha256:<64-hex>" } }

# 2 · LOOK UP one registered elsewhere (e.g. by the repo's CI) — no ids needed
{ name = "worker-image", type = "oci_image", lookup = true,
  meta = { registry = "public.ecr.aws", repository = "nullplatform/scopes/lambda",
           tag = "v0.3.2" } }        # or digest = …; or reference = … for git_repository

# 3 · PIN explicit ids
{ name = "worker-image", resource_id = "…", resource_revision_id = "…" }
```

Lookup facts (provider >= 0.0.102):
- Resolution is by **visibility**: owned at the nrn, ancestor-shared, and
  globals (`organization=*` — nullplatform's own scope/service images resolve
  from client orgs). Owned beats global on identity clashes.
- `tag` selects the **newest** revision registered with it and the data source
  computes `digest` for you. A re-registered tag drifts the plan to the new
  revision — by design, the digest changed. Use `digest` in the meta to freeze.
- git_repository pins by `reference` (use a tag or SHA for real immutability).

## Wiring the agent

`service_definition_agent_association` / `scope_definition_agent_association`
register the notification channel: `tags_selectors` must match the target
agent's `TAGS`, and the channel gets a UNIQUE package name (see
architecture.md Hazards).

## Gotchas

- **Default-actions two-step**: platform-generated actions exist only after the
  apply that creates the spec — from scratch, publish the package on a SECOND
  apply so the BOM pins them.
- Validation errors "must EITHER set meta OR both ids" / "lookup requires
  meta" = mixed reference forms in one artifact entry.
- Module outputs: `package_id`, `package_published_revision_id`,
  `package_default_version`, `package_artifacts` (name → ids).
- Console check: spec view → Versions → expand the revision — BOM with digests
  shortened, release notes if the artifact carries a changelog annotation.
