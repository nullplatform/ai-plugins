# Service

Create and manage services, service actions, service specifications, and service workflows. Also includes `service-action` commands for workflow execution.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np service list` | List services |
| `np service read --id <id>` | Read a service |
| `np service action list --serviceId <id>` | List service actions |
| `np service action read --serviceId <id> --id <id>` | Read a service action |
| `np service specification list` | List service specifications |
| `np service specification read --id <id>` | Read a service specification |
| `np service specification action specification list --serviceSpecificationId <id>` | List service specification actions |
| `np service specification action specification read --serviceSpecificationId <id> --id <id>` | Read a service specification action |
| `np service specification link specification list --id <id>` | List associated link specifications |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np service create --body <json>` | Create a service |
| `np service delete --id <id>` | Delete a service |
| `np service patch --id <id> --body <json>` | Update a service |
| `np service action create --serviceId <id> --body <json>` | Create a service action |
| `np service action delete --serviceId <id> --id <id>` | Delete a service action |
| `np service action patch --serviceId <id> --id <id> --body <json>` | Update a service action |
| `np service action update` | Update a service action result (workflow context) |
| `np service compare create --id <id> --body <json>` | Compare two services |
| `np service specification create --body <json>` | Create a service specification |
| `np service specification delete --id <id>` | Delete a service specification |
| `np service specification patch --id <id> --body <json>` | Update a service specification |
| `np service specification action specification create --serviceSpecificationId <id> --body <json>` | Create a service specification action |
| `np service specification action specification delete --serviceSpecificationId <id> --id <id>` | Delete a service specification action |
| `np service specification action specification patch --serviceSpecificationId <id> --id <id> --body <json>` | Update a service specification action |
| `np service workflow exec` | Execute a service workflow |
| `np service workflow build-context` | Build context for a service workflow |

### service-action Commands

| Command | Description |
|---------|-------------|
| `np service-action exec` | Execute action script with context environment variables |
| `np service-action export-action-data` | Export action context data |
| `np service-action get-exec-path` | Get the script path for an action |
| `np service-action get-exec-script` | Get the script content for an action |

## Flag Reference

### `np service list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | NRN filter |
| `--entity_nrn` | string | Entity NRN filter |
| `--id` | string | Service ID filter |
| `--specification_id` | string | Service specification ID filter |
| `--status` | string | Service status filter |
| `--type` | string | Service type filter |
| `--include_messages` | bool | Include messages |
| `--include_secret_attributes` | bool | Show secret attribute values |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np service read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Service ID |
| `--include` | string | Include related entities information |

### `np service create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np service delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Service ID |
| `--force` | bool | Force delete without checking for delete action existence |

### `np service patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Service ID |

### `np service action create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--serviceId` | string | Service ID |

### `np service action delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action ID |
| `--serviceId` | string | Service ID |

### `np service action list`

| Flag | Type | Description |
|------|------|-------------|
| `--serviceId` | string | Service ID |
| `--id` | string | Action ID filter |
| `--nrn` | string | NRN filter |
| `--status` | string | Action status filter |
| `--include_messages` | bool | Include messages |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np service action patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Action ID |
| `--serviceId` | string | Service ID |

### `np service action read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action ID |
| `--include` | string | Include related entities information |
| `--serviceId` | string | Service ID |

### `np service action update`

| Flag | Type | Description |
|------|------|-------------|
| `--service-action-id` | string | Service Action ID (auto-populated from NP_ACTION_CONTEXT if not set) |
| `--service-id` | string | Service ID (auto-populated from NP_ACTION_CONTEXT if not set) |
| `--messages` | string | Action messages of provisioning process |
| `--results` | string | Action results once provisioned |
| `--status` | string | Status of action: `success` or `failed` |

### `np service compare create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Service ID |

### `np service specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID filter |
| `--nrn` | string | NRN filter |
| `--type` | string | Specification type filter |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np service specification read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID |
| `--include` | string | Include related entities information |
| `--nrn` | string | NRN filter |
| `--type` | string | Specification type filter |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np service specification create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np service specification delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Specification ID |

### `np service specification patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Specification ID |

### `np service specification action specification create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--serviceSpecificationId` | string | Service specification ID |

### `np service specification action specification delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action specification ID |
| `--serviceSpecificationId` | string | Service specification ID |

### `np service specification action specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--serviceSpecificationId` | string | Service specification ID |
| `--application_id` | string | Application ID for dynamic properties |
| `--id` | string | Action specification ID filter |
| `--link_id` | string | Link ID for dynamic properties |
| `--link_specification_id` | string | Link specification ID filter |
| `--nrn` | string | NRN filter |
| `--service_id` | string | Service ID for dynamic properties |
| `--service_specification_id` | string | Service specification ID filter |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np service specification action specification patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | string | Action specification ID |
| `--serviceSpecificationId` | string | Service specification ID |

### `np service specification action specification read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action specification ID |
| `--include` | string | Include related entities information |
| `--serviceSpecificationId` | string | Service specification ID |

### `np service specification link specification list`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Service specification ID |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np service workflow build-context`

| Flag | Type | Description |
|------|------|-------------|
| `--include-secrets` | bool | Fetch secret parameters |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |
| `--provider-categories` | string | Provider categories to fetch |

### `np service workflow exec`

| Flag | Type | Description |
|------|------|-------------|
| `--build-context` | bool | Generate context for the action |
| `--dry-run` | bool | Print workflow instead of executing |
| `--include-secrets` | bool | Fetch secret parameters |
| `--no-output` | bool | Suppress context logs |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |
| `--workflow` | string | The workflow to execute |

### `np service-action exec`

| Flag | Type | Description |
|------|------|-------------|
| `--base-path` | string | Base path for the script |
| `--command` | string | Hardcoded command to run |
| `--debug` | bool | Print context in base64 for debugging |
| `--disable-auto-action-update` | bool | Disable automatic action status update based on exit code |
| `--dry-run` | bool | Print script instead of running |
| `--live-output` | bool | Show command output in real-time |
| `--live-report` | bool | Report output to action status in real-time |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |
| `--script` | string | Hardcoded script to run |

### `np service-action export-action-data`

| Flag | Type | Description |
|------|------|-------------|
| `--debug` | bool | Print context in base64 for debugging |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |

### `np service-action get-exec-path`

| Flag | Type | Description |
|------|------|-------------|
| `--base-path` | string | Base path for the script |
| `--debug` | bool | Print context in base64 for debugging |
| `--lookup-by` | string | Lookup strategy to build exec path |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |
| `--script` | bool | Hardcoded script to run |

### `np service-action get-exec-script`

| Flag | Type | Description |
|------|------|-------------|
| `--base-path` | string | Base path for the script |
| `--debug` | bool | Print context in base64 for debugging |
| `--notification` | string | Notification data (auto-inferred from NP_ACTION_CONTEXT) |
| `--script` | string | Hardcoded script to run |

## Gotchas

- **`--force` on delete**: skips checking for a delete action. Use only when you're sure no cleanup is needed.
- **`NP_ACTION_CONTEXT`**: many service-action and workflow commands auto-infer context from this environment variable. Set it when running in CI/CD or notification-triggered workflows.
- **`service-action exec`** auto-updates action status based on exit code (0 = success, non-zero = failed). Use `--disable-auto-action-update` to control this manually.
- **Creating scope specifications**: use `np service specification create --body <json>` with `"type": "scope"` in the body. Do NOT use `np scope specification create` — that command is deprecated (still appears in `np --help` due to tech debt but should not be suggested to users).
