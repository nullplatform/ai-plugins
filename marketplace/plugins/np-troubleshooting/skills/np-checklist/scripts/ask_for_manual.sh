#!/bin/bash
#
# ask_for_manual.sh - Route a checklist-mode approval to classic manual review
#
# Usage:
#   ask_for_manual.sh --approval-id <id> [--reason <text>]
#
# Wire contract:
#   POST /approval/:id/checklist/ask-for-manual
#   body: { "reason"? }
#
# When it applies (mirrors `canRequestManualReview` server-side — all three
# must hold, each violation returns its own business error):
#   1. The run is still evaluating, OR resolved with final_outcome=fail and
#      not already routed (`outcome_reason != requested_manual_review`) —
#      the "resumable fail".
#   2. The approval request is still `pending`.
#   3. The action's `on_checklist_fail` is not `deny` (`pending` or `manual`).
#
# Effect: the run's outcome_reason becomes `requested_manual_review`, the
# request moves to the CLASSIC manual-review flow (waiting room), and the
# reviewers are notified — this is the FIRST time anyone is pinged on a
# resumable fail. Requester-only: the caller must be the identity that
# created the deployment.
#
# Prefer fix-and-redeploy over this escalation when the failed gates are
# actionable — see np-developer-actions deployments.md paso 10a-CHK.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""; REASON=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"

DATA=$(jq -n \
    --arg reason "$REASON" \
    '{} | if $reason != "" then . + {reason: $reason} else . end')

call_api POST "$(approval_path "${APPROVAL_ID}/checklist/ask-for-manual")" "$DATA"
