#!/bin/bash
#
# set_action_template.sh - Associate a checklist template with an approval action
#
# Usage:
#   set_action_template.sh --action-id <id> --template-id <tmpl_xxx>
#
# Fails with 409 (APPROVAL_ACTION_HAS_POLICIES_XOR) if the action has live
# policies. Use migrate_action.sh instead to switch a policy-action to
# checklist mode in a single transaction.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ACTION_ID=""; TEMPLATE_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-id) ACTION_ID="$2"; shift 2 ;;
        --template-id) TEMPLATE_ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-id "$ACTION_ID"
require_arg template-id "$TEMPLATE_ID"

DATA=$(jq -n --arg t "$TEMPLATE_ID" '{checklist_template_id: $t}')

call_api POST "$(approval_path "action/${ACTION_ID}/checklist_template")" "$DATA"
