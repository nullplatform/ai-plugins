#!/bin/bash
#
# dry_run_template.sh - Pre-evaluate a template against a context (no run created)
#
# Usage:
#   dry_run_template.sh --template-id <tmpl_xxx> --context-file <path.json>
#
# Returns: preview.items[] (each with predicted status + message) and
# preview.aggregate_prediction (the would-be final outcome).
# Useful when editing a template — see which items would pass / fail
# against a known context (e.g. a real build's metadata).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

TEMPLATE_ID=""; CONTEXT_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --template-id) TEMPLATE_ID="$2"; shift 2 ;;
        --context-file) CONTEXT_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg template-id "$TEMPLATE_ID"
require_arg context-file "$CONTEXT_FILE"

CONTEXT="$(load_definition_file "$CONTEXT_FILE")"

DATA=$(jq -n --argjson context "$CONTEXT" '{context: $context}')

call_api POST "$(approval_path "checklist/template/${TEMPLATE_ID}/dry-run")" "$DATA"
