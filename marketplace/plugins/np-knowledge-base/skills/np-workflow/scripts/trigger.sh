#!/bin/bash
#
# trigger.sh - Fire the public webhook URL of an active trigger and report the result.
#
# Usage:
#   trigger.sh <workflow-id> [--alias=live] [--trigger=<trigger-id>] [--body='{"k":"v"}'] [--header 'K: V']
#
# Steps:
#   1. GET /triggers?workflowId=ID&status=active
#   2. Pick the trigger matching aliasName=ALIAS (and triggerId if given) with pluginType=webhook
#   3. POST <runtimeMetadata.webhookUrl> with the body
#   4. Print response + remind the user to inspect the resulting execution

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

ID="${1:-}"
if [ -z "$ID" ]; then
    echo "Usage: trigger.sh <workflow-id> [--alias=live] [--trigger=<id>] [--body='{...}']" >&2
    exit 2
fi
shift

ALIAS="live"
TRIGGER_ID=""
BODY='{}'
HEADERS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --alias=*) ALIAS="${1#--alias=}"; shift ;;
        --alias) ALIAS="$2"; shift 2 ;;
        --trigger=*) TRIGGER_ID="${1#--trigger=}"; shift ;;
        --trigger) TRIGGER_ID="$2"; shift 2 ;;
        --body=*) BODY="${1#--body=}"; shift ;;
        --body) BODY="$2"; shift 2 ;;
        --header)
            HEADERS+=(-H "$2")
            shift 2
            ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

TRIGS=$("$API" GET "/triggers?workflowId=$ID&status=active") || {
    echo "ERROR: failed to list triggers." >&2
    exit 1
}

WEBHOOK_URL=$(echo "$TRIGS" | jq -r --arg a "$ALIAS" --arg tid "$TRIGGER_ID" '
    .data[]?
    | select(.aliasName == $a and .pluginType == "webhook")
    | select($tid == "" or .triggerId == $tid)
    | .runtimeMetadata.webhookUrl
' | head -1)

if [ -z "$WEBHOOK_URL" ] || [ "$WEBHOOK_URL" = "null" ]; then
    echo "ERROR: no active webhook trigger found for workflow=$ID alias=$ALIAS${TRIGGER_ID:+ trigger=$TRIGGER_ID}" >&2
    echo ""
    echo "Available triggers:" >&2
    echo "$TRIGS" | jq -r '.data[]? | "  alias=\(.aliasName) type=\(.pluginType) id=\(.triggerId)"' >&2
    exit 1
fi

echo "POST $WEBHOOK_URL"
echo "  body=$BODY"
RESP=$(curl -s -S -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    "${HEADERS[@]}" \
    --data "$BODY" \
    -w '\n__HTTP_STATUS__%{http_code}')

STATUS=$(printf '%s' "$RESP" | awk -F'__HTTP_STATUS__' '{print $2}' | tr -d '[:space:]')
BODY_OUT=$(printf '%s' "$RESP" | awk -F'__HTTP_STATUS__' '{print $1}')
echo ""
echo "  HTTP $STATUS"
if [ -n "$BODY_OUT" ]; then
    echo "$BODY_OUT" | jq . 2>/dev/null || echo "  $BODY_OUT"
fi

echo ""
echo "Inspect the resulting execution:"
echo "  /np-workflow list-executions $ID"
echo "  /np-workflow execution <executionId>"
