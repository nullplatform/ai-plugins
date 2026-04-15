#!/bin/bash
#
# create_suggestion.sh - Create a suggestion under an action item
#
# Usage:
#   create_suggestion.sh \
#     --action-item-id <ai_id> \
#     --created-by <agent_id> \
#     --owner <executor_id> \
#     [--confidence 0.95] \
#     [--description <text>] \
#     [--metadata <json>] \
#     [--user-metadata <json>] \
#     [--user-metadata-config <json>] \
#     [--expires-at <iso8601>]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; CREATED_BY=""; OWNER=""
CONFIDENCE=""; DESCRIPTION=""
METADATA=""; USER_METADATA=""; USER_METADATA_CONFIG=""; EXPIRES_AT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        --confidence) CONFIDENCE="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --metadata) METADATA="$2"; shift 2 ;;
        --user-metadata) USER_METADATA="$2"; shift 2 ;;
        --user-metadata-config) USER_METADATA_CONFIG="$2"; shift 2 ;;
        --expires-at) EXPIRES_AT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"
require_arg created-by "$CREATED_BY"
require_arg owner "$OWNER"

DATA=$(jq -n \
    --arg created_by "$CREATED_BY" \
    --arg owner "$OWNER" \
    --arg confidence "$CONFIDENCE" \
    --arg description "$DESCRIPTION" \
    --argjson metadata "${METADATA:-null}" \
    --argjson user_metadata "${USER_METADATA:-null}" \
    --argjson user_metadata_config "${USER_METADATA_CONFIG:-null}" \
    --arg expires_at "$EXPIRES_AT" \
    '{created_by: $created_by, owner: $owner}
    + (if $confidence != "" then {confidence: ($confidence | tonumber)} else {} end)
    + (if $description != "" then {description: $description} else {} end)
    + (if $metadata != null then {metadata: $metadata} else {} end)
    + (if $user_metadata != null then {user_metadata: $user_metadata} else {} end)
    + (if $user_metadata_config != null then {user_metadata_config: $user_metadata_config} else {} end)
    + (if $expires_at != "" then {expires_at: $expires_at} else {} end)')

call_api POST "$(gov_path "action_item/${AI_ID}/suggestions")" "$DATA"
