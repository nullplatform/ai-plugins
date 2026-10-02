#!/bin/bash
#
# migrate_action.sh - Migrate an action from policy mode to checklist mode
#
# Usage:
#   migrate_action.sh --action-id <id> [--dry-run]
#
# Wire contract (migration_controller.js):
#   POST /approval/checklist/migrate_from_policy/preview  {approval_action_id}
#   POST /approval/checklist/migrate_from_policy/apply    {approval_action_id, expected_specification}
#
# What it does:
#   1. Reads the action's existing policies and its on_policy_success.
#   2. Generates a derived checklist specification: one condition item per
#      policy predicate, a manual human_sign_off item when on_policy_success
#      is not `approve` or there are no policies (with no policies it is the
#      only item), and a seeded definition.execution_trigger. No aggregation
#      block: the server derives the expression from the items' behaviors.
#   3. In a single transaction:
#        - soft-deletes the existing action_policy associations
#          (deleted_at = NOW())
#        - creates the new specification
#        - associates the specification with the action
#
# --dry-run calls only the preview endpoint: returns the generated
# specification and the migration plan without applying any changes.
# Strongly recommended before applying.
#
# Without --dry-run the script previews first and sends the generated
# specification back as `expected_specification` — the API's optimistic
# concurrency check that the policies didn't change between preview and
# apply.
#
# The specification's `created_by` is credited to the caller's JWT
# server-side (a --created-by flag is accepted and ignored for backward
# compatibility).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ACTION_ID=""; DRY_RUN="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --action-id) ACTION_ID="$2"; shift 2 ;;
        --created-by) shift 2 ;;  # ignored: created_by comes from the caller's JWT
        --dry-run) DRY_RUN="true"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg action-id "$ACTION_ID"

BODY=$(jq -n --arg id "$ACTION_ID" \
    '{approval_action_id: ($id | if test("^[0-9]+$") then tonumber else . end)}')

PREVIEW="$(call_api POST "$(approval_path "checklist/migrate_from_policy/preview")" "$BODY")"

if [ "$DRY_RUN" = "true" ]; then
    echo "$PREVIEW"
    exit 0
fi

EXPECTED="$(echo "$PREVIEW" | jq -c '.generated_specification // .generated_template // empty')"
if [ -z "$EXPECTED" ]; then
    echo "Error: preview returned no generated specification — nothing to apply. Preview response:" >&2
    echo "$PREVIEW" >&2
    exit 1
fi

DATA=$(echo "$BODY" | jq --argjson expected "$EXPECTED" '. + {expected_specification: $expected}')

call_api POST "$(approval_path "checklist/migrate_from_policy/apply")" "$DATA"
