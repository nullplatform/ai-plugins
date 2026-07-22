#!/bin/bash
#
# reopen_action_item.sh - Reopen a deferred or rejected action item
#
# Usage:
#   reopen_action_item.sh --id <id>
#
# Identity (the "actor" on the resulting audit entry) is always resolved from
# the auth token. This endpoint has no body actor channel, so the actor cannot
# be overridden — run under the token whose identity should be recorded.

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

DATA='{}'

call_api POST "$(gov_path "action_item/${ID}/reopen")" "$DATA"
