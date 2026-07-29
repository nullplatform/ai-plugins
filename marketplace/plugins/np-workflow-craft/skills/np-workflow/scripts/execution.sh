#!/bin/bash
#
# execution.sh - List recent executions or inspect one.
#
# Usage:
#   execution.sh                          List most recent 20 executions across all workflows
#   execution.sh list <workflow-id>       List most recent executions of a single workflow
#   execution.sh <execution-id>           Show a specific execution (record + state)
#   execution.sh state <execution-id>     Only the live state document

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

CMD="${1:-}"

list_executions() {
    local query="$1"
    local body
    body=$("$API" GET "/executions?$query") || return $?
    local count
    count=$(echo "$body" | jq -r '.data | length')
    echo "Executions: $count"
    echo ""
    printf '%-40s %-12s %-22s %s\n' EXECUTION STATUS STARTED WORKFLOW
    printf '%-40s %-12s %-22s %s\n' --------- ------ ------- --------
    echo "$body" | jq -r '.data[] | [.id, .status, .startedAt, .workflowId] | @tsv' \
      | while IFS=$'\t' read -r id status started wid; do
          printf '%-40s %-12s %-22s %s\n' "$id" "$status" "$started" "$wid"
        done
}

if [ -z "$CMD" ]; then
    list_executions "limit=20"
    exit 0
fi

if [ "$CMD" = "list" ]; then
    WID="${2:-}"
    if [ -z "$WID" ]; then
        list_executions "limit=20"
    else
        list_executions "workflowId=$WID&limit=20"
    fi
    exit 0
fi

if [ "$CMD" = "state" ]; then
    EID="${2:-}"
    if [ -z "$EID" ]; then echo "Usage: execution.sh state <execution-id>" >&2; exit 2; fi
    "$API" GET "/executions/$EID/state" | jq .
    exit 0
fi

# Default: treat $1 as an execution id
EID="$CMD"
REC=$("$API" GET "/executions/$EID") || exit $?
echo "Execution:"
echo "$REC" | jq '{id, workflowId, revision, status, startedAt, completedAt, error}'
echo ""

STATE=$("$API" GET "/executions/$EID/state" 2>/dev/null) || true
if [ -n "$STATE" ]; then
    echo "Steps:"
    echo "$STATE" | jq -r '.steps[]? | "  [\(.status)] \(.id)  items=\((.items // []) | length)"'
    FAILED=$(echo "$STATE" | jq -r '.steps[]? | select(.status=="failed") | "    error in \(.id): \(.error.message // "(no message)")"')
    if [ -n "$FAILED" ]; then
        echo ""
        echo "$FAILED"
    fi
fi

# Pending signals (if any)
PEND=$("$API" GET "/executions/$EID/pending-signals" 2>/dev/null) || true
PEND_LINES=$(echo "$PEND" | jq -r '.data[]? | "  awaiting signal in \(.stepId)  channel=\(.channel // "—")"' 2>/dev/null)
if [ -n "$PEND_LINES" ]; then
    echo ""
    echo "Pending signals:"
    echo "$PEND_LINES"
fi
