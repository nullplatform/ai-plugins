#!/bin/bash
#
# list_specifications.sh - List checklist specifications with optional filters
#
# Usage:
#   list_specifications.sh --nrn <nrn> [--status <status>] [--name <substring>] [--limit <n>]
#
# Filters:
#   --nrn      REQUIRED. NRN scope (e.g. "organization=1::account=2"). The API
#              rejects the list call without it (400 — with a misleading
#              "specification ID is not valid" message).
#   --status   active | inactive | deleted (default: server default).
#   --name     Substring match (sent as the name:contains query param; the
#              API has no exact-name filter).
#   --limit    Page size (default: server default, typically 50).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; STATUS=""; NAME=""; LIMIT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"

QS=""
[ -n "$NRN" ]    && QS="${QS}&nrn=$(urlencode "$NRN")"
[ -n "$STATUS" ] && QS="${QS}&status=$(urlencode "$STATUS")"
[ -n "$NAME" ]   && QS="${QS}&name:contains=$(urlencode "$NAME")"
[ -n "$LIMIT" ]  && QS="${QS}&limit=${LIMIT}"
QS="${QS:1}"  # strip leading &

ENDPOINT="$(approval_path "checklist/specification")"
[ -n "$QS" ] && ENDPOINT="${ENDPOINT}?${QS}"

call_api GET "$ENDPOINT"
