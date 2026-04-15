#!/bin/bash
#
# update_suggestion.sh - PATCH a suggestion (any field)
#
# Usage:
#   update_suggestion.sh --action-item-id <ai_id> --suggestion-id <s_id> [field flags...]
#
# Field flags:
#   --description <text>
#   --confidence <num>
#   --metadata <json>
#   --user-metadata <json>
#   --user-metadata-config <json>
#   --status <status>
#   --execution-result <json>
#   --expires-at <iso8601>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; S_ID=""
DESCRIPTION=""; CONFIDENCE=""; STATUS=""; EXPIRES_AT=""
METADATA=""; USER_METADATA=""; USER_METADATA_CONFIG=""; EXECUTION_RESULT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --suggestion-id) S_ID="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --confidence) CONFIDENCE="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --metadata) METADATA="$2"; shift 2 ;;
        --user-metadata) USER_METADATA="$2"; shift 2 ;;
        --user-metadata-config) USER_METADATA_CONFIG="$2"; shift 2 ;;
        --execution-result) EXECUTION_RESULT="$2"; shift 2 ;;
        --expires-at) EXPIRES_AT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"
require_arg suggestion-id "$S_ID"

DATA=$(jq -n \
    --arg description "$DESCRIPTION" \
    --arg confidence "$CONFIDENCE" \
    --arg status "$STATUS" \
    --arg expires_at "$EXPIRES_AT" \
    --argjson metadata "${METADATA:-null}" \
    --argjson user_metadata "${USER_METADATA:-null}" \
    --argjson user_metadata_config "${USER_METADATA_CONFIG:-null}" \
    --argjson execution_result "${EXECUTION_RESULT:-null}" \
    '{}
    + (if $description != "" then {description: $description} else {} end)
    + (if $confidence != "" then {confidence: ($confidence | tonumber)} else {} end)
    + (if $status != "" then {status: $status} else {} end)
    + (if $expires_at != "" then {expires_at: $expires_at} else {} end)
    + (if $metadata != null then {metadata: $metadata} else {} end)
    + (if $user_metadata != null then {user_metadata: $user_metadata} else {} end)
    + (if $user_metadata_config != null then {user_metadata_config: $user_metadata_config} else {} end)
    + (if $execution_result != null then {execution_result: $execution_result} else {} end)')

if [ "$DATA" = "{}" ]; then
    echo "Error: at least one field to update is required" >&2
    exit 1
fi

call_api PATCH "$(gov_path "action_item/${AI_ID}/suggestions/${S_ID}")" "$DATA"
