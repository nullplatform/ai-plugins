#!/bin/bash
#
# list_audit_logs.sh - List audit log entries of an action item
#
# Usage:
#   list_audit_logs.sh --id <action_item_id>

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

call_api GET "$(gov_path "action_item/${ID}/audit-logs")"
