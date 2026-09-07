#!/bin/bash
#
# get_specification.sh - Fetch a single checklist specification by id
#
# Usage:
#   get_specification.sh --id <spec_xxx|tmpl_xxx>
#
# IDs are opaque: specifications created before the rename keep their
# tmpl_ prefix, new ones are minted as spec_. Both work here.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

call_api GET "$(approval_path "checklist/specification/${ID}")"
