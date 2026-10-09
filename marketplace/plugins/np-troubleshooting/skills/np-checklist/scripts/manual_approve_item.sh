#!/bin/bash
#
# manual_approve_item.sh - Approve or reject a manual checklist item
#                         (or apply an override item)
#
# Usage:
#   manual_approve_item.sh --approval-id <id> --item-id <item_id> \
#                          --decision <approve|reject> \
#                          [--message <text>] \
#                          [--inputs <json>] \
#                          [--reason <text>]
#
# Wire contract (the real one — there is NO .../approve endpoint):
#   PATCH /approval/:id/checklist/items/:itemId
#   body: { "status": "passed" | "failed", "message"?, "inputs"?, "reason"? }
# `approve` maps to status=passed, `reject` to status=failed. The actor is
# derived server-side from the caller's JWT — it is NOT part of the body.
#
# --reason is why the person answers as they do (e.g. when correcting an
# earlier answer): up to 4 KB in UTF-8, sent only when given. It goes to the
# answer's `item.answer_recorded` event, never to the item state or message.
#
# The item's declared `behavior` (in the snapshotted specification) determines
# the semantics:
#   - behavior=gate       → approve allows the run to clear that gate
#   - behavior=override   → approve resolves as approve_with_override
#                           (only relevant if every gate item failed)
#   - behavior=informational → still recorded but does not affect outcome
# Server validates that the item is type=manual or behavior=override.
#
# If the item declares `inputs` (JSON Schema), pass the values with
# --inputs '{"field": "value", ...}'. Validations (four-eyes etc.) run
# ONLY on approve; a reject always applies.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""; ITEM_ID=""; DECISION=""; MESSAGE=""; INPUTS=""; REASON=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        --item-id) ITEM_ID="$2"; shift 2 ;;
        --decision) DECISION="$2"; shift 2 ;;
        # --actor kept for backward compatibility; the server attributes the
        # decision to the authenticated caller, so the value is ignored.
        --actor) shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        --inputs) INPUTS="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"
require_arg item-id "$ITEM_ID"
require_arg decision "$DECISION"

if [ "$DECISION" != "approve" ] && [ "$DECISION" != "reject" ]; then
    echo "Error: --decision must be 'approve' or 'reject'" >&2
    exit 1
fi

STATUS="passed"
if [ "$DECISION" = "reject" ]; then
    STATUS="failed"
fi

DATA=$(jq -n \
    --arg status "$STATUS" \
    --arg message "$MESSAGE" \
    --argjson inputs "${INPUTS:-null}" \
    --arg reason "$REASON" \
    '{status: $status}
     | if $message != "" then . + {message: $message} else . end
     | if $inputs != null then . + {inputs: $inputs} else . end
     | if $reason != "" then . + {reason: $reason} else . end')

call_api PATCH "$(approval_path "${APPROVAL_ID}/checklist/items/$(urlencode "$ITEM_ID")")" "$DATA"
