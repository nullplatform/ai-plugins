# Build Context Patterns

## yaml_value() Function

Reads simple YAML without requiring `yq`:

```bash
yaml_value() {
  local key="$1" default="$2" file="$3"
  local val
  val=$(grep "^${key}:" "$file" 2>/dev/null | sed 's/^[^:]*: *//;s/^"//;s/"$//' | head -1)
  echo "${val:-$default}"
}
```

## Resource Name Limits

Cloud providers enforce character limits on resource names. **ALL generated names MUST be truncated** to respect these limits:

| Resource | Max chars | Prefix budget | Available for name |
|----------|-----------|---------------|-------------------|
| S3 bucket | 63 | `np-` (3) | 60 |
| RDS instance | 63 | `np-` (3) | 60 |
| IAM User | 64 | `np-` (3) | 61 |
| IAM Policy | 128 | `np-` (3) | 125 |
| IAM Role | 64 | `np-` (3) | 61 |
| ElastiCache | 40 | `np-` (3) | 37 |

## sanitize_name() Function

Reusable function for all resource name construction. Takes raw input and max total length:

```bash
sanitize_name() {
  local input="$1" max_len="${2:-64}" fallback="$3"
  local prefix="np-"
  local available=$((max_len - ${#prefix}))
  local sanitized
  sanitized=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-"$available" | sed 's/^-*//;s/-*$//')
  echo "${prefix}${sanitized:-$fallback}"
}
```

## Instance Name Sanitization

`.service.name` may be empty or contain characters that sanitize to nothing, producing an invalid name like `np-`.

**Always include a fallback to `SERVICE_ID`** so the name is never empty:

```bash
SERVICE_NAME=$(echo "$CONTEXT" | jq -r '.service.name // ""')
INSTANCE_NAME=$(sanitize_name "$SERVICE_NAME" 63 "$SERVICE_ID")
```

If the service has a user-provided name parameter (e.g., `bucket_name_suffix` for S3), prefer that over `SERVICE_NAME` for the resource name. `SERVICE_ATTRS` is the merged attributes+parameters object (see "Merge Attributes with Parameters" below):

```bash
USER_SUFFIX=$(echo "$SERVICE_ATTRS" | jq -r '.bucket_name_suffix // ""')
INSTANCE_NAME=$(sanitize_name "$USER_SUFFIX" 63 "$SERVICE_ID")
```

## Merge Attributes with Parameters

On the first `create` action, `.service.attributes` may be empty. User values come in `.parameters`:

```bash
SERVICE_ATTRS=$(echo "$CONTEXT" | jq -r '(.service.attributes // {}) * (.parameters // {})')
```

The `*` operator in jq merges objects; parameters take precedence.

## Cloud Provider Profile

The values.yaml profile **must always override** whatever is in the environment. The agent inherits all env vars from the shell where it was started (e.g., `AWS_PROFILE`, `AZURE_SUBSCRIPTION_ID`). If the script only sets when the variable is empty, the agent's environment profile wins and may point to an incorrect account.

```bash
# CORRECT: values.yaml always wins over the environment
AWS_PROFILE_VAL=$(yaml_value "aws_profile" "" "$VALUES")
if [ -n "$AWS_PROFILE_VAL" ]; then
  export AWS_PROFILE="$AWS_PROFILE_VAL"
fi
```

Same pattern for other providers:
```bash
# Azure
AZURE_SUB=$(yaml_value "azure_subscription_id" "" "$VALUES")
if [ -n "$AZURE_SUB" ]; then export ARM_SUBSCRIPTION_ID="$AZURE_SUB"; fi

# GCP
GCP_PROJECT=$(yaml_value "gcp_project" "" "$VALUES")
if [ -n "$GCP_PROJECT" ]; then export GOOGLE_PROJECT="$GCP_PROJECT"; fi
```

## Link-Specific Variables

When `ACTION_SOURCE=link`, extract link data:

```bash
export LINK_ID=$(echo "$LINK" | jq -r '.id // ""')
export LINK_NAME=$(echo "$LINK" | jq -r '.name // ""')
export SCOPE_ID=$(echo "$LINK" | jq -r '.scope.id // ""')
export SCOPE_NRN=$(echo "$LINK" | jq -r '.scope.nrn // ""')
export SCOPE_SLUG=$(echo "$LINK" | jq -r '.scope.slug // ""')
export APP_SLUG=$(echo "$LINK" | jq -r '.entity.slug // ""')
export APP_NRN=$(echo "$LINK" | jq -r '.entity.nrn // ""')
export LINK_ACCESS_LEVEL=$(echo "$LINK" | jq -r '.attributes.accessLevel // "read-write"')
```

These fields come pre-populated in the notification payload. **Do NOT call the API** (e.g., `/np-api fetch-api "/scope/$SCOPE_ID"`) to resolve slugs, NRNs, or tags — they are already in `$LINK`.

Link attributes vs parameters: on first link action, `.link.attributes` may be empty. Fallback to `.parameters`:

```bash
if [ "$LINK_ACCESS_LEVEL" = "read-write" ]; then
  LINK_ACCESS_LEVEL=$(echo "$CONTEXT" | jq -r '.parameters.accessLevel // "read-write"')
fi
```

## build_permissions_context

Separate script for link.yaml and link-update.yaml (step 2). Key differences from build_context:

1. **Has its own `yaml_value()`** — NOT inherited from build_context (separate script execution)
2. **Derive ALL names from `$CONTEXT` data** — scope slug, app slug, and tags are in `$LINK`. Do NOT call the API to resolve them:
   ```bash
   SCOPE_SLUG=$(echo "$LINK" | jq -r '.scope.slug // ""')
   APP_SLUG=$(echo "$LINK" | jq -r '.entity.slug // ""')
   APP_NRN=$(echo "$LINK" | jq -r '.entity.nrn // ""')
   ```
   Use these to build deterministic resource names — **always truncate** (see Resource Name Limits):
   ```bash
   # IAM user name (max 64 chars)
   IAM_USER_NAME=$(sanitize_name "${SERVICE_NAME}-${LINK_ID}" 64 "$LINK_ID")
   # IAM policy name (max 128 chars)
   POLICY_NAME=$(sanitize_name "${SERVICE_NAME}-${SCOPE_SLUG}-${APP_SLUG}" 128 "$LINK_ID")
   # ARNs from names (don't read from .service.attributes)
   BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"
   ```
3. **app_role_name fallback chain** (also from `$LINK`, not API):
   ```bash
   APP_ROLE_NAME=$(echo "$LINK" | jq -r '.entity.attributes.role_name // .scope.attributes.role_name // ""')
   if [ -z "$APP_ROLE_NAME" ]; then
     APP_ROLE_NAME=$(yaml_value "app_role_name" "" "$VALUES")
   fi
   ```
4. **State separation per link**:
   ```bash
   export TOFU_INIT_VARIABLES="-backend-config=key=services/s3-${SERVICE_NAME}/links/${LINK_ID}.tfstate"
   ```
5. **Overrides OUTPUT_DIR** to link-specific directory
6. **Sets TOFU_MODULE_DIR** to `$SERVICE_PATH/permissions/`

## Permissions Module Pattern

### IAM User (default for AWS)

Creates a dedicated IAM user per link with access keys exported to the app. Truncate the name via `sanitize_name()` — it only cuts if the name exceeds the limit:

```bash
# In build_permissions_context:
export IAM_USER_NAME=$(sanitize_name "${SERVICE_NAME}-${LINK_ID}" 64 "$LINK_ID")
```

```hcl
resource "aws_iam_user" "link" {
  name = var.iam_user_name
}

resource "aws_iam_access_key" "link" {
  user = aws_iam_user.link.name
}

resource "aws_iam_user_policy_attachment" "access" {
  user       = aws_iam_user.link.name
  policy_arn = aws_iam_policy.access.arn
}
```

### IAM Role (IRSA) — only if scope creates per-app ServiceAccounts

Make `app_role_name` optional — it will be empty if the scope doesn't create dedicated SAs:

```hcl
resource "aws_iam_role_policy_attachment" "access" {
  count      = var.app_role_name != "" ? 1 : 0
  role       = var.app_role_name
  policy_arn = aws_iam_policy.access.arn
}

variable "app_role_name" {
  type    = string
  default = ""
}
```
