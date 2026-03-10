# Approval

Create and manage approvals, approval actions, and approval policies.

## Commands

### Read-Only

| Command | Description |
|---------|-------------|
| `np approval list` | List approvals |
| `np approval read --id <id>` | Read an approval |
| `np approval is_required` | Check if approval is required for a given NRN/entity/action |
| `np approval action list` | List approval actions filtered by NRN, entity, action, or dimensions |
| `np approval action read --id <id>` | Read an approval action |
| `np approval policy list` | List policies filtered by NRN |
| `np approval policy read --id <id>` | Read a policy |

### Write (mutating)

| Command | Description |
|---------|-------------|
| `np approval action create --body <json>` | Create a new approval action |
| `np approval action delete --id <id>` | Delete an approval action (permanent) |
| `np approval action patch --id <id> --body <json>` | Update on_policy_success and on_policy_fail fields |
| `np approval action policy create --id <id> --body <json>` | Associate a policy with an approval action |
| `np approval action policy delete --id <id> --policy_id <id>` | Disassociate a policy from an approval action |
| `np approval policy create --body <json>` | Create a new policy |
| `np approval policy delete --id <id>` | Delete a policy (permanent) |
| `np approval policy patch --id <id> --body <json>` | Update policy conditions |

## Flag Reference

### `np approval list`

| Flag | Type | Description |
|------|------|-------------|
| `--approval_action_id` | int | The ID of the action that triggered this approval |
| `--entity_action` | string | The action that requires approval |
| `--entity_name` | string | The entity that requires approval |
| `--nrn` | string | The resource (application, scope, etc.) that requires approval |
| `--status` | string | The status of the approval |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np approval read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the approval |
| `--include` | string | Include related entities information |

### `np approval is_required`

| Flag | Type | Description |
|------|------|-------------|
| `--action` | string | The action that requires approval |
| `--dimensions` | string | Dimensions configured, multiple key-value pairs separated by commas |
| `--entity` | string | The entity that requires approval |
| `--nrn` | string | The resource (application, scope, etc.) that requires approval |

### `np approval action create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np approval action delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the approval action |

### `np approval action list`

| Flag | Type | Description |
|------|------|-------------|
| `--action` | string | The action that requires approval |
| `--dimensions` | string | Dimensions configured, multiple key-value pairs separated by commas |
| `--entity` | string | The entity that requires approval |
| `--nrn` | string | The resource that will be subject to approvals |
| `--show_descendants` | bool | Show entities from lower NRN hierarchy levels |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np approval action patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | int | The ID of the approval action |

### `np approval action read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the approval action |
| `--include` | string | Include related entities information |

### `np approval action policy create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | int | The ID of the approval action |

### `np approval action policy delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the approval action |
| `--policy_id` | int | The ID of the policy to disassociate |

### `np approval policy create`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |

### `np approval policy delete`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the policy |

### `np approval policy list`

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | The NRN of the resource where the policy applies |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np approval policy patch`

| Flag | Type | Description |
|------|------|-------------|
| `--body` | string | JSON request body. Accepts a stringified JSON object or a file path |
| `--id` | int | The ID of the policy |

### `np approval policy read`

| Flag | Type | Description |
|------|------|-------------|
| `--id` | int | The ID of the policy |
| `--include` | string | Include related entities information |

## Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `approval approve` | Use `POST /approval/approve` via API |
| `approval deny` | Use `POST /approval/deny` via API |
