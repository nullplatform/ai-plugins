#!/bin/bash
#
# create_category.sh - Create an action item category via POST
#
# Usage:
#   create_category.sh --nrn <nrn> --name <name> [optional fields...]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; NAME=""; DESCRIPTION=""; COLOR=""; ICON=""
UNIT_NAME=""; UNIT_SYMBOL=""; PARENT_ID=""; CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
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

call_api POST "$(gov_path "action_item_category")" "$DATA"
