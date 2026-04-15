#!/bin/bash
#
# defer_action_item.sh - Defer an action item until a future date
#
# Usage:
#   defer_action_item.sh --id <id> --until <iso8601> --actor <actor> [--reason <text>]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; UNTIL=""; ACTOR=""; REASON=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg until "$UNTIL"
require_arg actor "$ACTOR"

DATA=$(jq -n --arg until "$UNTIL" --arg actor "$ACTOR" --arg reason "$REASON" \
    '{until: $until, actor: $actor} + (if $reason != "" then {reason: $reason} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/defer")" "$DATA"
