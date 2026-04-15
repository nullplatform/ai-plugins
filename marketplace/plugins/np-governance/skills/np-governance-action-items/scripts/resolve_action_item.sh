#!/bin/bash
#
# resolve_action_item.sh - Mark action item as resolved
#
# Usage:
#   resolve_action_item.sh --id <id> --actor <actor>
#
# If the category has requires_verification=true, this transitions to
# pending_verification instead of resolved.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; ACTOR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg actor "$ACTOR"

DATA=$(jq -n --arg actor "$ACTOR" '{actor: $actor}')
call_api POST "$(gov_path "action_item/${ID}/resolve")" "$DATA"
