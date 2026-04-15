#!/bin/bash
#
# list_suggestions.sh - List suggestions of an action item
#
# Usage:
#   list_suggestions.sh --action-item-id <id> [filters...]
#
# Filters:
#   --status <pending|approved|applied|failed|rejected|expired>
#   --owner <executor_id>
#   --created-by <agent_id>
#   --offset <n>     (default: 0)
#   --limit <n>      (default: 25)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

AI_ID=""; STATUS=""; OWNER=""; CREATED_BY=""; OFFSET="0"; LIMIT="25"

while [[ $# -gt 0 ]]; do
    case $1 in
        --action-item-id) AI_ID="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --offset) OFFSET="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-item-id "$AI_ID"

QS="offset=${OFFSET}&limit=${LIMIT}"
[ -n "$STATUS" ] && QS+="&status=$(urlencode "$STATUS")"
[ -n "$OWNER" ] && QS+="&owner=$(urlencode "$OWNER")"
[ -n "$CREATED_BY" ] && QS+="&created_by=$(urlencode "$CREATED_BY")"

call_api GET "$(gov_path "action_item/${AI_ID}/suggestions")?${QS}"
