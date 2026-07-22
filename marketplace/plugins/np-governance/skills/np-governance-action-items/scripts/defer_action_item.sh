#!/bin/bash
#
# defer_action_item.sh - Defer an action item until a future date
#
# Usage:
#   defer_action_item.sh --id <id> --until <date> [--reason <text>] [--category <text>]
#
# --until accepts a calendar date (YYYY-MM-DD) or an ISO8601 date-time.
# Identity (the "actor" on the resulting audit entry) is always resolved from
# the auth token. This endpoint has no body actor channel, so the actor cannot
# be overridden — run under the token whose identity should be recorded.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; UNTIL=""; REASON=""; CATEGORY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg until "$UNTIL"

DATA=$(jq -n --arg defer_until "$UNTIL" --arg reason "$REASON" --arg category "$CATEGORY" \
    '{defer_until: $defer_until}
    + (if $reason != "" then {reason: $reason} else {} end)
    + (if $category != "" then {category: $category} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/defer")" "$DATA"
