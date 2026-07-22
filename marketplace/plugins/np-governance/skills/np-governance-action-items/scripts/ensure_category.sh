#!/bin/bash
#
# ensure_category.sh - Idempotent search-or-create for an action item category
#
# Usage:
#   ensure_category.sh \
#     --nrn <nrn> \
#     --name <name> \
#     [--slug <slug>] \
#     [--description <text>] [--color <hex>] [--icon <name>] \
#     [--unit-name <name>] [--unit-symbol <sym>] \
#     [--config <json>] [--parent-id <id>]
#
# Idempotency is keyed on --name, which is the API's real uniqueness key:
# categories are unique by (name, nrn). --slug is optional and NOT used for
# matching — the API generates the slug from the name (a global counter may
# append -N), so the stored slug can differ from any slug you pass. The actual
# slug is returned in the output.
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
require_arg name "$NAME"

# find_by_name — GET the category list filtered by name+nrn and return the
# exact name match (or empty). The list endpoint filters name server-side
# (exact match), but ancestor-NRN visibility can surface categories from parent
# scopes, so we still match exactly client-side before deciding it exists.
find_by_name() {
    local qs body
    qs="nrn=$(urlencode "$NRN")&name=$(urlencode "$NAME")&limit=100"
    body=$(call_api GET "$(gov_path "action_item_category")?${qs}")
    echo "$body" | jq --arg name "$NAME" \
        '(.results // []) | map(select(.name == $name)) | .[0] // empty'
}

# 1. Search by name (the uniqueness key).
MATCH=$(find_by_name)

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
    # Create failed. The most common cause is a lost race or a prior run: the
    # name already exists in this scope (409 DUPLICATE_NAME). The API returns
    # the existing id/slug only inside a human-readable message, so instead of
    # parsing it we re-query by name and recover the existing category — which
    # keeps this script idempotent. Only a genuinely failed create falls through
    # to the error.
    RECOVERED=$(find_by_name)
    if [ -n "$RECOVERED" ] && [ "$RECOVERED" != "null" ]; then
        jq -n --arg id "$(echo "$RECOVERED" | jq -r '.id')" \
              --arg slug "$(echo "$RECOVERED" | jq -r '.slug')" \
            '{id: $id, slug: $slug, was_created: false}'
        exit 0
    fi
    echo "Error: failed to create category. Response:" >&2
    echo "$CREATED" >&2
    exit 1
fi

jq -n --arg id "$CREATED_ID" --arg slug "$CREATED_SLUG" \
    '{id: $id, slug: $slug, was_created: true}'
