#!/bin/bash
#
# run.sh - Start an execution and poll until it completes.
#
# Usage:
#   run.sh <workflow-id> [--alias=live] [--input key=value ...] [--timeout=120]
#
# Spawns the execution via POST /workflows/:id/execute, then polls
# /executions/:id until status is one of completed|failed|canceled or
# the timeout expires. Prints a compact step summary at the end.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

ID="${1:-}"
if [ -z "$ID" ]; then
    echo "Usage: run.sh <workflow-id> [--alias=live] [--input k=v ...] [--timeout=120]" >&2
    exit 2
fi
shift

ALIAS="live"
TIMEOUT=120
INPUTS_JSON='{}'
while [ $# -gt 0 ]; do
    case "$1" in
        --alias=*) ALIAS="${1#--alias=}"; shift ;;
        --alias) ALIAS="$2"; shift 2 ;;
        --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --input)
            kv="$2"
            k="${kv%%=*}"
            v="${kv#*=}"
            INPUTS_JSON=$(echo "$INPUTS_JSON" | jq --arg k "$k" --arg v "$v" '. + {($k): $v}')
            shift 2
            ;;
        --input=*)
            kv="${1#--input=}"
            k="${kv%%=*}"
            v="${kv#*=}"
            INPUTS_JSON=$(echo "$INPUTS_JSON" | jq --arg k "$k" --arg v "$v" '. + {($k): $v}')
            shift
            ;;
        *) echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
done

REQ=$(jq -n --arg a "$ALIAS" --argjson inp "$INPUTS_JSON" '{alias:$a, inputs:$inp}')
echo "POST /workflows/definitions/$ID/execute"
START=$("$API" POST "/definitions/$ID/execute" "$REQ") || {
    echo "Start failed. Response:" >&2
    echo "$START" >&2
    exit 1
}

EID=$(echo "$START" | jq -r '.executionId // .id')
if [ -z "$EID" ] || [ "$EID" = "null" ]; then
    echo "ERROR: server response missing executionId." >&2
    echo "$START" >&2
    exit 1
fi

echo "  executionId=$EID"
echo ""

# Poll
DEADLINE=$(( $(date +%s) + TIMEOUT ))
LAST_STATUS=""
while true; do
    NOW=$(date +%s)
    if [ "$NOW" -gt "$DEADLINE" ]; then
        echo "TIMEOUT after ${TIMEOUT}s. Last status: $LAST_STATUS"
        echo "Inspect with: /np-workflow execution $EID"
        exit 4
    fi
    EXEC=$("$API" GET "/executions/$EID" 2>/dev/null) || {
        sleep 2
        continue
    }
    LAST_STATUS=$(echo "$EXEC" | jq -r '.status // "unknown"')
    case "$LAST_STATUS" in
        completed|failed|canceled|cancelled) break ;;
        *) printf '\r  status=%s' "$LAST_STATUS"; sleep 1 ;;
    esac
done
echo ""
echo "  status=$LAST_STATUS"
echo ""

# Step summary
STATE=$("$API" GET "/executions/$EID/state" 2>/dev/null) || true
echo "Steps:"
echo "$STATE" | jq -r '.steps[]? | "  [\(.status // "—")] \(.id)  items=\((.items // []) | length)"' 2>/dev/null \
  || echo "$EXEC" | jq -r '.steps[]? | "  [\(.status // "—")] \(.id // .stepId)"'

if [ "$LAST_STATUS" != "completed" ]; then
    echo ""
    echo "Failed step error:"
    echo "$STATE" | jq -r '.steps[]? | select(.status=="failed") | "  \(.id): \(.error.message // "(no message)")"' 2>/dev/null
    exit 1
fi
