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
#     [--statuses "open,deferred,pending_deferral,pending_verification,pending_rejection"] \
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

# Server-side metadata.<key> filtering DOES work, but only for string values.
# Verified 2026-07-02 against the running API (PostgreSQL): a matching
# metadata.<key>=<string> returns the item, and a non-matching value returns
# nothing, so the filter is genuinely applied (not ignored). Non-string values
# (numbers, booleans) do NOT match via the querystring, because query values
# always arrive as strings and the JSONB containment check is type-sensitive
# (e.g. a stored 5 does not match "5"). Prefer string idempotency keys.
#
# We still re-filter client-side on the exact (key, value) match for two
# reasons: (1) the list endpoint's pagination.total is computed WITHOUT the
# metadata filter, so we recompute .count from the filtered .results; (2) it
# guards against false positives. This client-side check is itself string-based
# (jq: 5 == "5" is false), so it likewise will not match non-string values.
echo "$RAW" | jq --arg key "$KEY" --arg value "$VALUE" '
    .results = ((.results // []) | map(select((.metadata // {})[$key] == $value)))
    | .count = (.results | length)
'
