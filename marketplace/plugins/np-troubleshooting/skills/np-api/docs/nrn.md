# NRN (Nullplatform Resource Name)

NRN is a unique hierarchical identifier for any resource in Nullplatform (similar to AWS ARN).
In addition to identifying resources, the `/nrn/` endpoint functions as a hierarchical key-value store
with automatic inheritance.

**DEPRECATION NOTE**: The NRN as key-value store may be removed in the future.
Nullplatform recommends using platform settings and providers instead.

## Format

```
organization=123:account=456:namespace=789:application=101:scope=202
```

Levels (from highest to lowest):
1. `organization=<id>`
2. `organization=<id>:account=<id>`
3. `organization=<id>:account=<id>:namespace=<id>`
4. `organization=<id>:account=<id>:namespace=<id>:application=<id>`
5. `organization=<id>:account=<id>:namespace=<id>:application=<id>:scope=<id>`

## NRN as configuration scope

Many entities are created at an NRN level and cascade to children:

| Entity | Cascades | Example |
|--------|----------|---------|
| Dimension | Yes | Created at org, visible in all accounts/namespaces/apps |
| Entity Hook Action | Yes | Created at account, applies to all account apps |
| Notification Channel | Yes (with showDescendants) | Created at account, visible with `showDescendants=true` |
| Runtime Configuration | Yes | Created at a level, affects scopes that match dimensions |
| Approval Action | Yes | Created at account, applies to all account apps |

**Parent-child rule for Dimensions**: The same dimension cannot exist in both parent AND child.
It can exist in siblings (two different accounts).

## @endpoint /nrn/{nrn_string}

Reads values from the hierarchical key-value store. Values are inherited and merged from upper
levels.

### Parameters
- `nrn_string` (path, required): Complete NRN (NOT URL-encoded in the path)
- `ids` (query, **required**): Comma-separated list of keys
- `output_json_values` (query): `true` to parse JSON instead of returning strings
- `no-merge` (query): `true` to get only values from this level, without inheritance
- `profile` (query): Profile name to apply

### Example
```bash
# Read specific values
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1,key2"

# Without inheritance (only this level)
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1&no-merge=true"

# With profile
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1&profile=my-profile"
```

### Inheritance and merge

When reading a key at a child NRN:
1. The key is searched at the specified NRN
2. If it doesn't exist, it's searched in the parent (and so on)
3. If it exists at multiple levels, a **deep merge** of JSON objects and arrays is performed
4. The child overrides parent values

### Notes
- `ids` is **mandatory** — without it, the endpoint returns nothing useful
- Values can be strings, JSON objects, or JSON arrays
- With `output_json_values=true`, JSON strings are automatically parsed
- With `no-merge=true`, only values from the exact NRN level are returned
- **Potentially deprecated**: consider using platform settings/providers

---

## @endpoint /nrn/{nrn_string}/available_profiles

Lists available profiles for an NRN.

### Parameters
- `nrn_string` (path, required): Complete NRN

### Example
```bash
np-api fetch-api "/nrn/organization=1255165411:account=95118862/available_profiles"
```

### Notes
- Profiles allow cross-cutting configuration (e.g., per-environment configuration)
- Naming convention: `${profile_name}::${namespace}.${key}`
- Profiles have ordering (lower number = higher priority)
- They are assigned to scopes to apply the corresponding configuration

---

## Wildcards in NRN

Some endpoints support wildcards to scan levels:

```bash
# All org accounts (dimension, service, etc.)
GET /dimension?nrn=organization%3D1255165411%3Aaccount%3D*

# All org services
GET /service?nrn=organization%3D1255165411%3Aaccount%3D*&limit=1500
```

The `*` wildcard replaces the ID at a level and returns results from all children.

## URL Encoding

In query params, the NRN must be URL-encoded:
- `=` → `%3D`
- `:` → `%3A`

In path params (`/nrn/{nrn_string}`), the NRN goes without encoding.
