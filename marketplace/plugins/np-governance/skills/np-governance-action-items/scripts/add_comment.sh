#!/bin/bash
#
# add_comment.sh - Add a comment to an action item
#
# Usage:
#   add_comment.sh --id <action_item_id> --author <author> --content <content>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""; AUTHOR=""; CONTENT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --author) AUTHOR="$2"; shift 2 ;;
        --content) CONTENT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"
require_arg author "$AUTHOR"
require_arg content "$CONTENT"

DATA=$(jq -n --arg author "$AUTHOR" --arg content "$CONTENT" \
    '{author: $author, content: $content}')

call_api POST "$(gov_path "action_item/${ID}/comments")" "$DATA"
