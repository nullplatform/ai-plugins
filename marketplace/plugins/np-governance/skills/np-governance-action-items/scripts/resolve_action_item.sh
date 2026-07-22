#!/bin/bash
#
# resolve_action_item.sh - Mark action item as resolved
#
# Usage:
#   resolve_action_item.sh --id <id> [--resolution <text>] [--evidence-url <url>] [--category <text>]
#
# Whether resolve requires verification is decided by the platform approval
# policy. When required, the item returns in pending_verification instead of
# resolved and the platform completes the flow.
#
# Identity (the "actor" on the resulting audit entry) is always resolved from
# the auth token. This endpoint has no body actor channel, so the actor cannot
# be overridden — run under the token whose identity should be recorded.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; RESOLUTION=""; EVIDENCE_URL=""; CATEGORY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --evidence-url) EVIDENCE_URL="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

DATA=$(jq -n --arg resolution "$RESOLUTION" --arg evidence_url "$EVIDENCE_URL" --arg category "$CATEGORY" \
    '{}
    + (if $resolution != "" then {resolution: $resolution} else {} end)
    + (if $evidence_url != "" then {evidence_url: $evidence_url} else {} end)
    + (if $category != "" then {category: $category} else {} end)')

call_api POST "$(gov_path "action_item/${ID}/resolve")" "$DATA"
