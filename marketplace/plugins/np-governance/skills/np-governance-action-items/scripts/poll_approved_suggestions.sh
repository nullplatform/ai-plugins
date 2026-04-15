#!/bin/bash
#
# poll_approved_suggestions.sh - One-shot polling loop for executor agents
#
# Same as find_approved_suggestions.sh but optionally also includes failed
# suggestions that have not exceeded the retry limit.
#
# Usage:
#   poll_approved_suggestions.sh \
#     --owner <executor_id> \
#     --nrn <nrn> \
#     [--include-failed] \
#     [--max-retry-attempts 3]
#
# Output: JSON array of {action_item, suggestion}

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

OWNER=""; NRN=""; INCLUDE_FAILED="false"; MAX_RETRY="3"

while [[ $# -gt 0 ]]; do
    case $1 in
        --owner) OWNER="$2"; shift 2 ;;
        --nrn) NRN="$2"; shift 2 ;;
        --include-failed) INCLUDE_FAILED="true"; shift ;;
        --max-retry-attempts) MAX_RETRY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg owner "$OWNER"
require_arg nrn "$NRN"

# 1. Approved suggestions
APPROVED=$("${SCRIPT_DIR}/find_approved_suggestions.sh" --owner "$OWNER" --nrn "$NRN")

if [ "$INCLUDE_FAILED" != "true" ]; then
    echo "$APPROVED"
    exit 0
fi

# 2. Also collect failed suggestions with attempts < MAX_RETRY
RESULT="$APPROVED"
OFFSET=0
LIMIT=100

while true; do
    QS="nrn=$(urlencode "$NRN")&status[]=open&offset=${OFFSET}&limit=${LIMIT}"
    PAGE=$(call_api GET "$(gov_path "action_item")?${QS}")
    PAGE_RESULTS=$(echo "$PAGE" | jq '.results // []')
    PAGE_COUNT=$(echo "$PAGE_RESULTS" | jq 'length')

    if [ "$PAGE_COUNT" = "0" ]; then break; fi

    for AI_ID in $(echo "$PAGE_RESULTS" | jq -r '.[].id'); do
        AI=$(echo "$PAGE_RESULTS" | jq --arg id "$AI_ID" '.[] | select(.id == $id)')
        SUGGESTIONS_QS="status=failed&owner=$(urlencode "$OWNER")&limit=100"
        SUGGESTIONS=$(call_api GET "$(gov_path "action_item/${AI_ID}/suggestions")?${SUGGESTIONS_QS}")
        S_RESULTS=$(echo "$SUGGESTIONS" | jq '.results // .')

        for S_ID in $(echo "$S_RESULTS" | jq -r '.[].id // empty'); do
            S=$(echo "$S_RESULTS" | jq --arg id "$S_ID" '.[] | select(.id == $id)')
            ATTEMPTS=$(echo "$S" | jq -r '.execution_result.details.attempt // 0')
            if [ "$ATTEMPTS" -lt "$MAX_RETRY" ]; then
                ENTRY=$(jq -n --argjson ai "$AI" --argjson s "$S" '{action_item: $ai, suggestion: $s}')
                RESULT=$(echo "$RESULT" | jq --argjson e "$ENTRY" '. + [$e]')
            fi
        done
    done

    if [ "$PAGE_COUNT" -lt "$LIMIT" ]; then break; fi
    OFFSET=$((OFFSET + LIMIT))
done

echo "$RESULT"
