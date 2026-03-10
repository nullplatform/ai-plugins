# Customer Lake Schema

Database: `customers_lake` — 52 tables in 6 domains.

**Source of truth:** Generated from `system.columns WHERE database = 'customers_lake'`.

## Common Columns

Most tables share these system columns (exceptions noted per table):

| Column | Type | Description |
|--------|------|-------------|
| `nrn` | String | Nullplatform Resource Name — hierarchical unique identifier |
| `_version` | UInt64 | Record version (monotonically increasing) |
| `_deleted` | UInt8 | Soft-delete flag: `0` = active, `1` = deleted |
| `_synced_at` | DateTime64(6) | Last sync timestamp to the data lake |

**Tables WITHOUT `_version` and `_deleted`:** `audit_events`, `scm_code_commits`, `scm_code_repositories`, `core_entities_metadata` (has `_deleted` but no `_version`).

### NRN Format

```
organization=123:account=456:namespace=789:application=012:scope=345
```

Filter by prefix:

```sql
WHERE nrn LIKE 'organization=123:account=456:namespace=789%'
```

---

## IMPORTANT: Column Naming Conventions

Column names are NOT consistent across tables:

| Table | ID Column | Type | Name Column | Slug Column |
|-------|-----------|------|-------------|-------------|
| `core_entities_organization` | `org_id` | Int32 | `org_name` | `org_slug` |
| `core_entities_account` | `account_id` | Int32 | `account_name` | `slug` |
| `core_entities_namespace` | `namespace_id` | Int32 | `namespace_name` | `namespace_slug` |
| `core_entities_application` | `app_id` | Int32 | `app_name` | `application_slug` |
| `core_entities_build` | `id` | Int32 | — | — |
| `core_entities_deployment` | `id` | Int32 | — | — |
| `core_entities_scope` | `id` | Int32 | `name` | `scope_slug` |
| `core_entities_release` | `id` | Int32 | — | — |
| `core_entities_technology_template` | `template_id` | Int32 | `name` | — |

### CRITICAL: Deployment has NO application_id

`core_entities_deployment` does **NOT** have an `application_id` column. The application is referenced through the `nrn` field. Filter by NRN prefix or query separately.

### JOINs: Use `AS alias FINAL` syntax

JOINs work correctly. The syntax is `table AS alias FINAL` (alias BEFORE `FINAL`):

```sql
-- CORRECT
FROM core_entities_deployment AS d FINAL
JOIN core_entities_scope AS s FINAL ON d.scope_id = s.id

-- WRONG (syntax error)
FROM core_entities_deployment FINAL AS d
```

**Always use `FINAL`** on `ReplacingMergeTree` tables to deduplicate rows. Without it, queries may return duplicate rows for the same entity.

---

## Core Entities Domain (21 tables)

### core_entities_organization

| Column | Type |
|--------|------|
| `org_id` | Int32 |
| `org_name` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `org_slug` | Nullable(String) |
| `org_logo` | Nullable(String) |
| `org_short_logo` | Nullable(String) |
| `org_logo_dark` | Nullable(String) |
| `org_short_logo_dark` | Nullable(String) |
| `org_settings` | Nullable(String) |
| `org_alt_domains` | Array(String) |

### core_entities_account

| Column | Type |
|--------|------|
| `account_id` | Int32 |
| `account_name` | Nullable(String) |
| `org_id` | Nullable(Int32) |
| `repo_provider` | Nullable(String) |
| `repo_prefix` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `slug` | Nullable(String) |
| `settings` | Nullable(String) |
| `deleted_at` | Nullable(DateTime64(6)) |

### core_entities_namespace

| Column | Type |
|--------|------|
| `namespace_id` | Int32 |
| `namespace_name` | Nullable(String) |
| `account_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `namespace_slug` | Nullable(String) |
| `status` | Nullable(String) |

### core_entities_application

| Column | Type |
|--------|------|
| `app_id` | Int32 |
| `app_name` | Nullable(String) |
| `namespace_id` | Nullable(Int32) |
| `repository_url` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `status` | Nullable(String) |
| `application_slug` | Nullable(String) |
| `template_id` | Nullable(Int32) |
| `auto_deploy_on_creation` | Nullable(UInt8) |
| `is_mono_repo` | Nullable(UInt8) |
| `repository_app_path` | Nullable(String) |
| `tags` | Nullable(String) |
| `messages` | Nullable(String) |
| `settings` | Nullable(String) |

### core_entities_scope

| Column | Type | Notes |
|--------|------|-------|
| `id` | Int32 | |
| `name` | Nullable(String) | Scope name (e.g., "Production Argentina") |
| `type` | Nullable(String) | web_pool, web_pool_k8s, serverless |
| `application_id` | Nullable(Int32) | FK to application (app_id) |
| `created_at` | Nullable(DateTime64(6)) | |
| `updated_at` | Nullable(DateTime64(6)) | |
| `status` | Nullable(String) | active, stopped, failed |
| `requested_spec` | Nullable(String) | JSON: cpu, memory, storage |
| `scope_slug` | Nullable(String) | |
| `scope_domain` | Nullable(String) | Assigned domain |
| `tier` | Nullable(String) | important, critical |
| `capabilities` | Nullable(String) | JSON: auto_scaling, health_check, logs |
| `tags` | Array(String) | |
| `messages` | Nullable(String) | |
| `asset_name` | Nullable(String) | e.g., "main", "docker-image-asset" |
| `external_created` | Nullable(UInt8) | |
| `profiles` | Nullable(String) | JSON array |
| `provider` | Nullable(String) | AWS:WEB_POOL:EKS, etc. |
| `instance_id` | Nullable(String) | |

### core_entities_build

| Column | Type | Notes |
|--------|------|-------|
| `id` | Int32 | |
| `app_id` | Nullable(Int32) | FK to application (app_id) |
| `status` | Nullable(String) | successful, failed, in_progress |
| `commit` | Nullable(String) | Git commit hash |
| `commit_permalink` | Nullable(String) | URL to commit |
| `branch` | Nullable(String) | Git branch |
| `description` | Nullable(String) | Commit message |
| `created_at` | Nullable(DateTime64(6)) | |
| `updated_at` | Nullable(DateTime64(6)) | |

### core_entities_release

| Column | Type | Notes |
|--------|------|-------|
| `id` | Int32 | |
| `semver` | Nullable(String) | e.g., "0.0.1" |
| `build_id` | Nullable(Int32) | FK to build |
| `status` | Nullable(String) | active |
| `app_id` | Nullable(Int32) | FK to application (app_id) |
| `created_at` | Nullable(DateTime64(6)) | |
| `updated_at` | Nullable(DateTime64(6)) | |

### core_entities_deployment

**No `application_id` column.** Application referenced through `nrn`.

| Column | Type | Notes |
|--------|------|-------|
| `id` | Int32 | |
| `scope_id` | Nullable(Int32) | FK to scope |
| `release_id` | Nullable(Int32) | FK to release |
| `strategy` | Nullable(String) | initial, blue_green, canary |
| `status` | Nullable(String) | creating_approval, creating, waiting_for_instances, running, finalizing, finalized, failed, deleting, deleted, rolled_back, cancelled |
| `strategy_data` | Nullable(String) | JSON |
| `created_at` | Nullable(DateTime64(6)) | |
| `updated_at` | Nullable(DateTime64(6)) | |
| `status_in_scope` | Nullable(String) | active, inactive, candidate |
| `messages` | Nullable(String) | JSON array (K8S events) |
| `deployment_token` | Nullable(String) | ndp-xxx |
| `expires_at` | Nullable(DateTime64(6)) | |
| `deployment_group_id` | Nullable(Int32) | FK to deployment_group |
| `created_by` | Nullable(Int32) | User ID who created |
| `updated_by` | Nullable(Int32) | User ID who updated |
| `status_started_at` | Nullable(String) | JSON: timestamp per status |
| `parameters` | Nullable(String) | JSON array |
| `external_strategy_id` | Nullable(Int32) | FK to deployment_strategy |

### core_entities_deployment_group

| Column | Type |
|--------|------|
| `id` | Int32 |
| `status` | Nullable(String) |
| `application_id` | Nullable(Int32) |
| `strategy_data` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `release_id` | Nullable(Int32) |
| `last_directive` | Nullable(String) |
| `deployments_amount` | Nullable(Int32) |
| `created_by` | Nullable(Int32) |
| `updated_by` | Nullable(Int32) |

### core_entities_asset

| Column | Type |
|--------|------|
| `id` | Int32 |
| `build_id` | Nullable(Int32) |
| `type` | Nullable(String) |
| `url` | Nullable(String) |
| `metadata` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `name` | Nullable(String) |
| `platform` | Nullable(String) |

### core_entities_deployment_strategy

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `description` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `parameters` | Nullable(String) |
| `created_by` | Nullable(Int32) |
| `updated_by` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_deployment_strategy_scope_type

| Column | Type |
|--------|------|
| `id` | Int32 |
| `deployment_strategy_id` | Nullable(Int32) |
| `scope_type_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_metadata

**No `_version` column.**

| Column | Type |
|--------|------|
| `pk` | String |
| `sk` | String |
| `id` | String |
| `entity` | String |
| `metadata_type` | String |
| `specification_id` | Nullable(String) |
| `data` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | DateTime64(6) |

### core_entities_runtime_configuration

| Column | Type |
|--------|------|
| `id` | Int32 |
| `profile` | Nullable(String) |
| `status` | Nullable(String) |
| `stored_keys` | Array(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `dimensions` | Nullable(String) |

### core_entities_runtime_configuration_dimension

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `slug` | Nullable(String) |
| `status` | Nullable(String) |
| `order` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_runtime_configuration_dimension_value

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `slug` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `dimension_id` | Nullable(Int32) |

### core_entities_runtime_configuration_scope

| Column | Type |
|--------|------|
| `id` | Int32 |
| `rc_id` | Nullable(Int32) |
| `scope_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_runtime_configuration_values

| Column | Type |
|--------|------|
| `id` | Int32 |
| `rc_id` | Nullable(Int32) |
| `rc_dimension_id` | Nullable(Int32) |
| `rc_value_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `runtime_configuration_dimension_id` | Nullable(Int32) |
| `runtime_configuration_dimension_value_id` | Nullable(Int32) |

### core_entities_scope_dimension

| Column | Type |
|--------|------|
| `id` | Int32 |
| `dimension_slug` | Nullable(String) |
| `value_slug` | Nullable(String) |
| `scope_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_scope_domain

| Column | Type |
|--------|------|
| `id` | UUID |
| `domain` | Nullable(String) |
| `scope_id` | Nullable(Int32) |
| `organization_id` | Nullable(Int32) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `type` | Nullable(String) |

### core_entities_scope_type

| Column | Type |
|--------|------|
| `id` | Int32 |
| `type` | Nullable(String) |
| `name` | Nullable(String) |
| `status` | Nullable(String) |
| `description` | Nullable(String) |
| `provider_type` | Nullable(String) |
| `provider_id` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### core_entities_technology_template

| Column | Type |
|--------|------|
| `template_id` | Int32 |
| `name` | Nullable(String) |
| `organization_id` | Nullable(Int32) |
| `account_id` | Nullable(Int32) |
| `status` | Nullable(String) |
| `url` | Nullable(String) |
| `provider` | Nullable(String) |
| `components` | Nullable(String) |
| `metadata` | Nullable(String) |
| `tags` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `repository_name` | Nullable(String) |
| `rules` | Nullable(String) |

---

## Audit Domain (1 table)

### audit_events

**No `_version` or `_deleted` columns.** JSON columns use `JSON(max_dynamic_paths=0)` — access with dot notation.

| Column | Type | Notes |
|--------|------|-------|
| `entity` | String | Entity type (login_success, deployment, scope) |
| `method` | String | HTTP method |
| `nrn` | String | |
| `request_body` | JSON(max_dynamic_paths=0) | Use dot notation: `request_body.field` |
| `status` | Int16 | HTTP status code |
| `url` | String | API endpoint |
| `ips` | String | |
| `headers` | JSON(max_dynamic_paths=0) | |
| `auth` | JSON(max_dynamic_paths=0) | |
| `organization_id` | String | |
| `application` | String | Service name |
| `scope` | String | |
| `entity_id` | String | |
| `user_id` | String | |
| `date` | DateTime64(3, 'UTC') | Event timestamp |
| `response_body` | JSON(max_dynamic_paths=0) | |
| `entity_context` | JSON(max_dynamic_paths=0) | |
| `user_email` | String | |
| `user_type` | String | |
| `organization_name` | String | |
| `organization_slug` | String | |
| `request_body_fields` | JSON(max_dynamic_paths=0) | |
| `entity_data` | JSON(max_dynamic_paths=0) | |

---

## Approvals Domain (18 tables)

### approvals_approval_action

| Column | Type |
|--------|------|
| `id` | Int32 |
| `entity` | Nullable(String) |
| `action` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `status` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `on_policy_success` | Nullable(String) |
| `on_policy_fail` | Nullable(String) |
| `time_to_reply` | Nullable(Int64) |
| `allowed_time_to_execute` | Nullable(Int64) |

### approvals_approval_action_policy

| Column | Type |
|--------|------|
| `id` | Int32 |
| `approval_action_id` | Nullable(Int32) |
| `policy_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_approval_policy

| Column | Type |
|--------|------|
| `id` | Int32 |
| `entity` | Nullable(String) |
| `action` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `status` | Nullable(String) |
| `dimensions` | Nullable(String) |

### approvals_approval_policy_notification

| Column | Type |
|--------|------|
| `id` | Int32 |
| `approval_policy_id` | Nullable(Int32) |
| `type` | Nullable(String) |
| `configuration_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_approval_policy_spec

| Column | Type |
|--------|------|
| `id` | Int32 |
| `approval_policy_id` | Nullable(Int32) |
| `approval_spec_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_approval_reply

| Column | Type |
|--------|------|
| `id` | Int32 |
| `body` | Nullable(String) |
| `status` | Nullable(String) |
| `headers` | Nullable(String) |
| `approval_request_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_approval_request

| Column | Type |
|--------|------|
| `id` | Int32 |
| `entity_name` | Nullable(String) |
| `entity_action` | Nullable(String) |
| `entity_id` | Nullable(String) |
| `context` | Nullable(String) |
| `status` | Nullable(String) |
| `original_http_request_id` | Nullable(Int32) |
| `authority_http_request_id` | Nullable(Int32) |
| `approval_http_request_id` | Nullable(Int32) |
| `denial_http_request_id` | Nullable(Int32) |
| `approval_policy_id` | Nullable(Int32) |
| `user_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `execution_status` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `cancel_http_request_id` | Nullable(Int32) |
| `specs_context` | Nullable(String) |
| `approval_action_id` | Nullable(Int32) |
| `policy_context` | Nullable(String) |
| `expires_at` | Nullable(DateTime64(6)) |
| `execution_expires_at` | Nullable(DateTime64(6)) |
| `aggregator_entity_id` | Nullable(String) |

### approvals_approval_spec

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `slug` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_approval_spec_value

| Column | Type |
|--------|------|
| `id` | Int32 |
| `approval_spec_id` | Nullable(Int32) |
| `version` | Nullable(Int32) |
| `rules` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_action

| Column | Type |
|--------|------|
| `id` | UUID |
| `status` | Nullable(String) |
| `entity` | Nullable(String) |
| `action` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `on_policy_success` | Nullable(String) |
| `on_policy_fail` | Nullable(String) |
| `type` | Nullable(String) |
| `when` | Nullable(String) |
| `on` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_action_policy

| Column | Type |
|--------|------|
| `id` | UUID |
| `entity_hook_action_id` | Nullable(UUID) |
| `policy_id` | Nullable(UUID) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_http_request

| Column | Type |
|--------|------|
| `id` | UUID |
| `entity_hook_request_id` | Nullable(UUID) |
| `headers` | Nullable(String) |
| `method` | Nullable(String) |
| `body` | Nullable(String) |
| `url` | Nullable(String) |
| `retries` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `type` | Nullable(String) |

### approvals_entity_hook_http_response

| Column | Type |
|--------|------|
| `id` | UUID |
| `headers` | Nullable(String) |
| `body` | Nullable(String) |
| `status` | Nullable(Int32) |
| `entity_hook_http_request_id` | Nullable(UUID) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_policy

| Column | Type |
|--------|------|
| `id` | UUID |
| `name` | Nullable(String) |
| `slug` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_policy_value

| Column | Type |
|--------|------|
| `id` | UUID |
| `policy_id` | Nullable(Int32) |
| `version` | Nullable(Int32) |
| `conditions` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_entity_hook_request

| Column | Type |
|--------|------|
| `id` | UUID |
| `entity_name` | Nullable(String) |
| `entity_action` | Nullable(String) |
| `entity_id` | Nullable(String) |
| `context` | Nullable(String) |
| `status` | Nullable(String) |
| `reply_approved` | Nullable(String) |
| `reply_denied` | Nullable(String) |
| `user_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `execution_status` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `entity_hook_action_id` | Nullable(UUID) |
| `policy_context` | Nullable(String) |
| `messages` | Nullable(String) |
| `type` | Nullable(String) |
| `when` | Nullable(String) |
| `on` | Nullable(String) |
| `dependencies` | Nullable(String) |

### approvals_policy

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `slug` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### approvals_policy_value

| Column | Type |
|--------|------|
| `id` | Int32 |
| `policy_id` | Nullable(Int32) |
| `version` | Nullable(Int32) |
| `conditions` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `selector` | Nullable(String) |

---

## Parameters Domain (5 tables)

### parameters_parameter

| Column | Type |
|--------|------|
| `id` | Int32 |
| `name` | Nullable(String) |
| `type` | Nullable(String) |
| `secret` | Nullable(UInt8) |
| `handle` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `encoding` | Nullable(String) |
| `read_only` | Nullable(UInt8) |

### parameters_parameter_value

| Column | Type |
|--------|------|
| `id` | Int64 |
| `location` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |
| `parameter_id` | Nullable(Int32) |
| `parameter_version` | Nullable(Int32) |
| `strategy_data` | Nullable(String) |
| `dimensions` | Nullable(String) |
| `external` | Nullable(String) |
| `checksum` | Nullable(String) |

### parameters_parameter_version

| Column | Type |
|--------|------|
| `id` | Int32 |
| `parameter_id` | Nullable(Int32) |
| `user_id` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### parameters_crypto_strategy

| Column | Type |
|--------|------|
| `id` | Int32 |
| `type` | Nullable(String) |
| `since` | Nullable(DateTime64(6)) |
| `configuration` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### parameters_external_storage_configuration

| Column | Type |
|--------|------|
| `id` | Int64 |
| `dimensions` | Nullable(String) |
| `since` | Nullable(DateTime64(6)) |
| `engine` | Nullable(String) |
| `configuration` | Nullable(String) |
| `encryption_metadata` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

---

## Governance Domain (4 tables)

### governance_action_items_action_items

| Column | Type |
|--------|------|
| `action_item_id` | String |
| `action_item_slug` | Nullable(String) |
| `title` | Nullable(String) |
| `description` | Nullable(String) |
| `status` | Nullable(String) |
| `priority` | Nullable(String) |
| `score` | Nullable(Int32) |
| `created_by` | Nullable(String) |
| `category_id` | Nullable(String) |
| `unit_id` | Nullable(String) |
| `value` | Nullable(String) |
| `due_date` | Nullable(DateTime64(6)) |
| `deferred_until` | Nullable(DateTime64(6)) |
| `resolved_at` | Nullable(DateTime64(6)) |
| `labels` | Nullable(String) |
| `affected_resources` | Nullable(String) |
| `references` | Nullable(String) |
| `metadata` | Nullable(String) |
| `config` | Nullable(String) |
| `comments` | Nullable(String) |
| `audit_logs` | Nullable(String) |
| `deferral_count` | Nullable(Int32) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### governance_action_items_categories

| Column | Type |
|--------|------|
| `category_id` | String |
| `category_slug` | Nullable(String) |
| `parent_id` | Nullable(String) |
| `category_name` | Nullable(String) |
| `description` | Nullable(String) |
| `color` | Nullable(String) |
| `icon` | Nullable(String) |
| `config` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### governance_action_items_suggestions

| Column | Type |
|--------|------|
| `suggestion_id` | String |
| `suggestion_slug` | Nullable(String) |
| `action_item_id` | Nullable(String) |
| `status` | Nullable(String) |
| `created_by` | Nullable(String) |
| `owner` | Nullable(String) |
| `confidence` | Nullable(String) |
| `description` | Nullable(String) |
| `metadata` | Nullable(String) |
| `user_metadata` | Nullable(String) |
| `user_metadata_config` | Nullable(String) |
| `executed_at` | Nullable(DateTime64(6)) |
| `execution_result` | Nullable(String) |
| `expires_at` | Nullable(DateTime64(6)) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

### governance_action_items_units

| Column | Type |
|--------|------|
| `unit_id` | String |
| `unit_slug` | Nullable(String) |
| `unit_name` | Nullable(String) |
| `symbol` | Nullable(String) |
| `status` | Nullable(String) |
| `created_at` | Nullable(DateTime64(6)) |
| `updated_at` | Nullable(DateTime64(6)) |

---

## SCM Domain (2 tables)

**No `_version` or `_deleted` columns.**

### scm_code_commits

| Column | Type |
|--------|------|
| `id` | UUID |
| `sha` | String |
| `message` | Nullable(String) |
| `author_name` | Nullable(String) |
| `author_email` | Nullable(String) |
| `date` | DateTime64(6) |
| `code_repository_id` | UUID |
| `created_at` | DateTime64(6) |
| `updated_at` | DateTime64(6) |

### scm_code_repositories

| Column | Type |
|--------|------|
| `id` | UUID |
| `external_repository_id` | String |
| `name` | String |
| `provider` | String |
| `stars` | Int64 |
| `forks` | Int64 |
| `language` | Nullable(String) |
| `private` | UInt8 |
| `description` | Nullable(String) |
| `url` | Nullable(String) |
| `date_created` | Nullable(DateTime64(6)) |
| `scm_organization_id` | UUID |
| `scm_organization_name` | Nullable(String) |
| `scm_organization_provider` | Nullable(String) |
| `scm_organization_host` | Nullable(String) |
| `scm_organization_installation_status` | Nullable(String) |
| `tags` | Map(String, String) |
| `created_at` | DateTime64(6) |
| `updated_at` | DateTime64(6) |

---

## Table Engines & Sorting Keys (Query Optimization)

All tables use **ReplicatedReplacingMergeTree** (deduplicates rows by `_version`) except `audit_events` which uses **ReplicatedMergeTree** (append-only, no dedup).

**Sorting key = Primary key** in all tables. Queries that filter on sorting key columns (especially the leftmost) are significantly faster because ClickHouse can skip data granules.

| Table | Sorting Key |
|-------|-------------|
| `audit_events` | `nrn, date` |
| `core_entities_metadata` | `entity, id, metadata_type` |
| `scm_code_commits` | `nrn, code_repository_id, date, id` |
| `scm_code_repositories` | `nrn, id` |
| `core_entities_account` | `account_id` |
| `core_entities_application` | `app_id` |
| `core_entities_namespace` | `namespace_id` |
| `core_entities_organization` | `org_id` |
| `core_entities_technology_template` | `template_id` |
| `governance_action_items_action_items` | `action_item_id` |
| `governance_action_items_categories` | `category_id` |
| `governance_action_items_suggestions` | `suggestion_id` |
| `governance_action_items_units` | `unit_id` |
| All other tables | `id` |

**Optimization tips:**
- `WHERE id = X` (or `account_id`, `app_id`, etc.) is fast — uses primary index
- `audit_events`: `WHERE nrn = '...' AND date >= ...` is fast; `WHERE user_email = '...'` requires full scan
- `scm_code_commits`: `WHERE nrn = '...'` is fast; `WHERE sha = '...'` requires full scan
- For non-key filters, combine with a key filter when possible to reduce scan range

---

## Entity Relationships

```
organization (org_id)
  └── account (account_id, FK: org_id)
       └── namespace (namespace_id, FK: account_id)
            └── application (app_id, FK: namespace_id)
                 ├── scope (id, FK: application_id)
                 │    ├── scope_dimension (FK: scope_id)
                 │    ├── scope_domain (FK: scope_id)
                 │    └── deployment (id, FK: scope_id) ← NO application_id!
                 ├── build (id, FK: app_id)
                 │    ├── asset (FK: build_id)
                 │    └── release (id, FK: build_id, app_id)
                 │         └── deployment (FK: release_id)
                 ├── deployment_group (FK: application_id)
                 └── technology_template (template_id)
```
