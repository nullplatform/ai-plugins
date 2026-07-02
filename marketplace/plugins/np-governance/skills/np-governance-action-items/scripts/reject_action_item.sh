#!/bin/bash
#
# reject_action_item.sh - Reject an action item
#
# Usage:
#   reject_action_item.sh --id <id> --reason <text> [--category <text>] [--actor <actor>]
#
# --reason is required — rejections must be justified.
# --actor is optional — identity is resolved from the token; only honored for
#   callers with delegation rights.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; REASON=""; CATEGORY=""; ACTOR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg reason "$REASON"

DATA=$(jq -n --arg reason "$REASON" --arg category "$CATEGORY" --arg actor "$ACTOR" \
    '{reason: $reason}
    + (if $category != "" then {category: $category} else {} end)
    + (if $actor != "" then {actor: $actor} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/reject")" "$DATA"
