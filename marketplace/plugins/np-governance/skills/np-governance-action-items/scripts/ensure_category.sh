#!/bin/bash
#
# ensure_category.sh - Idempotent search-or-create for an action item category
#
# Usage:
#   ensure_category.sh \
#     --nrn <nrn> \
#     --slug <slug> \
#     --name <name> \
#     [--description <text>] [--color <hex>] [--icon <name>] \
#     [--unit-name <name>] [--unit-symbol <sym>] \
#     [--config <json>] [--parent-id <id>]
#
# Output: JSON {id, slug, was_created}

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; SLUG=""; NAME=""; DESCRIPTION=""; COLOR=""; ICON=""
UNIT_NAME=""; UNIT_SYMBOL=""; PARENT_ID=""; CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --slug) SLUG="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --color) COLOR="$2"; shift 2 ;;
        --icon) ICON="$2"; shift 2 ;;
        --unit-name) UNIT_NAME="$2"; shift 2 ;;
        --unit-symbol) UNIT_SYMBOL="$2"; shift 2 ;;
        --parent-id) PARENT_ID="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg slug "$SLUG"
require_arg name "$NAME"

# 1. Search by slug + nrn.
#
# IMPORTANT: The backend is currently known to ignore the ?slug= query
# parameter and return all categories for the NRN (filed as a bug). We always
# do a client-side match on the exact slug before deciding a category exists.
# Without this, a backend that returns an unrelated category would make the
# script either resolve to the wrong id or create a duplicate.
QS="nrn=$(urlencode "$NRN")&slug=$(urlencode "$SLUG")&limit=100"
EXISTING=$(call_api GET "$(gov_path "action_item_category")?${QS}")

MATCH=$(echo "$EXISTING" | jq --arg slug "$SLUG" \
    '(.results // []) | map(select(.slug == $slug)) | .[0] // empty')

if [ -n "$MATCH" ] && [ "$MATCH" != "null" ]; then
    EXISTING_ID=$(echo "$MATCH" | jq -r '.id')
    EXISTING_SLUG=$(echo "$MATCH" | jq -r '.slug')
    jq -n --arg id "$EXISTING_ID" --arg slug "$EXISTING_SLUG" \
        '{id: $id, slug: $slug, was_created: false}'
    exit 0
fi

# 2. Not found → create
DATA=$(jq -n \
    --arg nrn "$NRN" \
    --arg name "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg color "$COLOR" \
    --arg icon "$ICON" \
    --arg unit_name "$UNIT_NAME" \
    --arg unit_symbol "$UNIT_SYMBOL" \
    --arg parent_id "$PARENT_ID" \
    --argjson config "${CONFIG:-null}" \
    '{nrn: $nrn, name: $name}
    + (if $description != "" then {description: $description} else {} end)
    + (if $color != "" then {color: $color} else {} end)
    + (if $icon != "" then {icon: $icon} else {} end)
    + (if $unit_name != "" then {unit_name: $unit_name} else {} end)
    + (if $unit_symbol != "" then {unit_symbol: $unit_symbol} else {} end)
    + (if $parent_id != "" then {parent_id: $parent_id} else {} end)
    + (if $config != null then {config: $config} else {} end)')

CREATED=$(call_api POST "$(gov_path "action_item_category")" "$DATA")

CREATED_ID=$(echo "$CREATED" | jq -r '.id // empty')
CREATED_SLUG=$(echo "$CREATED" | jq -r '.slug // empty')

if [ -z "$CREATED_ID" ]; then
    echo "Error: failed to create category. Response:" >&2
    echo "$CREATED" >&2
    exit 1
fi

jq -n --arg id "$CREATED_ID" --arg slug "$CREATED_SLUG" \
    '{id: $id, slug: $slug, was_created: true}'
