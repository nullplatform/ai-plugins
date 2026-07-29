#!/bin/bash
#
# list_templates.sh - List checklist templates with optional filters
#
# Usage:
#   list_templates.sh [--nrn <nrn>] [--status <status>] [--name <name>] [--limit <n>]
#
# Filters:
#   --nrn      NRN scope (e.g. "organization=1::account=2"). Supports wildcards per gateway.
#   --status   active | inactive | deleted (default: server default).
#   --name     Exact name match.
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

QS=""
[ -n "$NRN" ]    && QS="${QS}&nrn=$(urlencode "$NRN")"
[ -n "$STATUS" ] && QS="${QS}&status=$(urlencode "$STATUS")"
[ -n "$NAME" ]   && QS="${QS}&name=$(urlencode "$NAME")"
[ -n "$LIMIT" ]  && QS="${QS}&limit=${LIMIT}"
QS="${QS:1}"  # strip leading &

ENDPOINT="$(approval_path "checklist/template")"
[ -n "$QS" ] && ENDPOINT="${ENDPOINT}?${QS}"

call_api GET "$ENDPOINT"
