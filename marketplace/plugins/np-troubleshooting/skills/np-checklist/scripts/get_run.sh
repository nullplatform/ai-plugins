#!/bin/bash
#
# get_run.sh - Fetch full state of a checklist run (by approval_request id)
#
# Usage:
#   get_run.sh --approval-id <approval_request_id>
#
# Returns the full run: aggregate_status, final_outcome, outcome_reason,
# item_states (per-item status + message + details), specification_snapshot,
# context_snapshot, started_at, resolved_at.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"

call_api GET "$(approval_path "${APPROVAL_ID}/checklist")"
