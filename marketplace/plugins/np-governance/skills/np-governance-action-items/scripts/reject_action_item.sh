#!/bin/bash
#
# reject_action_item.sh - Reject an action item
#
# Usage:
#   reject_action_item.sh --id <id> --actor <actor> [--reason <text>]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; ACTOR=""; REASON=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg actor "$ACTOR"

DATA=$(jq -n --arg actor "$ACTOR" --arg reason "$REASON" \
    '{actor: $actor} + (if $reason != "" then {reason: $reason} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/reject")" "$DATA"
