---
name: np-service-specs
description: Use when working with nullplatform service spec files — service-spec.json.tpl, link specs (connect.json.tpl), values.yaml, attribute schemas, export configuration, and spec authoring conventions.
---

# Nullplatform Service Specs

Conventions for service specification files: service-spec.json.tpl, link specs, and values.yaml.

## Critical Rules

1. **Schema MUST be in `attributes.schema`** — NEVER use `specification_schema` as top-level field. The terraform module passes `attributes` directly to the API. Using `specification_schema` causes "No applicable renderer found" in the UI.
2. **`visible_to` is IGNORED** in the template JSON — visibility is controlled via the `nrn` parameter in the terraform module.
3. **Link specs follow the same rule** — schema in `attributes.schema`, not `specification_schema`.
4. **VALUES is a FILE PATH** — scripts read values.yaml via `yaml_value()`, not jq.

## Service Spec Structure

```json
{
  "name": "Service Name",
  "slug": "service-slug",
  "type": "dependency",
  "unique": false,
  "assignable_to": "any",
  "use_default_actions": true,
  "available_links": ["connect"],
  "selectors": {
    "category": "Database|Cache|Storage|Messaging|Networking|Security",
    "imported": false,
    "provider": "AWS|Azure|GCP|any",
    "sub_category": "Relational Database|NoSQL|In-Memory Cache|..."
  },
  "attributes": {
    "schema": {
      "type": "object",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "required": ["field1"],
      "properties": { ... }
    },
    "values": {}
  }
}
```

## Field Properties

| Property | Values | Description |
|----------|--------|-------------|
| `editableOn` | `["create"]`, `["create","update"]`, `[]` | When the field can be edited. `[]` = output field |
| `visibleOn` | `["read"]` | When the field is visible. Use for output fields |
| `export` | `true`, `{"type":"environment_variable","secret":true}` | Export as env var when link activates |
| `order` | number | UI field ordering |
| `enum` | `["val1","val2"]` | Restrict to specific values |
| `default` | any | Default value |

## Field Types

| Type | editableOn | export | Use |
|------|-----------|--------|-----|
| Input (user chooses) | `["create"]` | `true` (optional) | `bucket_name`, `region` |
| Output (post-provisioning) | `[]` | `true` | `bucket_arn`, `endpoint` |
| Secret output | `[]` | `{"type":"environment_variable","secret":true}` | `secret_access_key` |

Output fields are populated post-provisioning by `write_service_outputs` / `write_link_outputs` scripts.

## Link Spec Structure

```json
{
  "name": "Connect",
  "slug": "connect",
  "unique": false,
  "use_default_actions": true,
  "attributes": {
    "schema": {
      "type": "object",
      "properties": {
        "accessLevel": {
          "enum": ["read", "write", "read-write"],
          "type": "string",
          "default": "read-write",
          "editableOn": ["create", "update"]
        },
        "access_key_id": {
          "type": "string",
          "export": true,
          "visibleOn": ["read"],
          "editableOn": []
        },
        "secret_access_key": {
          "type": "string",
          "export": {"type": "environment_variable", "secret": true},
          "visibleOn": ["read"],
          "editableOn": []
        }
      }
    },
    "values": {}
  }
}
```

## values.yaml

Static configuration not exposed in the UI. Read in scripts with `yaml_value()`:

```bash
yaml_value() {
  local key="$1" default="$2" file="$3"
  val=$(grep "^${key}:" "$file" 2>/dev/null | sed 's/^[^:]*: *//;s/^"//;s/"$//' | head -1)
  echo "${val:-$default}"
}
REGION=$(yaml_value "region" "us-east-1" "$VALUES")
```

Typical values.yaml fields: `region`, `aws_profile`, `resource_group_name`, `account_name`.

## Validation Commands

```bash
# Schema in attributes.schema (MUST pass)
jq -e '.attributes.schema.type' specs/service-spec.json.tpl

# No specification_schema (MUST fail)
jq -e '.specification_schema' specs/service-spec.json.tpl && echo "ERROR" || echo "OK"

# Links also use attributes.schema
jq -e '.attributes.schema' specs/links/*.json.tpl

# Valid JSON
jq . specs/*.json.tpl specs/links/*.json.tpl
```

For details on how export generates env vars, see `docs/export-parameters.md`.
