#!/bin/bash
#
# rollback_migration.sh - Revert a policy-to-checklist migration
#
# Usage:
#   rollback_migration.sh --action-id <id>
#
# Restores the action_policy rows that were soft-deleted by migrate_action.sh
# (sets deleted_at = NULL) and removes the checklist_template association.
# Fails if the action was never migrated or if any checklist runs are
# still in progress on the action (server returns 409).

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

call_api POST "$(approval_path "migration/${ACTION_ID}/rollback")"
