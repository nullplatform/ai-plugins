#!/bin/bash
#
# list_runs.sh - List approval-requests running in checklist mode
#
# Usage:
#   list_runs.sh [--nrn <nrn>] [--status <status>] [--final-outcome <outcome>] [--limit <n>]
#
# Filters:
#   --nrn             NRN scope.
#   --status          ApprovalRequest.status: pending | approved | denied | cancelled | expired | ...
#   --final-outcome   Run outcome: approve | approve_with_override | fail | cancelled | expired.
#                     (Filters via the enriched response — only applies when status is terminal.)
#   --limit           Page size.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; STATUS=""; OUTCOME=""; LIMIT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --final-outcome) OUTCOME="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

QS="mode=checklist"
[ -n "$NRN" ]     && QS="${QS}&nrn=$(urlencode "$NRN")"
[ -n "$STATUS" ]  && QS="${QS}&status=$(urlencode "$STATUS")"
[ -n "$OUTCOME" ] && QS="${QS}&final_outcome=$(urlencode "$OUTCOME")"
[ -n "$LIMIT" ]   && QS="${QS}&limit=${LIMIT}"

call_api GET "$(approval_path "")?${QS}"
