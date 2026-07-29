#!/bin/bash
#
# manual_approve_item.sh - Approve or reject a manual checklist item
#                         (or apply an override item)
#
# Usage:
#   manual_approve_item.sh --approval-id <id> --item-id <item_id> \
#                          --decision <approve|reject> \
#                          --actor <email|agent_id> \
#                          [--message <text>]
#
# The item's declared `behavior` (in the snapshotted template) determines
# the semantics:
#   - behavior=gate       → approve allows the run to clear that gate
#   - behavior=override   → approve resolves as approve_with_override
#                           (only relevant if every gate item failed)
#   - behavior=informational → still recorded but does not affect outcome
# Server validates that the item is type=manual or behavior=override.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""; ITEM_ID=""; DECISION=""; ACTOR=""; MESSAGE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        --item-id) ITEM_ID="$2"; shift 2 ;;
        --decision) DECISION="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"
require_arg item-id "$ITEM_ID"
require_arg decision "$DECISION"
require_arg actor "$ACTOR"

if [ "$DECISION" != "approve" ] && [ "$DECISION" != "reject" ]; then
    echo "Error: --decision must be 'approve' or 'reject'" >&2
    exit 1
fi

DATA=$(jq -n \
    --arg decision "$DECISION" \
    --arg actor "$ACTOR" \
    --arg message "$MESSAGE" \
    '{decision: $decision, actor: $actor}
     | if $message != "" then . + {message: $message} else . end')

call_api POST "$(approval_path "${APPROVAL_ID}/checklist/items/$(urlencode "$ITEM_ID")/approve")" "$DATA"
