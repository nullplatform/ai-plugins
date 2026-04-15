#!/bin/bash
#
# delete_category.sh - Delete a category
#
# Usage:
#   delete_category.sh --id <category_id>
#
# Fails if the category has associated action items or has children.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

call_api DELETE "$(gov_path "action_item_category/${ID}")"
