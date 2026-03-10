# Account

Create and manage accounts.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np account list` | List accounts in an organization |
| `np account read --id <id>` | Read account details by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np account create --body <json>` | Create a new account in an organization |
| `np account delete --id <id>` | Remove an account by ID |
| `np account update --id <id> --body <json>` | Update account information |

## Flag Reference

### `np account create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np account delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the account to delete |

### `np account list`

| Flag | Type | Description |
|------|------|-------------|
| `--organization_id` | string | Filter by organization ID |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np account read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the account to read |
| `--include` | string | Include related entities information |

### `np account update`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the account |
