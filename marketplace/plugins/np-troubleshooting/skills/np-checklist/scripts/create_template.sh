#!/bin/bash
#
# create_template.sh - Create a checklist template
#
# Usage:
#   create_template.sh --nrn <nrn> --name <name> --definition-file <path> \
#                      --created-by <email> [--description <text>] [--version <n>]
#
# --definition-file accepts YAML (.yaml/.yml) or JSON (.json). The file
# contents are POSTed as the `definition` field of the template.
# Server assigns the id (tmpl_xxx) and computes derived_expression.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; NAME=""; DEF_FILE=""; CREATED_BY=""; DESCRIPTION=""; VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --definition-file) DEF_FILE="$2"; shift 2 ;;
        --created-by) CREATED_BY="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg name "$NAME"
require_arg definition-file "$DEF_FILE"
require_arg created-by "$CREATED_BY"

DEFINITION="$(load_definition_file "$DEF_FILE")"

DATA=$(jq -n \
    --arg nrn "$NRN" \
    --arg name "$NAME" \
    --arg created_by "$CREATED_BY" \
    --arg description "$DESCRIPTION" \
    --argjson definition "$DEFINITION" \
    --arg version "$VERSION" \
    '{nrn: $nrn, name: $name, created_by: $created_by, definition: $definition}
     | if $description != "" then . + {description: $description} else . end
     | if $version != "" then . + {version: ($version | tonumber)} else . end')

call_api POST "$(approval_path "checklist/template")" "$DATA"
