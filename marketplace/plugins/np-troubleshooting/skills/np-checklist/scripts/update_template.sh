#!/bin/bash
#
# update_template.sh - Partial update of a checklist template
#
# Usage:
#   update_template.sh --id <tmpl_xxx> [--name <name>] [--description <text>] \
#                      [--status <status>] [--definition-file <path>]
#
# At least one mutable field must be provided. Updating `definition` bumps
# `version` server-side (typically — confirm with the API).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; NAME=""; DESCRIPTION=""; STATUS=""; DEF_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --definition-file) DEF_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

if [ -z "$NAME" ] && [ -z "$DESCRIPTION" ] && [ -z "$STATUS" ] && [ -z "$DEF_FILE" ]; then
    echo "Error: at least one of --name/--description/--status/--definition-file is required" >&2
    exit 1
fi

DEFINITION_JSON="null"
if [ -n "$DEF_FILE" ]; then
    DEFINITION_JSON="$(load_definition_file "$DEF_FILE")"
fi

DATA=$(jq -n \
    --arg name "$NAME" \
    --arg description "$DESCRIPTION" \
    --arg status "$STATUS" \
    --argjson definition "$DEFINITION_JSON" \
    '{}
     | if $name != "" then . + {name: $name} else . end
     | if $description != "" then . + {description: $description} else . end
     | if $status != "" then . + {status: $status} else . end
     | if $definition != null then . + {definition: $definition} else . end')

call_api PATCH "$(approval_path "checklist/template/${ID}")" "$DATA"
