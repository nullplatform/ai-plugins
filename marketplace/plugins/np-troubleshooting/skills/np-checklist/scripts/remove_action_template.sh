#!/bin/bash
#
# remove_action_template.sh - Dissociate a checklist template from an action
#
# Usage:
#   remove_action_template.sh --action-id <id>
#
# Idempotent: returns the action unchanged if no template was set.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ACTION_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-id) ACTION_ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-id "$ACTION_ID"

call_api DELETE "$(approval_path "action/${ACTION_ID}/checklist_template")"
