#!/bin/bash
#
# list_events.sh - Paginated audit trail for a checklist run
#
# Usage:
#   list_events.sh --approval-id <id> [--types <t1,t2,...>] [--limit <n>] [--cursor <c>]
#
# Each event has: id (cevt_xxx), checklist_run_id, sequence_number,
# occurred_at, event_type, actor, payload (JSON).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""; TYPES=""; LIMIT=""; CURSOR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        --types) TYPES="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        --cursor) CURSOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"

QS=""
[ -n "$TYPES" ]  && QS="${QS}&types=$(urlencode "$TYPES")"
[ -n "$LIMIT" ]  && QS="${QS}&limit=${LIMIT}"
[ -n "$CURSOR" ] && QS="${QS}&cursor=$(urlencode "$CURSOR")"
QS="${QS:1}"

ENDPOINT="$(approval_path "${APPROVAL_ID}/checklist/events")"
[ -n "$QS" ] && ENDPOINT="${ENDPOINT}?${QS}"

call_api GET "$ENDPOINT"
