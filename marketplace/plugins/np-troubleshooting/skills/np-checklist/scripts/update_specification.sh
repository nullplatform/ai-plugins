#!/bin/bash
#
# update_specification.sh - Partial update of a checklist specification
#
# Usage:
#   update_specification.sh --id <spec_xxx|tmpl_xxx> [--name <name>] [--description <text>] \
#                           [--definition-file <path>]
#
# At least one mutable field must be provided. Every successful update
# creates a NEW specification row: new spec_ id, version = max(version)+1
# for the (nrn, name) lineage. The action keeps pointing at the OLD id —
# re-run set_action_specification.sh with the returned id.
#
# There is no --status: the PATCH endpoint ignores a status field (a 200
# would still change nothing). To soft-delete, use delete_specification.sh.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; NAME=""; DESCRIPTION=""; DEF_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --definition-file) DEF_FILE="$2"; shift 2 ;;
        --status)
            echo "Error: --status is not supported — PATCH has no status mutation (the API ignores the field). To soft-delete, use delete_specification.sh." >&2
            exit 1 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

if [ -z "$NAME" ] && [ -z "$DESCRIPTION" ] && [ -z "$DEF_FILE" ]; then
    echo "Error: at least one of --name/--description/--definition-file is required" >&2
    exit 1
fi

DEFINITION_JSON="null"
if [ -n "$DEF_FILE" ]; then
    DEFINITION_JSON="$(load_definition_file "$DEF_FILE")"
fi

DATA=$(jq -n \
    --arg name "$NAME" \
    --arg description "$DESCRIPTION" \
    --argjson definition "$DEFINITION_JSON" \
    '{}
     | if $name != "" then . + {name: $name} else . end
     | if $description != "" then . + {description: $description} else . end
     | if $definition != null then . + {definition: $definition} else . end')

call_api PATCH "$(approval_path "checklist/specification/${ID}")" "$DATA"
