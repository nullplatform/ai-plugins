# Asset

Create and manage assets (build artifacts for deployment).

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np asset list` | List assets |
| `np asset read --id <id>` | Read an asset by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np asset create --body <json>` | Create an asset after uploading files to a URL |
| `np asset push --type <type> --source <file>` | Push and deploy an asset to the right repository |

## Flag Reference

### `np asset create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np asset list`

| Flag | Type | Description |
|------|------|-------------|
| `--build-id` | int | Filter by build ID |
| `--name` | string | Filter by asset name |

### `np asset push`

| Flag | Type | Description |
|------|------|-------------|
| `--application-id` | int | Application ID (alternative to build-id) |
| `--aws-access-key-id` | string | AWS Access Key ID |
| `--aws-region` | string | AWS Region to push asset |
| `--aws-secret-access-key` | string | AWS Secret Access Key |
| `--aws-session-token` | string | AWS Session Token |
| `--branch` | string | Branch name (used with application-id to find build) |
| `--build-id` | int | Build ID where the asset is being created |
| `--commit-sha` | string | Commit SHA (used with application-id to find build) |
| `--current-build-status` | string | Build status filter (default "in_progress") |
| `--extra-tags` | string | Extra tags (e.g., latest) |
| `--id` | int | Asset ID to push (if known) |
| `--name` | string | Asset name (default "main") |
| `--no-login` | bool | Skip Docker registry login |
| `--path` | string | Path for monorepo application lookup |
| `--platform` | string | Target platform of the asset |
| `--repository` | string | Repository URL to find application |
| `--source` | string | Docker tar/image or lambda file path to push |
| `--type` | string | Asset type: `docker-image`, `lambda`, or `bundle` |
| `--url` | string | URL for the asset. Required for bundle type |

### `np asset read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | Asset ID |

## Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `asset patch` | Use `PATCH /asset/:id` via API |
| `asset replace` | Use `PUT /asset/:id` via API |
| `asset update` | Use `PUT /asset/:id` via API |
