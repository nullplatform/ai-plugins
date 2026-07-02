#!/bin/bash
#
# resolve_action_item.sh - Mark action item as resolved
#
# Usage:
#   resolve_action_item.sh --id <id> [--resolution <text>] [--evidence-url <url>] [--category <text>] [--actor <actor>]
#
# Whether resolve requires verification is decided by the platform approval
# policy. When required, the item returns in pending_verification instead of
# resolved and the platform completes the flow.
#
# --actor is optional — identity is resolved from the token; only honored for
#   callers with delegation rights.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; RESOLUTION=""; EVIDENCE_URL=""; CATEGORY=""; ACTOR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --evidence-url) EVIDENCE_URL="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

DATA=$(jq -n --arg resolution "$RESOLUTION" --arg evidence_url "$EVIDENCE_URL" --arg category "$CATEGORY" --arg actor "$ACTOR" \
    '{}
    + (if $resolution != "" then {resolution: $resolution} else {} end)
    + (if $evidence_url != "" then {evidence_url: $evidence_url} else {} end)
    + (if $category != "" then {category: $category} else {} end)
    + (if $actor != "" then {actor: $actor} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/resolve")" "$DATA"
