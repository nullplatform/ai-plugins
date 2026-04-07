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

## Instance Name Sanitization

Many AWS resource names (S3 buckets, RDS instances, ElastiCache clusters) require lowercase alphanumeric characters with hyphens. `.service.name` may be empty or contain characters that sanitize to nothing, producing an invalid name like `np-`.

**Always include a fallback to `SERVICE_ID`** so the name is never empty:

```bash
SERVICE_NAME=$(echo "$CONTEXT" | jq -r '.service.name // ""')
# Truncate to 55 chars; with "np-" prefix, total <= 58. Respects S3 (63) and RDS (63) limits.
# For services with shorter limits (e.g., ElastiCache 40), adjust cut length accordingly.
SANITIZED=$(echo "$SERVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-55 | sed 's/^-*//;s/-*$//')
INSTANCE_NAME="np-${SANITIZED:-$SERVICE_ID}"
```

If the service has a user-provided name parameter (e.g., `bucket_name_suffix` for S3), prefer that over `SERVICE_NAME` for the resource name. `SERVICE_ATTRS` is the merged attributes+parameters object (see "Merge Attributes with Parameters" below):

```bash
USER_SUFFIX=$(echo "$SERVICE_ATTRS" | jq -r '.bucket_name_suffix // ""')
SANITIZED=$(echo "$USER_SUFFIX" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-55 | sed 's/^-*//;s/-*$//')
INSTANCE_NAME="np-${SANITIZED:-$SERVICE_ID}"
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
export LINK_ACCESS_LEVEL=$(echo "$LINK" | jq -r '.attributes.accessLevel // "read-write"')
```

Link attributes vs parameters: on first link action, `.link.attributes` may be empty. Fallback to `.parameters`:

```bash
if [ "$LINK_ACCESS_LEVEL" = "read-write" ]; then
  LINK_ACCESS_LEVEL=$(echo "$CONTEXT" | jq -r '.parameters.accessLevel // "read-write"')
fi
```

## build_permissions_context

Separate script for link.yaml (step 2). Key differences from build_context:

1. **Has its own `yaml_value()`** — NOT inherited from build_context (separate script execution)
2. **Derives ARNs from names** — don't read ARNs from `.service.attributes`:
   ```bash
   BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"  # Deterministic
   ```
3. **app_role_name fallback chain**:
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

Make `app_role_name` optional for local testing (no deployed app with IAM role):

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
