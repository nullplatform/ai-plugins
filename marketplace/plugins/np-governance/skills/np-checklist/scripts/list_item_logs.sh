#!/bin/bash
#
# list_item_logs.sh - Per-item logs for a checklist run
#
# Usage:
#   list_item_logs.sh --approval-id <id> --item-id <item_id> [--level <lvl>] [--limit <n>]
#
# Logs are structured with level (debug|info|warn|error), message, and an
# optional details JSON blob. Useful to diagnose item-specific failures
# (especially `external` items where the executor reports back via callback).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

APPROVAL_ID=""; ITEM_ID=""; LEVEL=""; LIMIT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --approval-id) APPROVAL_ID="$2"; shift 2 ;;
        --item-id) ITEM_ID="$2"; shift 2 ;;
        --level) LEVEL="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg approval-id "$APPROVAL_ID"
require_arg item-id "$ITEM_ID"

QS=""
[ -n "$LEVEL" ] && QS="${QS}&level=$(urlencode "$LEVEL")"
[ -n "$LIMIT" ] && QS="${QS}&limit=${LIMIT}"
QS="${QS:1}"

ENDPOINT="$(approval_path "${APPROVAL_ID}/checklist/items/$(urlencode "$ITEM_ID")/logs")"
[ -n "$QS" ] && ENDPOINT="${ENDPOINT}?${QS}"

call_api GET "$ENDPOINT"
