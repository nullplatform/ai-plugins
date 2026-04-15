#!/bin/bash
#
# list_categories.sh - List action item categories
#
# Usage:
#   list_categories.sh --nrn <nrn> [--name <name>] [--parent-id <id>]
#                      [--status active|inactive] [--offset 0] [--limit 25]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; NAME=""; PARENT_ID=""; STATUS=""; OFFSET="0"; LIMIT="25"

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --parent-id) PARENT_ID="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --offset) OFFSET="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"

QS="nrn=$(urlencode "$NRN")&offset=${OFFSET}&limit=${LIMIT}"
[ -n "$NAME" ] && QS+="&name=$(urlencode "$NAME")"
[ -n "$PARENT_ID" ] && QS+="&parent_id=$(urlencode "$PARENT_ID")"
[ -n "$STATUS" ] && QS+="&status=$(urlencode "$STATUS")"

call_api GET "$(gov_path "action_item_category")?${QS}"
