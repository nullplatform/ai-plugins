#!/bin/bash
#
# update_category.sh - PATCH a category
#
# Usage:
#   update_category.sh --id <id> [field flags...]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; NAME=""; DESCRIPTION=""; COLOR=""; ICON=""
UNIT_NAME=""; UNIT_SYMBOL=""; CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --color) COLOR="$2"; shift 2 ;;
        --icon) ICON="$2"; shift 2 ;;
        --unit-name) UNIT_NAME="$2"; shift 2 ;;
        --unit-symbol) UNIT_SYMBOL="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

DATA=$(jq -n \
    --arg name "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg color "$COLOR" \
    --arg icon "$ICON" \
    --arg unit_name "$UNIT_NAME" \
    --arg unit_symbol "$UNIT_SYMBOL" \
    --argjson config "${CONFIG:-null}" \
    '{}
    + (if $name != "" then {name: $name} else {} end)
    + (if $description != "" then {description: $description} else {} end)
    + (if $color != "" then {color: $color} else {} end)
    + (if $icon != "" then {icon: $icon} else {} end)
    + (if $unit_name != "" then {unit_name: $unit_name} else {} end)
    + (if $unit_symbol != "" then {unit_symbol: $unit_symbol} else {} end)
    + (if $config != null then {config: $config} else {} end)')

if [ "$DATA" = "{}" ]; then
    echo "Error: at least one field to update is required" >&2
    exit 1
fi

call_api PATCH "$(gov_path "action_item_category/${ID}")" "$DATA"
