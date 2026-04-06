# Metadata (Catalog)

Metadata and metadata specifications for entities. Also known as **Catalog** in the
official documentation (rebranding). The catalog system allows attaching structured
and reusable metadata to entities (applications, builds, namespaces).

These endpoints live in the `metadata.nullplatform.io` microservice and are accessed via the
public API with the `/metadata/` prefix.

**IMPORTANT**: All endpoints in this file require the `/metadata/` prefix in the URL.
Example: to reach `metadata.nullplatform.io/metadata_specification` use
`np-api fetch-api "/metadata/metadata_specification?..."`.

---

## @endpoint /metadata/metadata_specification

Gets the formal metadata schema for an entity at a specific NRN.
Returns the required fields, types, enums, and descriptions defined by the organization.

### Parameters
- `entity` (query, required): Entity type (`application`, `build`, `namespace`, etc.)
- `nrn` (query, required): Context NRN (URL-encoded). Can be at namespace, account, or organization level.
- `merge` (query, optional): `true` to merge inherited specifications from upper NRN levels

### Response
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "entity": "application",
      "metadata": "application",
      "name": "Application",
      "nrn": "organization=X:account=Y:namespace=Z",
      "schema": {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "required": ["businessUnit", "pci", "slo", "applicationOwner"],
        "properties": {
          "businessUnit": {
            "type": "string",
            "description": "The business unit responsible for the service",
            "enum": ["Credits", "Payments", "OnBoarding", "KYC", "Money Market"]
          },
          "pci": {
            "type": "string",
            "description": "Whether the service is PCI compliant",
            "enum": ["Yes", "No"]
          }
        },
        "additionalProperties": false
      }
    }
  ]
}
```

### Navigation
- **← from application creation**: Needed to know what metadata to request from the user when creating an app
- **← from build metadata**: Used to validate build metadata

### Example
```bash
# Metadata specification for applications in a namespace
np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973&merge=true"
```

### Catalog Properties in the schema

The JSON Schema properties may have additional fields that control behavior
in the UI (Catalog system):

| Field | Description | Example |
|-------|-------------|---------|
| `visibleOn` | Controls where the field is shown in the UI | `["create", "read", "update", "list"]` |
| `tag` | Enables the field as a tag/filter in dashboards | `true` or `"custom_tag_name"` |
| `uiSchema` | Override of the automatic form layout | `{"ui:widget": "textarea"}` |
| `links` | Renders dedicated resource blocks | See official docs |

**`visibleOn` values:**
- `create`: visible when creating the entity
- `read`: visible when viewing the entity
- `update`: visible when editing the entity
- `list`: visible in listings/tables

### Supported entities
- `application`: application metadata
- `build`: build metadata (e.g., test coverage, security scan results)
- `namespace`: namespace metadata

### Notes
- The `nrn` in the query param must be URL-encoded (`:` → `%3A`, `=` → `%3D`)
- Schema fields are **organization-specific**: each org defines its own fields
- `merge=true` combines specifications from all NRN levels (org + account + namespace)
- The `schema` field follows JSON Schema draft-07 format
- `required` indicates mandatory fields when creating the entity
- `enum` in properties defines valid values (shown as dropdowns in the UI)
- If `results` is empty, the organization doesn't require metadata for that entity
- **Catalog vs Metadata**: "Catalog" is the new name in official documentation; the API still uses `/metadata/` as prefix
- Fields with `tag: true` are indexed and allow fast filtering in the UI
- `visibleOn` is key to controlling which fields appear in each UI context

---

## @endpoint /metadata/{entity}/{id}

Reads metadata of a specific entity.

### Parameters
- `entity` (path, required): Entity type (`application`, `build`, `namespace`)
- `id` (path, required): Entity ID

### Response (GET)
```json
{
  "application": {
    "businessUnit": "Payments",
    "pci": "No",
    "slo": "High",
    "applicationOwner": "Jane Smith"
  },
  "additional_properties": {}
}
```

### Example
```bash
# Read application metadata
np-api fetch-api "/metadata/application/489238271"

# Read metadata for multiple entities by ID
np-api fetch-api "/metadata/application?id=123,456,789"
```

### Notes
- Application metadata is also included in `GET /application/{id}` (`metadata` field)
- But the list `GET /application` does NOT include metadata - requires individual fetch or using this endpoint
