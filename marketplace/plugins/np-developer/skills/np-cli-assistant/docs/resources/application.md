# Application

Create and manage applications.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np application current` | Get the application for the current repository |
| `np application list` | List applications in a namespace |
| `np application read --id <id>` | Read application details by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np application create --body <json>` | Create a new application in a namespace |
| `np application patch --id <id> --body <json>` | Patch an existing application |
| `np application update --id <id> --body <json>` | Update application information |

## Flag Reference

### `np application create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np application current`

| Flag | Type | Description |
|------|------|-------------|
| `--application-id` | int | Application ID (alternative to repository option) |
| `--path` | string | Path to application in monorepo |
| `--repository` | string | Repository URL used to find the application |

### `np application list`

| Flag | Type | Description |
|------|------|-------------|
| `--namespace_id` | string | Filter by namespace ID (comma-separated, up to 10 values) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np application patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the application to update |

### `np application read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the application to read |
| `--include` | string | Include related entities information |

### `np application update`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the application to update |

## Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `application delete` | Use `DELETE /application/:id` via API |

## Gotchas

- Use `--namespace_id`, **not** `--nrn`, to filter applications by namespace. The `--nrn` flag does not exist on `application list`.
