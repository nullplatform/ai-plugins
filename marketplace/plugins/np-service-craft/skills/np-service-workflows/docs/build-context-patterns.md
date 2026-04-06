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

## Merge Attributes with Parameters

On the first `create` action, `.service.attributes` may be empty. User values come in `.parameters`:

```bash
SERVICE_ATTRS=$(echo "$CONTEXT" | jq -r '(.service.attributes // {}) * (.parameters // {})')
```

The `*` operator in jq merges objects; parameters take precedence.

## Cloud Provider Profile

El profile de values.yaml **siempre debe overridear** lo que haya en el entorno. El agente hereda todas las env vars del shell donde se inicio (ej: `AWS_PROFILE`, `AZURE_SUBSCRIPTION_ID`). Si el script solo setea cuando la variable esta vacia, el profile del entorno del agente gana y puede apuntar a un account incorrecto.

```bash
# CORRECTO: values.yaml siempre gana sobre el entorno
AWS_PROFILE_VAL=$(yaml_value "aws_profile" "" "$VALUES")
if [ -n "$AWS_PROFILE_VAL" ]; then
  export AWS_PROFILE="$AWS_PROFILE_VAL"
fi
```

Mismo patron para otros providers:
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
