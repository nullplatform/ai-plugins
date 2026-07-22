#!/bin/bash
#
# reject_action_item.sh - Reject an action item
#
# Usage:
#   reject_action_item.sh --id <id> --reason <text> [--category <text>]
#
# --reason is required — rejections must be justified.
# Identity (the "actor" on the resulting audit entry) is always resolved from
# the auth token. This endpoint has no body actor channel, so the actor cannot
# be overridden — run under the token whose identity should be recorded.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; REASON=""; CATEGORY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg reason "$REASON"

DATA=$(jq -n --arg reason "$REASON" --arg category "$CATEGORY" \
    '{reason: $reason}
    + (if $category != "" then {category: $category} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/reject")" "$DATA"
