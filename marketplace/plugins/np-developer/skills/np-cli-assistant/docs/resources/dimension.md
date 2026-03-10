# Dimension

Create and manage dimensions and dimension values. Dimensions define context axes (e.g., environment, region) used across scopes and runtime configurations.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np dimension list` | List dimensions by NRN |
| `np dimension read --id <id>` | Read a dimension by ID |
| `np dimension value list` | List dimension values by NRN |
| `np dimension value read --dimensionId <id> --id <id>` | Read a dimension value |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np dimension create --body <json>` | Create a dimension |
| `np dimension delete --id <id>` | Remove a dimension by ID |
| `np dimension patch --id <id> --body <json>` | Update a dimension |
| `np dimension value create --dimensionId <id> --body <json>` | Create a dimension value |
| `np dimension value delete --dimensionId <id> --id <id>` | Remove a dimension value |
| `np dimension value patch --dimensionId <id> --id <id> --body <json>` | Update a dimension value |

## Flag Reference

### `np dimension create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np dimension delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the dimension to delete |

### `np dimension list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Filter by NRN (at or above the specified level) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np dimension patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the dimension to update |

### `np dimension read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the dimension to read |
| `--include` | string | Include related entities information |

### `np dimension value create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--dimensionId` | string | The ID of the dimension |

### `np dimension value delete`

| Flag | Type | Description |
|------|------|-------------|
| `--dimensionId` | string | The ID of the dimension |
| `--id` | string | The ID of the dimension value to delete |

### `np dimension value list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Filter by NRN (at or above the specified level) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np dimension value patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--dimensionId` | string | The ID of the dimension |
| `--id` | string | The ID of the dimension value to update |

### `np dimension value read`

| Flag | Type | Description |
|------|------|-------------|
| `--dimensionId` | string | The ID of the dimension |
| `--id` | string | The ID of the dimension value |
| `--include` | string | Include related entities information |
