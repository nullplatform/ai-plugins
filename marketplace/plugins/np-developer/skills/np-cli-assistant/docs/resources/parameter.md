# Parameter

Create and manage parameters (application and scope configuration values).

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np parameter list` | List parameters by NRN |
| `np parameter read --id <id>` | Read a parameter by ID |
| `np parameter version list --id <id>` | List versions available for a parameter |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np parameter create --body <json>` | Create an application parameter |
| `np parameter delete --id <id>` | Delete a parameter and all its values/versions (permanent) |
| `np parameter update --id <id> --body <json>` | Create or replace parameter fields (does not affect values) |
| `np parameter value create --id <id> --body <json>` | Create a parameter value |
| `np parameter value delete --parameterId <id> --id <id>` | Delete a parameter value (creates new version without it) |
| `np parameter values create --id <id> --body <json>` | Create parameter values (bulk) |
| `np parameter values delete --parameterId <id> --ids <ids>` | Delete multiple parameter values (bulk) |

## Flag Reference

### `np parameter create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np parameter delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the parameter |

### `np parameter list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | The NRN to which the parameter belongs |
| `--interpolate` | string | If true, interpolation will be applied to existing parameters |
| `--show_secret_values` | string | If true, secret values will be shown |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np parameter read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the parameter |
| `--include` | string | Include related entities information |

### `np parameter update`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the parameter |

### `np parameter value create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the parameter |

### `np parameter value delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the parameter value to delete |
| `--parameterId` | string | The ID of the parameter |

### `np parameter values create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the parameter |

### `np parameter values delete`

| Flag | Type | Description |
|------|------|-------------|
| `--ids` | string | The IDs of the parameter values to delete |
| `--parameterId` | string | The ID of the parameter |

### `np parameter version list`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the parameter |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

## Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `parameter patch` | Use `PATCH /parameter/:id` via API |
| `parameter value compare` | Use API instead |
