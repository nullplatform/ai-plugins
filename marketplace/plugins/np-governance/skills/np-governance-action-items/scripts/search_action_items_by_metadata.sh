#!/bin/bash
#
# search_action_items_by_metadata.sh - Idempotency helper
#
# Searches for action items matching a metadata key/value, by default in
# "live" statuses (open, deferred, pending_*). Use this BEFORE creating an
# action item to avoid duplicates.
#
# Usage:
#   search_action_items_by_metadata.sh \
#     --nrn <nrn> \
#     --metadata-key <key> \
#     --metadata-value <value> \
#     [--statuses "open,deferred,pending_deferral,pending_verification"] \
#     [--include-resolved]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""
KEY=""
VALUE=""
STATUSES_CSV="open,deferred,pending_deferral,pending_verification,pending_rejection"
INCLUDE_RESOLVED="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --metadata-key) KEY="$2"; shift 2 ;;
        --metadata-value) VALUE="$2"; shift 2 ;;
        --statuses) STATUSES_CSV="$2"; shift 2 ;;
        --include-resolved) INCLUDE_RESOLVED="true"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg metadata-key "$KEY"
require_arg metadata-value "$VALUE"

QS="nrn=$(urlencode "$NRN")&metadata.${KEY}=$(urlencode "$VALUE")&limit=100"

if [ "$INCLUDE_RESOLVED" = "true" ]; then
    STATUSES_CSV="${STATUSES_CSV},resolved,rejected,closed"
fi

IFS=',' read -ra STATUSES <<< "$STATUSES_CSV"
for st in "${STATUSES[@]}"; do
    QS+="&status[]=$(urlencode "$st")"
done

RAW=$(call_api GET "$(gov_path "action_item")?${QS}")

# IMPORTANT: The backend is currently known to ignore metadata.<key> query
# filters. Always filter client-side on the exact (key, value) match so
# callers (especially idempotency checks) don't act on false positives.
echo "$RAW" | jq --arg key "$KEY" --arg value "$VALUE" '
    .results = ((.results // []) | map(select((.metadata // {})[$key] == $value)))
    | .count = (.results | length)
'
