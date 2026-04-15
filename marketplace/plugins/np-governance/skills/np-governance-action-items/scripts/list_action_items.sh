#!/bin/bash
#
# list_action_items.sh - List action items with filters
#
# Usage:
#   list_action_items.sh --nrn <nrn> [filters...]
#
# Filters:
#   --nrn <nrn>                   NRN scope (required)
#   --status <status>             Filter by status (open|deferred|resolved|...)
#                                 Can be repeated to filter on multiple statuses
#   --category-id <id>            Filter by category ID
#   --category-slug <slug>        Filter by category slug
#   --priority <priority>         Filter by priority (critical|high|medium|low)
#   --created-by <agent_id>       Filter by created_by
#   --metadata-key <key>          Used together with --metadata-value
#   --metadata-value <value>
#   --label-key <key>             Used together with --label-value
#   --label-value <value>
#   --due-date-before <iso8601>
#   --due-date-after <iso8601>
#   --min-value <num>
#   --max-value <num>
#   --offset <n>                  Pagination offset (default: 0)
#   --limit <n>                   Page size (default: 25)
#   --order-by <field>            score|value|priority|createdAt|dueDate (default: score)
#   --order <ASC|DESC>            (default: DESC)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""
STATUSES=()
CATEGORY_ID=""
CATEGORY_SLUG=""
PRIORITY=""
CREATED_BY=""
METADATA_KEY=""
METADATA_VALUE=""
LABEL_KEY=""
LABEL_VALUE=""
DUE_BEFORE=""
DUE_AFTER=""
MIN_VALUE=""
MAX_VALUE=""
OFFSET="0"
LIMIT="25"
ORDER_BY="score"
ORDER="DESC"

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --status) STATUSES+=("$2"); shift 2 ;;
        --category-id) CATEGORY_ID="$2"; shift 2 ;;
        --category-slug) CATEGORY_SLUG="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --metadata-key) METADATA_KEY="$2"; shift 2 ;;
        --metadata-value) METADATA_VALUE="$2"; shift 2 ;;
        --label-key) LABEL_KEY="$2"; shift 2 ;;
        --label-value) LABEL_VALUE="$2"; shift 2 ;;
        --due-date-before) DUE_BEFORE="$2"; shift 2 ;;
        --due-date-after) DUE_AFTER="$2"; shift 2 ;;
        --min-value) MIN_VALUE="$2"; shift 2 ;;
        --max-value) MAX_VALUE="$2"; shift 2 ;;
        --offset) OFFSET="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        --order-by) ORDER_BY="$2"; shift 2 ;;
        --order) ORDER="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"

QS="nrn=$(urlencode "$NRN")&offset=${OFFSET}&limit=${LIMIT}&order_by=${ORDER_BY}&order=${ORDER}"

for st in "${STATUSES[@]}"; do
    QS+="&status[]=$(urlencode "$st")"
done

[ -n "$CATEGORY_ID" ] && QS+="&category_id=$(urlencode "$CATEGORY_ID")"
[ -n "$CATEGORY_SLUG" ] && QS+="&category_slug=$(urlencode "$CATEGORY_SLUG")"
[ -n "$PRIORITY" ] && QS+="&priority=$(urlencode "$PRIORITY")"
[ -n "$CREATED_BY" ] && QS+="&created_by=$(urlencode "$CREATED_BY")"
[ -n "$METADATA_KEY" ] && [ -n "$METADATA_VALUE" ] && QS+="&metadata.${METADATA_KEY}=$(urlencode "$METADATA_VALUE")"
[ -n "$LABEL_KEY" ] && [ -n "$LABEL_VALUE" ] && QS+="&labels.${LABEL_KEY}=$(urlencode "$LABEL_VALUE")"
[ -n "$DUE_BEFORE" ] && QS+="&due_date_before=$(urlencode "$DUE_BEFORE")"
[ -n "$DUE_AFTER" ] && QS+="&due_date_after=$(urlencode "$DUE_AFTER")"
[ -n "$MIN_VALUE" ] && QS+="&min_value=${MIN_VALUE}"
[ -n "$MAX_VALUE" ] && QS+="&max_value=${MAX_VALUE}"

call_api GET "$(gov_path "action_item")?${QS}"
