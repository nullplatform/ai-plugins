#!/bin/bash
#
# reopen_action_item.sh - Reopen a deferred or rejected action item
#
# Usage:
#   reopen_action_item.sh --id <id> [--actor <actor>]
#
# --actor is optional — identity is resolved from the token; only honored for
#   callers with delegation rights.

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

DATA=$(jq -n --arg actor "$ACTOR" \
    '{} + (if $actor != "" then {actor: $actor} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/reopen")" "$DATA"
