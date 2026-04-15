#!/bin/bash
#
# create_action_item.sh - Create a new action item via POST
#
# Usage:
#   create_action_item.sh \
#     --nrn <nrn> \
#     --title <title> \
#     --created-by <agent_id> \
#     (--category-id <id> | --category-slug <slug>) \
#     [--description <text>] \
#     [--priority critical|high|medium|low] \
#     [--value <num>] \
#     [--due-date <iso8601>] \
#     [--metadata <json>] \
#     [--labels <json>] \
#     [--affected-resources <json>] \
#     [--references <json>] \
#     [--config <json>]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; TITLE=""; CREATED_BY=""
CATEGORY_ID=""; CATEGORY_SLUG=""
DESCRIPTION=""; PRIORITY=""; VALUE=""; DUE_DATE=""
METADATA=""; LABELS=""; AFFECTED_RESOURCES=""; REFERENCES=""; CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --category-id) CATEGORY_ID="$2"; shift 2 ;;
        --category-slug) CATEGORY_SLUG="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --value) VALUE="$2"; shift 2 ;;
        --due-date) DUE_DATE="$2"; shift 2 ;;
        --metadata) METADATA="$2"; shift 2 ;;
        --labels) LABELS="$2"; shift 2 ;;
        --affected-resources) AFFECTED_RESOURCES="$2"; shift 2 ;;
        --references) REFERENCES="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg title "$TITLE"
require_arg created-by "$CREATED_BY"

if [ -z "$CATEGORY_ID" ] && [ -z "$CATEGORY_SLUG" ]; then
    echo "Error: --category-id or --category-slug is required" >&2
    exit 1
fi

# Build JSON payload using jq (safer than string concat)
DATA=$(jq -n \
    --arg nrn "$NRN" \
    --arg title "$TITLE" \
    --arg created_by "$CREATED_BY" \
    --arg category_id "$CATEGORY_ID" \
    --arg category_slug "$CATEGORY_SLUG" \
    --arg description "$DESCRIPTION" \
    --arg priority "$PRIORITY" \
    --arg value "$VALUE" \
    --arg due_date "$DUE_DATE" \
    --argjson metadata "${METADATA:-null}" \
    --argjson labels "${LABELS:-null}" \
    --argjson affected_resources "${AFFECTED_RESOURCES:-null}" \
    --argjson references "${REFERENCES:-null}" \
    --argjson config "${CONFIG:-null}" \
    '{
        nrn: $nrn,
        title: $title,
        created_by: $created_by
    }
    + (if $category_id != "" then {category_id: $category_id} else {} end)
    + (if $category_slug != "" then {category_slug: $category_slug} else {} end)
    + (if $description != "" then {description: $description} else {} end)
    + (if $priority != "" then {priority: $priority} else {} end)
    + (if $value != "" then {value: ($value | tonumber)} else {} end)
    + (if $due_date != "" then {due_date: $due_date} else {} end)
    + (if $metadata != null then {metadata: $metadata} else {} end)
    + (if $labels != null then {labels: $labels} else {} end)
    + (if $affected_resources != null then {affected_resources: $affected_resources} else {} end)
    + (if $references != null then {references: $references} else {} end)
    + (if $config != null then {config: $config} else {} end)')

call_api POST "$(gov_path "action_item")" "$DATA"
