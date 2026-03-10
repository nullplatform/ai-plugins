# Build

Create and manage builds (CI/CD pipeline artifacts).

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np build list` | List builds for an application |
| `np build read --id <id>` | Read build details by ID |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np build asset-url create --id <id> --body <json>` | Generate a URL for uploading build assets |
| `np build create --body <json>` | Create a new build for an application |
| `np build patch --id <id> --body <json>` | Update build information |
| `np build start` | Start a new build |
| `np build update --status <status>` | Update an existing build status (`successful` or `failed`) |

## Flag Reference

### `np build asset-url create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the build |

### `np build create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np build list`

| Flag | Type | Description |
|------|------|-------------|
| `--application_id` | string | The application ID to filter builds |
| `--branch` | string | Filter by branch name |
| `--commit.id` | string | Filter by commit ID |
| `--commit.permalink` | string | Filter by commit permalink |
| `--description` | string | Filter by build description |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

### `np build patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | The ID of the build to update |

### `np build read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The ID of the build to read |
| `--include` | string | Include related entities information |

### `np build start`

| Flag | Type | Description |
|------|------|-------------|
| `--application-id` | int | Application ID where the build is created |
| `--branch` | string | Branch name for the build |
| `--commit-permalink` | string | Commit permanent link |
| `--commit-sha` | string | Commit SHA hash |
| `--description` | string | Build description |
| `--path` | string | Path to application in monorepo |
| `--repository` | string | Repository URL to find the application |

### `np build update`

| Flag | Type | Description |
|------|------|-------------|
| `--application-id` | int | Application ID (alternative to build ID) |
| `--branch` | string | Branch name (used to find build if no ID) |
| `--commit-sha` | string | Commit SHA (used to find build if no ID) |
| `--current-status` | string | Current build status filter (default "in_progress") |
| `--id` | int | Build ID |
| `--path` | string | Path to application in monorepo |
| `--repository` | string | Repository URL to find the application |
| `--status` | string | Updated status: `successful` or `failed` |

## Gotchas

- `np build update` auto-infers flags from CI environment variables (GitHub Actions, GitLab, Azure DevOps). Explicit flags override inferred values.
- `np build start` and `np build update` can locate builds by `--application-id` + `--commit-sha` + `--branch` instead of `--id`.
