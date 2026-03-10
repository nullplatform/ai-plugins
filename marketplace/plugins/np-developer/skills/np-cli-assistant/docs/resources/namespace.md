# Namespace

Create and manage namespaces. Namespaces organize applications within an account.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np namespace list` | List namespaces in an account |
| `np namespace read --id <id>` | Read namespace details by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np namespace create --body <json>` | Create a new namespace in an account |
| `np namespace update --id <id> --body <json>` | Update namespace information |

## Flag Reference

### `np namespace create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np namespace list`

| Flag | Type | Description |
|------|------|-------------|
| `--account_id` | string | Filter by account ID (comma-separated, up to 10 values) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np namespace read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the namespace to read |
| `--include` | string | Include related entities information |

### `np namespace update`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the namespace to update |

## Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `namespace delete` | Use `DELETE /namespace/:id` via API |
