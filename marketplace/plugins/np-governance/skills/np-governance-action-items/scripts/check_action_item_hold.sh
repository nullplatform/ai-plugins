#!/bin/bash
#
# check_action_item_hold.sh - Check for hold/abort instructions in human comments
#
# Fetches comments of an action item via np-api, filters out auto-generated
# comments (executor:* and agent:*), and scans the remaining human comments
# for keywords that indicate a hold/abort instruction.
#
# Refactored from the original read-comments.sh: now delegates auth to np-api
# and uses the gateway path /governance/action_item/:id/comments. The keyword
# detection logic is preserved.
#
# Usage:
#   check_action_item_hold.sh --id <action_item_id>
#
# Output JSON:
#   {
#     "should_proceed": true|false,
#     "hold_reason": "<author>: <content>" | null,
#     "user_instructions": "<concatenated human comments>" | null,
#     "comment_count": <int>,
#     "human_comment_count": <int>
#   }

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

# Fetch comments via np-api
RESPONSE=$(call_api GET "$(gov_path "action_item/${ID}/comments")")

# Normalize: response can be {results: [...]} or just [...]
COMMENTS=$(echo "$RESPONSE" | jq '.results // .')
COMMENT_COUNT=$(echo "$COMMENTS" | jq 'length // 0')

if [ "$COMMENT_COUNT" = "0" ]; then
    jq -n '{
        should_proceed: true,
        hold_reason: null,
        user_instructions: null,
        comment_count: 0,
        human_comment_count: 0
    }'
    exit 0
fi

# Filter human comments (author NOT starting with executor: or agent:)
HUMAN_COMMENTS=$(echo "$COMMENTS" | jq '[
    .[]
    | select(
        (.author // "" | startswith("executor:") | not)
        and (.author // "" | startswith("agent:") | not)
    )
]')

HUMAN_COUNT=$(echo "$HUMAN_COMMENTS" | jq 'length')

# Hold/abort keyword detection
HOLD_REASON=""
KEYWORDS_RE="abort|hold|do not execute|stop execution|cancel execution|skip this|do not apply|no ejecutar|detener|cancelar ejecucion"

if [ "$HUMAN_COUNT" -gt 0 ]; then
    HOLD_REASON=$(echo "$HUMAN_COMMENTS" | jq -r --arg re "$KEYWORDS_RE" '
        [.[] | select(.content | ascii_downcase | test($re))]
        | last
        | (if . == null then "" else "\(.author // "unknown"): \(.content)" end)
    ' 2>/dev/null || echo "")
fi

# Collect all human comments as user_instructions (most recent first)
USER_INSTRUCTIONS=""
if [ "$HUMAN_COUNT" -gt 0 ]; then
    USER_INSTRUCTIONS=$(echo "$HUMAN_COMMENTS" | jq -r '
        [.[] | "\(.author // "unknown") (\(.created_at // .createdAt // "?")): \(.content)"]
        | reverse
        | join("\n---\n")
    ' 2>/dev/null || echo "")
fi

SHOULD_PROCEED="true"
if [ -n "$HOLD_REASON" ]; then
    SHOULD_PROCEED="false"
fi

jq -n \
    --argjson should_proceed "$SHOULD_PROCEED" \
    --arg hold_reason "$HOLD_REASON" \
    --arg user_instructions "$USER_INSTRUCTIONS" \
    --argjson comment_count "$COMMENT_COUNT" \
    --argjson human_comment_count "$HUMAN_COUNT" \
    '{
        should_proceed: $should_proceed,
        hold_reason: (if $hold_reason == "" then null else $hold_reason end),
        user_instructions: (if $user_instructions == "" then null else $user_instructions end),
        comment_count: $comment_count,
        human_comment_count: $human_comment_count
    }'
