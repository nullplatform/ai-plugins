#!/bin/bash
#
# defer_action_item.sh - Defer an action item until a future date
#
# Usage:
#   defer_action_item.sh --id <id> --until <date> [--reason <text>] [--category <text>] [--actor <actor>]
#
# --until accepts a calendar date (YYYY-MM-DD) or an ISO8601 date-time.
# --actor is optional — identity is resolved from the token; only honored for
#   callers with delegation rights.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; UNTIL=""; REASON=""; CATEGORY=""; ACTOR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg until "$UNTIL"

DATA=$(jq -n --arg defer_until "$UNTIL" --arg reason "$REASON" --arg category "$CATEGORY" --arg actor "$ACTOR" \
    '{defer_until: $defer_until}
    + (if $reason != "" then {reason: $reason} else {} end)
    + (if $category != "" then {category: $category} else {} end)
    + (if $actor != "" then {actor: $actor} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/defer")" "$DATA"
