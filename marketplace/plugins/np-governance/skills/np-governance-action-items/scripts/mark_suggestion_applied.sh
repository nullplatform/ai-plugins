#!/bin/bash
#
# mark_suggestion_applied.sh - Report a successful execution
#
# Usage:
#   mark_suggestion_applied.sh \
#     --action-item-id <ai_id> --suggestion-id <s_id> \
#     --execution-result <json>
#
# Only valid from the "approved" state. Terminal.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; S_ID=""; EXECUTION_RESULT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --suggestion-id) S_ID="$2"; shift 2 ;;
        --execution-result) EXECUTION_RESULT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"
require_arg suggestion-id "$S_ID"
require_arg execution-result "$EXECUTION_RESULT"

DATA=$(jq -n --argjson er "$EXECUTION_RESULT" '{status: "applied", execution_result: $er}')

call_api PATCH "$(gov_path "action_item/${AI_ID}/suggestions/${S_ID}")" "$DATA"
