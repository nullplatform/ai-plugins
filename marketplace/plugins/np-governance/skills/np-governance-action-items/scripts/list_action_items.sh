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
#   --category-id <id>            Filter by category ID (direct)
#   --category-slug <slug>        Filter by category slug (resolved to an id
#                                 client-side; the list endpoint has no slug
#                                 filter). Ignored if --category-id is given
#   --priority <priority>         Filter by priority (critical|high|medium|low)
#   --created-by <agent_id>       Filter by created_by
#   --title <substring>           Case-insensitive title substring match
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
#   --order-by <field>            score|value|priority|createdAt|dueDate|status|category (default: score)
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
TITLE_CONTAINS=""
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
        --title) TITLE_CONTAINS="$2"; shift 2 ;;
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

# Enforce the --order-by allowlist. These are the only sort fields the list
# endpoint accepts (routes/action_item.js parseSort allowlist). An unrecognized
# value would otherwise be silently ignored server-side and fall back to
# score DESC, so we reject it up front instead of surprising the caller.
case "$ORDER_BY" in
    score|value|priority|createdAt|dueDate|status|category) ;;
    *) echo "Error: --order-by must be one of score|value|priority|createdAt|dueDate|status|category (got '$ORDER_BY')" >&2; exit 1 ;;
esac

# The list endpoint has NO category_slug filter — it only applies category_id
# server-side (verified 2026-07-02 against routes/action_item.js: the list
# handler reads req.query.category_id and ignores category_slug; passing
# ?category_slug= would return the ENTIRE unfiltered list). So when the caller
# gives --category-slug (and not --category-id), resolve the slug to an id
# client-side: GET the categories for the NRN and exact-match the slug — the
# same approach ensure_category.sh uses because ?slug= is ignored too. We then
# query with the resolved category_id and never send category_slug.
if [ -n "$CATEGORY_SLUG" ] && [ -z "$CATEGORY_ID" ]; then
    CAT_QS="nrn=$(urlencode "$NRN")&limit=100"
    CATS=$(call_api GET "$(gov_path "action_item_category")?${CAT_QS}")
    CATEGORY_ID=$(echo "$CATS" | jq -r --arg slug "$CATEGORY_SLUG" \
        '(.results // []) | map(select(.slug == $slug)) | .[0].id // empty')
    if [ -z "$CATEGORY_ID" ]; then
        echo "Error: no category matches slug '$CATEGORY_SLUG' in NRN '$NRN'" >&2
        exit 1
    fi
fi

QS="nrn=$(urlencode "$NRN")&offset=${OFFSET}&limit=${LIMIT}&sort=${ORDER_BY}:${ORDER}"

for st in "${STATUSES[@]}"; do
    QS+="&status[]=$(urlencode "$st")"
done

[ -n "$CATEGORY_ID" ] && QS+="&category_id=$(urlencode "$CATEGORY_ID")"
[ -n "$PRIORITY" ] && QS+="&priority=$(urlencode "$PRIORITY")"
[ -n "$CREATED_BY" ] && QS+="&created_by=$(urlencode "$CREATED_BY")"
[ -n "$TITLE_CONTAINS" ] && QS+="&title:contains=$(urlencode "$TITLE_CONTAINS")"
[ -n "$METADATA_KEY" ] && [ -n "$METADATA_VALUE" ] && QS+="&metadata.${METADATA_KEY}=$(urlencode "$METADATA_VALUE")"
[ -n "$LABEL_KEY" ] && [ -n "$LABEL_VALUE" ] && QS+="&labels.${LABEL_KEY}=$(urlencode "$LABEL_VALUE")"
[ -n "$DUE_BEFORE" ] && QS+="&due_date_before=$(urlencode "$DUE_BEFORE")"
[ -n "$DUE_AFTER" ] && QS+="&due_date_after=$(urlencode "$DUE_AFTER")"
[ -n "$MIN_VALUE" ] && QS+="&min_value=${MIN_VALUE}"
[ -n "$MAX_VALUE" ] && QS+="&max_value=${MAX_VALUE}"

call_api GET "$(gov_path "action_item")?${QS}"
