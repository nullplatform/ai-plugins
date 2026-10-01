# Dimensions

Dimensions define the variation axes (environment, country, region, etc.) to classify
scopes, services, parameters, approvals, and runtime configurations.

**IMPORTANT**: Dimensions are created at a specific NRN level, NOT necessarily at the
organization level. They cascade downward (children inherit). The same dimension cannot exist
in a parent-child relationship (but can in siblings).

They are used when creating scopes, services, deployments, and in approval policies.

## @endpoint /dimension

Lists dimensions available at an NRN, including dimensions inherited from upper levels.

### Parameters
- `nrn` (query, required): URL-encoded NRN. Accepts any hierarchy level.
  - Scans upward: returns dimensions of the specified NRN and all its parents
  - Supports wildcards: `account=*` to scan children

### Response
```json
{
  "paging": {"total": 2, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 1599217067,
      "name": "Environment",
      "slug": "environment",
      "nrn": "organization=1255165411",
      "status": "active",
      "order": 1,
      "values": [
        {"id": 1977891659, "name": "Development", "slug": "development"},
        {"id": 209213675, "name": "Production", "slug": "production"},
        {"id": 217338261, "name": "Stress Test", "slug": "stress-test"}
      ],
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Key fields
- `id`: Numeric dimension ID
- `name`: Visible name (e.g., "Environment", "Country")
- `slug`: URL-friendly identifier. **This is the key used in the `dimensions` field of scopes and services**
- `nrn`: NRN where the dimension was created (can be org, account, namespace, etc.)
- `order`: Priority/display order
- `values[]`: Possible values for the dimension
  - `id`: Numeric value ID
  - `name`: Visible name (e.g., "AR", "Production")
  - `slug`: **This is the value used in the `dimensions` field** (e.g., "argentina", "production")
  - `nrn`: Value's NRN (can be a lower level than the dimension itself)

### Relationship with other entities

The `dimensions` field in scopes, services, links, approvals, and runtime configurations uses slugs:
```json
{
  "dimensions": {
    "environment": "production",
    "country": "argentina"
  }
}
```
Where `"environment"` is the dimension slug and `"production"` is the value slug.

### NRN and dimension inheritance

Dimensions cascade downward in the NRN hierarchy:
- A dimension created at `organization=1` is visible in all accounts, namespaces, and applications
- A dimension created at `organization=1:account=2` is visible only in that account and its children

**Parent-child restriction**: The same dimension (same slug) cannot exist in both a parent NRN AND a child NRN. It can exist in siblings (e.g., two different accounts can have dimensions with the same slug).

### Example
```bash
# Organization dimensions (highest level)
np-api fetch-api "/dimension?nrn=organization%3D1255165411"

# Dimensions visible from an account (includes inherited from org)
np-api fetch-api "/dimension?nrn=organization%3D1255165411%3Aaccount%3D95118862"

# Dimensions from all accounts (wildcard)
np-api fetch-api "/dimension?nrn=organization%3D1255165411%3Aaccount%3D*"

# Only active dimensions with their values
np-api fetch-api "/dimension?nrn=organization%3D1255165411" | jq '[.results[] | {name: .slug, values: [.values[] | .slug]}]'
```

### Notes
- Dimensions are created at a specific NRN level, not necessarily at org level
- Dimension values can have their own NRN (at a lower level than the dimension)
- When creating a scope, `dimensions` values must match valid slugs from this endpoint
- When creating a service, `dimensions` restrict which scopes can link to it
- `ops` permissions are needed to create/modify dimensions
- Be cautious when adding many dimensions: it increases the scope matrix complexity

---

## @endpoint /dimension/{id}

Gets detail of a specific dimension (without its values).

### Parameters
- `id` (path, required): Numeric dimension ID

### Response
```json
{
  "id": 1599217067,
  "name": "Environment",
  "nrn": "organization=1255165411",
  "slug": "environment",
  "status": "active",
  "order": 1,
  "created_at": "...",
  "updated_at": "..."
}
```

### Notes
- Does not include dimension values (use `GET /dimension?nrn=...` to get values included)
- Useful to verify if a specific dimension exists

---

## @endpoint /dimension/value

Lists dimension values filtered by NRN.

### Parameters
- `nrn` (query, required): URL-encoded NRN. Supports wildcards.

### Response
```json
{
  "paging": {"total": 10, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 587888267,
      "name": "AR",
      "slug": "argentina",
      "nrn": "organization=1255165411",
      "status": "active",
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Example
```bash
# Dimension values at organization level
np-api fetch-api "/dimension/value?nrn=organization%3D1255165411"

# Values with wildcard (all accounts)
np-api fetch-api "/dimension/value?nrn=organization%3D1255165411%3Aaccount%3D*"
```

### Notes
- Useful when only values are needed without the parent dimension
- Individual values can have their own NRN at a lower level than the dimension

---

## @endpoint /dimension/value/{id}

Gets detail of a specific dimension value.

### Parameters
- `id` (path, required): Numeric value ID

### Response
```json
{
  "id": 587888267,
  "name": "AR",
  "slug": "argentina",
  "nrn": "organization=1255165411",
  "status": "active",
  "created_at": "...",
  "updated_at": "..."
}
```

### Notes
- Useful to verify if a specific value exists
- The `slug` is what's used as value in the `dimensions` field of scopes/services
