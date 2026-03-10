# Miscellaneous Resources

Smaller resources with 1–5 commands each. For resources not listed here, run `np <resource> --help` to discover available subcommands.

---

## action

Create and manage actions.

| Command | Description |
|---------|-------------|
| `np action specification list` | List service specification actions |
| `np action specification read --id <id>` | Read a service specification action |

### `np action specification list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--application_id` | string | Application ID for dynamic properties |
| `--id` | string | Action specification ID |
| `--link_id` | string | Link ID for dynamic properties |
| `--link_specification_id` | string | Link specification ID |
| `--nrn` | string | NRN filter |
| `--service_id` | string | Service ID for dynamic properties |
| `--service_specification_id` | string | Service specification ID |
| `--limit` | string | Max results per page |
| `--offset` | string | Pagination offset |

### `np action specification read` flags

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | Action specification ID |
| `--include` | string | Include related entities information |

---

## agent

Create and manage agents.

| Command | Description |
|---------|-------------|
| `np agent command --body <json>` | Execute a command on a specific agent |
| `np agent list` | List agents within an organization |
| `np agent read --id <id>` | Read a specific agent by ID |

### `np agent list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--account_id` | int | The ID of the account |
| `--organization_id` | int | The ID of the organization |
| `--status` | string | Status of the scope |
| `--tags` | string | Key-value pairs for tag matching |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np agent read` flags

| Flag | Type | Description |
|------|------|-------------|
| `--id` | string | The unique ID of the agent |
| `--include` | string | Include related entities information |

---

## api-key

Create and manage API keys.

| Command | Description |
|---------|-------------|
| `np api-key create --body <json>` | Create a new API key |
| `np api-key delete --id <id>` | Remove an API key by ID |
| `np api-key list` | List all API keys |
| `np api-key patch --id <id> --body <json>` | Update an API key |
| `np api-key read --id <id>` | Read an API key by ID |

### `np api-key list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--owner_id` | int | Filter by owner ID |
| `--limit` | string | Max results per page |
| `--offset` | int | Pagination offset |

---

## authz

Create and manage user permissions.

| Command | Description |
|---------|-------------|
| `np authz grants create --body <json>` | Provide users with access to resources (NRN) |

### Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `authz user-role list` | Use API instead |

---

## entity-hook

Create and manage entity hooks.

| Command | Description |
|---------|-------------|
| `np entity-hook action create --body <json>` | Create an entity hook action |
| `np entity-hook action delete --id <id>` | Delete an entity hook action |
| `np entity-hook action list` | List entity hook actions |
| `np entity-hook action patch --id <id> --body <json>` | Update an entity hook action |
| `np entity-hook action read --id <id>` | Read an entity hook action |

### `np entity-hook action list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--entity` | string | Entity type affected by this hook action |
| `--nrn` | string | Filter actions matching or more specific than NRN |
| `--on` | string | The action type that triggers the hook |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

---

## log

Create and manage log configurations, specifications, and templates.

| Command | Description |
|---------|-------------|
| `np log configuration create --body <json>` | Create or overwrite a log configuration |
| `np log configuration delete --id <id>` | Delete a log configuration |
| `np log configuration list` | List log configurations |
| `np log configuration read --id <id>` | Read a log configuration |
| `np log specification create --body <json>` | Create a log specification |
| `np log specification delete --id <id>` | Delete a log specification |
| `np log specification list` | List log specifications |
| `np log specification patch --id <id> --body <json>` | Update a log specification |
| `np log specification read --id <id>` | Read a log specification |
| `np log template create --body <json>` | Create a template |
| `np log template delete --id <id>` | Delete a template |
| `np log template list` | List all templates |
| `np log template read --id <id>` | Read a template |

### `np log configuration list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--account_id` | int | The ID of the account |
| `--organization_id` | int | The ID of the organization |
| `--selector` | string | JSON key-value pairs for tag matching |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### `np log template list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--account_id` | int | The ID of the account |
| `--organization_id` | int | The ID of the organization |
| `--name` | string | Template name filter |
| `--capability_category` | string | Capability category filter |
| `--capability_provider` | string | Capability provider filter |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

---

## metadata

Create and manage values for metadata catalog.

| Command | Description |
|---------|-------------|
| `np metadata create` | Create new metadata for an entity |
| `np metadata read` | Read entity metadata |

### `np metadata create` flags

| Flag | Type | Description |
|------|------|-------------|
| `--application-id` | int | Application ID |
| `--branch` | string | Branch name |
| `--commit-sha` | string | Commit SHA |
| `--current-build-status` | string | Build status filter |
| `--path` | string | Path for monorepo |
| `--repository` | string | Repository URL |

### `np metadata read` flags

| Flag | Type | Description |
|------|------|-------------|
| `--include` | string | Additional metadata info (e.g., schemas, tags) |

### Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `metadata specification create` | Use API instead |
| `metadata specification delete` | Use API instead |
| `metadata specification list` | Use API instead |
| `metadata specification patch` | Use API instead |
| `metadata specification read` | Use API instead |
| `metadata specification update` | Use API instead |
| `metadata update` | Use `PATCH /metadata/:id` via API |

---

## notification

Create and manage notifications and channels.

| Command | Description |
|---------|-------------|
| `np notification channel create --body <json>` | Create a notification channel |
| `np notification channel delete --id <id>` | Delete a notification channel |
| `np notification channel list` | List notification channels by NRN |
| `np notification channel patch --id <id> --body <json>` | Update a notification channel |
| `np notification channel read --id <id>` | Read a notification channel |

### `np notification channel list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Resource under which the channel was created |
| `--type` | string | Channel type (github, gitlab, http, slack, azure, agent, entity) |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `notification list` | Use `GET /notification` via API |
| `notification read` | Use `GET /notification/:id` via API |
| `notification resend` | Use `POST /notification/resend` via API |

---

## nrn

Create and manage NRN (Nullplatform Resource Name) configurations. Used for runtime configuration values.

| Command | Description |
|---------|-------------|
| `np nrn create --body <json>` | Create or replace an NRN value (overwrites previous) |
| `np nrn delete --nrn <nrn>` | Remove keys within namespaces/profiles |
| `np nrn patch --nrn <nrn> --body <json>` | Update a value within an NRN |
| `np nrn read --nrn <nrn>` | Read an NRN value |
| `np nrn update --nrn <nrn> --body <json>` | Replace an NRN (overwrites previous) |

### `np nrn read` flags

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | The NRN to read |
| `--ids` | string | Comma-separated elements (${namespace}.${key}) |
| `--profile` | string | Comma-separated list of profiles |
| `--array_merge_strategy` | string | JSON array merge strategy (default "merge") |
| `--no-merge` | bool | Skip merging with parent nodes |
| `--output_json_values` | bool | Parse values as JSON objects |
| `--include` | string | Include related entities information |

### `np nrn delete` flags

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | The NRN to delete |
| `--namespaces` | string | Comma-separated list of namespaces to delete |
| `--profiles` | string | Comma-separated list of profiles to delete |
| `--include_parents` | bool | If false, removes namespace only on this node (default false) |

---

## organization

Create and manage organizations.

| Command | Description |
|---------|-------------|
| `np organization read --id <id>` | Read organization details |
| `np organization update --id <id> --body <json>` | Update organization information |

### Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `organization patch` | Use `PATCH /organization/:id` via API |

---

## release

Create and manage releases.

| Command | Description |
|---------|-------------|
| `np release create --body <json>` | Create a new release |
| `np release list` | List releases for an application |
| `np release read --id <id>` | Read release details |
| `np release update --id <id> --body <json>` | Update a release |

### `np release list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--application_id` | string | Filter by application ID (comma-separated, up to 10 values) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

---

## runtime-configuration

Create and manage runtime configurations.

| Command | Description |
|---------|-------------|
| `np runtime-configuration create --body <json>` | Create a runtime configuration |
| `np runtime-configuration delete --id <id>` | Remove a runtime configuration |
| `np runtime-configuration list` | List runtime configurations |
| `np runtime-configuration patch --id <id> --body <json>` | Update a runtime configuration |
| `np runtime-configuration read --id <id>` | Read a runtime configuration |

### `np runtime-configuration list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--nrn` | string | Filter by NRN (at or above specified level) |
| `--limit` | int | Max results per call (max 200) |
| `--offset` | int | Pagination offset (min 0) |

---

## template

Create and manage technology templates (application starters/skeletons).

| Command | Description |
|---------|-------------|
| `np template create --body <json>` | Create a technology template |
| `np template delete --id <id>` | Delete a technology template |
| `np template list` | List all technology templates |
| `np template patch --id <id> --body <json>` | Update a technology template |
| `np template read --id <id>` | Read a technology template |

### `np template list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--target_nrn` | string | Filter by NRN |
| `--limit` | int | Max results per page |
| `--offset` | int | Pagination offset |

---

## token

Create and manage access tokens.

| Command | Description |
|---------|-------------|
| `np token create --body <json>` | Get or renew an access token |

---

## user

Create and manage users.

| Command | Description |
|---------|-------------|
| `np user create --body <json>` | Create a new user |
| `np user list` | List all users in your organization |
| `np user patch --id <id> --body <json>` | Update a user |
| `np user read --id <id>` | Read a user by ID |

### `np user list` flags

| Flag | Type | Description |
|------|------|-------------|
| `--email` | string | Filter by email |
| `--first_name` | string | Filter by first name |
| `--last_name` | string | Filter by last name |
| `--id` | string | Filter by ID (comma-separated) |
| `--organization_id` | string | Filter by organization ID |
| `--status` | string | Filter by status (comma-separated) |
| `--type` | string | Filter by user type |
| `--limit` | int | Max results per call (max 200, default 30) |
| `--offset` | int | Pagination offset (min 0) |

### Unsupported Operations

| Operation | Alternative |
|-----------|-------------|
| `user grant bulk` | Use `POST /user/:id/grant` via API |
| `user grant list` | Use API instead |
| `user grant update` | Use API instead |

---

## version

Display CLI version information.

| Command | Description |
|---------|-------------|
| `np version` | Show CLI version, build date, and git commit |
