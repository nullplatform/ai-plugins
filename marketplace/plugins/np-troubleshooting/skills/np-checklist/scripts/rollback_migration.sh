#!/bin/bash
#
# rollback_migration.sh - Revert a policy-to-checklist migration
#
# Usage:
#   rollback_migration.sh --action-id <id> [--force]
#
# Wire contract (migration_controller.js):
#   POST /approval/checklist/migrate_from_policy/rollback  {approval_action_id, force}
#
# Restores the action_policy rows that were soft-deleted by migrate_action.sh
# (sets deleted_at = NULL) and removes the checklist_specification association.
# 409s: NOTHING_TO_ROLLBACK (no migrated specification on the action),
# NOT_AUTO_MIGRATED (the current specification was not created by a
# migration), FINGERPRINT_MISMATCH (specification edited after migration —
# --force overrides, discarding the hand edits).
# The server does NOT check for in-progress checklist runs before rolling
# back: check with list_runs.sh and time the rollback yourself.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ACTION_ID=""; FORCE="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-id) ACTION_ID="$2"; shift 2 ;;
        --force) FORCE="true"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-id "$ACTION_ID"

DATA=$(jq -n --arg id "$ACTION_ID" --argjson force "$FORCE" \
    '{approval_action_id: ($id | if test("^[0-9]+$") then tonumber else . end), force: $force}')

call_api POST "$(approval_path "checklist/migrate_from_policy/rollback")" "$DATA"
