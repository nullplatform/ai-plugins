#!/bin/bash
#
# find_approved_suggestions.sh - Find all approved suggestions for a given owner
#
# Iterates over open action items in a NRN and collects suggestions in
# "approved" state belonging to the specified owner.
#
# Usage:
#   find_approved_suggestions.sh --owner <executor_id> --nrn <nrn> [--limit-action-items 100]
#
# Output: JSON array of {action_item, suggestion}

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

OWNER=""; NRN=""; AI_LIMIT="100"

while [[ $# -gt 0 ]]; do
    case $1 in
        --owner) OWNER="$2"; shift 2 ;;
        --nrn) NRN="$2"; shift 2 ;;
        --limit-action-items) AI_LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg owner "$OWNER"
require_arg nrn "$NRN"

# 1. List open action items (paginated)
OFFSET=0
RESULT="[]"

while true; do
    QS="nrn=$(urlencode "$NRN")&status[]=open&offset=${OFFSET}&limit=${AI_LIMIT}"
    PAGE=$(call_api GET "$(gov_path "action_item")?${QS}")

    PAGE_RESULTS=$(echo "$PAGE" | jq '.results // []')
    PAGE_COUNT=$(echo "$PAGE_RESULTS" | jq 'length')

    if [ "$PAGE_COUNT" = "0" ]; then
        break
    fi

    # 2. For each AI, fetch approved suggestions for this owner
    for AI_ID in $(echo "$PAGE_RESULTS" | jq -r '.[].id'); do
        AI=$(echo "$PAGE_RESULTS" | jq --arg id "$AI_ID" '.[] | select(.id == $id)')
        SUGGESTIONS_QS="status=approved&owner=$(urlencode "$OWNER")&limit=100"
        SUGGESTIONS=$(call_api GET "$(gov_path "action_item/${AI_ID}/suggestions")?${SUGGESTIONS_QS}")

        S_RESULTS=$(echo "$SUGGESTIONS" | jq '.results // .')
        for S_ID in $(echo "$S_RESULTS" | jq -r '.[].id // empty'); do
            S=$(echo "$S_RESULTS" | jq --arg id "$S_ID" '.[] | select(.id == $id)')
            ENTRY=$(jq -n --argjson ai "$AI" --argjson s "$S" '{action_item: $ai, suggestion: $s}')
            RESULT=$(echo "$RESULT" | jq --argjson e "$ENTRY" '. + [$e]')
        done
    done

    if [ "$PAGE_COUNT" -lt "$AI_LIMIT" ]; then
        break
    fi
    OFFSET=$((OFFSET + AI_LIMIT))
done

echo "$RESULT"
