#!/bin/bash
#
# dry_run_specification.sh - Pre-evaluate a checklist against a context (no run created)
#
# Usage:
#   dry_run_specification.sh --nrn <nrn> --action <entity:action> --context-file <path> \
#                            [--entity <entity>] [--entity-id <id>] \
#                            [--approval-mode auto|policy|checklist]
#
# Hits POST /approval/dry-run (the same pre-evaluation the deploy form uses).
# There is no by-id dry-run endpoint: the approval action is resolved from
# (--nrn, --action) and its associated checklist specification is evaluated
# against the supplied context. To preview a specification, associate it with
# an action first (set_action_specification.sh), then dry-run that action.
#
# Supplying --context-file makes the server skip buildContext (no upstream
# lookups) — the preview is deterministic against exactly the JSON you pass.
#
# --approval-mode defaults to `checklist`, which errors clearly if the
# matched action has no associated specification (instead of silently
# falling back to policy evaluation).
#
# Returns: preview.items[] (each with predicted status + message) and
# preview.aggregate_prediction (the would-be final outcome). The resolved
# specification is echoed under `specification_snapshot` (the response also
# mirrors the deprecated `template_snapshot` alias — same value — until the
# legacy surface is sunset).
# Useful when editing a specification — see which items would pass / fail
# against a known context (e.g. a real build's metadata).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; ACTION=""; CONTEXT_FILE=""; ENTITY=""; ENTITY_ID=""; APPROVAL_MODE="checklist"
while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --action) ACTION="$2"; shift 2 ;;
        --context-file) CONTEXT_FILE="$2"; shift 2 ;;
        --entity) ENTITY="$2"; shift 2 ;;
        --entity-id) ENTITY_ID="$2"; shift 2 ;;
        --approval-mode) APPROVAL_MODE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg action "$ACTION"
require_arg context-file "$CONTEXT_FILE"

CONTEXT="$(load_definition_file "$CONTEXT_FILE")"

DATA=$(jq -n \
    --arg nrn "$NRN" \
    --arg action "$ACTION" \
    --arg entity "$ENTITY" \
    --arg entity_id "$ENTITY_ID" \
    --arg approval_mode "$APPROVAL_MODE" \
    --argjson context "$CONTEXT" \
    '{nrn: $nrn, action: $action, context: $context, approval_mode: $approval_mode}
     | if $entity != "" then . + {entity: $entity} else . end
     | if $entity_id != "" then . + {entity_id: $entity_id} else . end')

call_api POST "$(approval_path "dry-run")" "$DATA"
