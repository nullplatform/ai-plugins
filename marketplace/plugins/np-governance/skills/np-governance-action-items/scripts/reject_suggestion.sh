#!/bin/bash
#
# reject_suggestion.sh - Transition a suggestion to rejected (terminal)
#
# Usage:
#   reject_suggestion.sh --action-item-id <ai_id> --suggestion-id <s_id>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; S_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --suggestion-id) S_ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"
require_arg suggestion-id "$S_ID"

call_api PATCH "$(gov_path "action_item/${AI_ID}/suggestions/${S_ID}")" '{"status":"rejected"}'
