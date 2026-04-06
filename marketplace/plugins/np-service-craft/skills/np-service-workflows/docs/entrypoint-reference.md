# Entrypoint Reference

## entrypoint (main router)

```bash
#!/bin/bash
set -euo pipefail

if [ -z "${NP_ACTION_CONTEXT:-}" ]; then
  echo "NP_ACTION_CONTEXT is not set. Exiting."
  exit 1
fi

# Bridge: np-agent uses NP_API_KEY; np CLI uses NULLPLATFORM_API_KEY
if [ -n "${NP_API_KEY:-}" ] && [ -z "${NULLPLATFORM_API_KEY:-}" ]; then
  export NULLPLATFORM_API_KEY="$NP_API_KEY"
fi

CLEAN_CONTEXT=$(echo "$NP_ACTION_CONTEXT" | sed "s/^'//;s/'$//")
export NP_ACTION_CONTEXT="$CLEAN_CONTEXT"

export CONTEXT=$(echo "$CLEAN_CONTEXT" | jq '.notification')
export SERVICE_ACTION=$(echo "$CONTEXT" | jq -r '.slug')
export SERVICE_ACTION_TYPE=$(echo "$CONTEXT" | jq -r '.type')
export NOTIFICATION_ACTION=$(echo "$CONTEXT" | jq -r '.action')
export LINK=$(echo "$CONTEXT" | jq '.link')

ACTION_SOURCE=service
IS_LINK_ACTION=$(echo "$CONTEXT" | jq '.link != null')
if [ "$IS_LINK_ACTION" = "true" ]; then
  ACTION_SOURCE=link
fi

export WORKING_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVICE_PATH=""
OVERRIDES_PATH=""
for arg in "$@"; do
  case $arg in
    --service-path=*) SERVICE_PATH="${arg#*=}" ;;
    --overrides-path=*) OVERRIDES_PATH="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

SERVICE_PATH="${SERVICE_PATH:-$(dirname "$WORKING_DIRECTORY")}"

# Resolve relative to absolute. Agent child inherits CWD from where np-agent started,
# NOT ~/.np/. Try CWD first, then fallback to basepath.
if [[ "$SERVICE_PATH" != /* ]]; then
  if [ -d "$SERVICE_PATH" ]; then
    SERVICE_PATH="$(cd "$SERVICE_PATH" && pwd)"
  elif [ -d "$HOME/.np/$SERVICE_PATH" ]; then
    SERVICE_PATH="$(cd "$HOME/.np/$SERVICE_PATH" && pwd)"
  else
    echo "ERROR: Cannot resolve SERVICE_PATH='$SERVICE_PATH' from CWD=$(pwd) or ~/.np/"
    exit 1
  fi
fi

export SERVICE_PATH
export OVERRIDES_PATH="${OVERRIDES_PATH:-$SERVICE_PATH/overrides}"
export ACTION_SOURCE

np service-action exec --live-output --live-report --script="$WORKING_DIRECTORY/$ACTION_SOURCE"
```

## service handler

```bash
#!/bin/bash
echo "Executing service action=$SERVICE_ACTION type=$SERVICE_ACTION_TYPE"

ACTION_TO_EXECUTE="$SERVICE_ACTION_TYPE"
case "$SERVICE_ACTION_TYPE" in
  "custom") ACTION_TO_EXECUTE="$SERVICE_ACTION" ;;
esac

WORKFLOW_PATH="$SERVICE_PATH/workflows/<provider>/$ACTION_TO_EXECUTE.yaml"
OVERRIDES_WORKFLOW_PATH="$OVERRIDES_PATH/workflows/<provider>/$ACTION_TO_EXECUTE.yaml"
VALUES_PATH="$SERVICE_PATH/values.yaml"

CMD="np service workflow exec --workflow $WORKFLOW_PATH"
[[ -f "$VALUES_PATH" ]] && CMD="$CMD --values $VALUES_PATH"
[[ -f "$OVERRIDES_WORKFLOW_PATH" ]] && CMD="$CMD --overrides $OVERRIDES_WORKFLOW_PATH"

echo "Executing command: $CMD"
eval "$CMD"
```

## link handler

```bash
#!/bin/bash
echo "Executing link action=$SERVICE_ACTION type=$SERVICE_ACTION_TYPE"

ACTION_TO_EXECUTE="$SERVICE_ACTION_TYPE"
case "$SERVICE_ACTION_TYPE" in
  "custom") ACTION_TO_EXECUTE="$SERVICE_ACTION" ;;
  "create") ACTION_TO_EXECUTE="link" ;;
  "delete") ACTION_TO_EXECUTE="unlink" ;;
esac

WORKFLOW_PATH="$SERVICE_PATH/workflows/<provider>/$ACTION_TO_EXECUTE.yaml"
OVERRIDES_WORKFLOW_PATH="$OVERRIDES_PATH/workflows/<provider>/$ACTION_TO_EXECUTE.yaml"
VALUES_PATH="$SERVICE_PATH/values.yaml"

CMD="np service workflow exec --workflow $WORKFLOW_PATH"
[[ -f "$VALUES_PATH" ]] && CMD="$CMD --values $VALUES_PATH"
[[ -f "$OVERRIDES_WORKFLOW_PATH" ]] && CMD="$CMD --overrides $OVERRIDES_WORKFLOW_PATH"

echo "Executing command: $CMD"
eval "$CMD"
```

## do_tofu (generic)

```bash
#!/bin/bash
set -euo pipefail

TOFU_ACTION="${TOFU_ACTION:-apply}"
cd "$OUTPUT_DIR"
cp -r "$TOFU_MODULE_DIR"/* .
tofu init $TOFU_INIT_VARIABLES
tofu $TOFU_ACTION -auto-approve $TOFU_VARIABLES
```

## write_service_outputs

```bash
#!/bin/bash
set -euo pipefail
cd "$OUTPUT_DIR"
SERVICE_ID=$(echo "$CONTEXT" | jq -r '.service.id')

# Read outputs — ADAPT to actual service
FIELD1=$(tofu output -raw field1 2>/dev/null || echo "")
if [ -z "$FIELD1" ]; then
  echo "Warning: No tofu outputs found. Skipping."
  exit 0
fi

ATTRS=$(jq -n --arg f1 "$FIELD1" '{field1: $f1}')
echo "Updating service $SERVICE_ID attributes: $ATTRS"
np service patch --id "$SERVICE_ID" --body "{\"attributes\": $ATTRS}"
```

## write_link_outputs

```bash
#!/bin/bash
set -euo pipefail
cd "$OUTPUT_DIR"
LINK_ID=$(echo "$CONTEXT" | jq -r '.link.id')

ACCESS_KEY_ID=$(tofu output -raw access_key_id 2>/dev/null || echo "")
SECRET_ACCESS_KEY=$(tofu output -raw secret_access_key 2>/dev/null || echo "")
if [ -z "$ACCESS_KEY_ID" ]; then
  echo "Warning: No tofu outputs found. Skipping."
  exit 0
fi

ATTRS=$(jq -n --arg k "$ACCESS_KEY_ID" --arg s "$SECRET_ACCESS_KEY" \
  '{access_key_id: $k, secret_access_key: $s}')
echo "Updating link $LINK_ID attributes"
np link patch --id "$LINK_ID" --body "{\"attributes\": $ATTRS}"
```
