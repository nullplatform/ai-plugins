#!/bin/bash
#
# retry_suggestion.sh - Retry a failed suggestion (failed → approved)
#
# Usage:
#   retry_suggestion.sh \
#     --action-item-id <ai_id> --suggestion-id <s_id> \
#     [--user-metadata <json>]
#
# Optionally pass user_metadata to adjust retry parameters (e.g.: retry_attempt counter).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; S_ID=""; USER_METADATA=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --suggestion-id) S_ID="$2"; shift 2 ;;
        --user-metadata) USER_METADATA="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"
require_arg suggestion-id "$S_ID"

DATA=$(jq -n --argjson um "${USER_METADATA:-null}" \
    '{status: "approved"} + (if $um != null then {user_metadata: $um} else {} end)')

call_api PATCH "$(gov_path "action_item/${AI_ID}/suggestions/${S_ID}")" "$DATA"
