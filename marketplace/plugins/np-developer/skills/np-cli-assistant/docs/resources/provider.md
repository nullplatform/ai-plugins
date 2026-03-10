# Provider

Create and manage providers and provider specifications. Providers are integrations that extend nullplatform capabilities.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np provider list` | List providers |
| `np provider read --id <id>` | Read a provider by ID (attributes resolved with inheritance) |
| `np provider category list` | List provider categories |
| `np provider category read --id <id>` | Read a provider category |
| `np provider specification list` | List provider specifications |
| `np provider specification read --id <id>` | Read a provider specification |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np provider create --body <json>` | Create a new provider |
| `np provider delete --id <id>` | Delete a provider by ID |
| `np provider patch --id <id> --body <json>` | Update a provider by ID |
| `np provider update --id <id> --body <json>` | Replace a provider by ID |

## Flag Reference

### `np provider create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np provider delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Provider ID |

### `np provider list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | The NRN of the resource to list providers |
| `--categories` | string | Category names to filter |
| `--dimensions` | string | Dimensions for the provider |
| `--id` | string | Provider ID filter |
| `--include` | string | Attributes to include in the response |
| `--specification` | string | Provider specification IDs to filter by |
| `--specification_id` | string | Provider specification ID (comma-separated) |
| `--specification_slug` | string | Provider specification slug (comma-separated) |
| `--show_ascendants` | bool | Show entities from higher NRN hierarchy levels |
| `--show_descendants` | bool | Show entities from lower NRN hierarchy levels |
| `--limit` | int | Max results per call (default 30) |
| `--offset` | int | Pagination offset |

### `np provider patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Provider ID |

### `np provider read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Provider ID |
| `--include` | string | Include related entities information |
| `--no_merge` | bool | Skip hierarchical attribute merging |

### `np provider update`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Provider ID |

### `np provider category list`

| Flag | Type | Description |
|------|------|-------------|
| `--include` | string | Related resources to include |
| `--slug` | string | Unique category slug to filter by |
| `--type` | string | Category type slug (e.g., "menu") |
| `--limit` | int | Max results per call (default 30) |
| `--offset` | int | Pagination offset |

### `np provider category read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Category ID |
| `--include` | string | Related resources to include |

### `np provider specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | NRN filter |
| `--category` | string | Category IDs to filter by |
| `--name` | string | Provider specification name |
| `--slug` | string | Unique slug for the specification |
| `--limit` | int | Max results per call (default 30) |
| `--offset` | int | Pagination offset |

### `np provider specification read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID |
| `--include` | string | Include related entities information |

## Gotchas

- `np provider read` resolves attributes with **inheritance** by default. Use `--no_merge` to get only the provider's own attributes without parent merging.
- Provider dependencies may need to be met before creating a new provider. Check the provider specification for required dependencies.
