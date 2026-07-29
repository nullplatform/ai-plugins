#!/bin/bash
#
# migrate_action.sh - Migrate an action from policy mode to checklist mode
#
# Usage:
#   migrate_action.sh --action-id <id> --created-by <email> [--dry-run]
#
# What it does:
#   1. Reads the action's existing policies (must have at least one).
#   2. Generates a derived checklist template (one condition item per policy
#      predicate, plus a top-level aggregation expression).
#   3. In a single transaction:
#        - soft-deletes the existing action_policy associations
#          (deleted_at = NOW())
#        - creates the new template
#        - associates the template with the action
#
# --dry-run returns the generated template and the migration plan without
# applying any changes. Strongly recommended before applying.
#
# Idempotent: if the action is already in checklist mode, returns the
# current template association.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ACTION_ID=""; CREATED_BY=""; DRY_RUN="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-id) ACTION_ID="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-id "$ACTION_ID"

if [ "$DRY_RUN" != "true" ]; then
    require_arg created-by "$CREATED_BY"
fi

DATA=$(jq -n \
    --arg created_by "$CREATED_BY" \
    --argjson dry_run "$DRY_RUN" \
    '{dry_run: $dry_run}
     | if $created_by != "" then . + {created_by: $created_by} else . end')

call_api POST "$(approval_path "migration/${ACTION_ID}")" "$DATA"
