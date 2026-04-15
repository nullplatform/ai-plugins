#!/bin/bash
#
# update_action_item.sh - Patch an action item
#
# Usage:
#   update_action_item.sh --id <id> [field flags...]
#
# Field flags (any subset):
#   --title <text>
#   --description <text>
#   --priority <p>
#   --value <num>
#   --status <status>
#   --due-date <iso8601>
#   --metadata <json>
#   --labels <json>
#   --affected-resources <json>
#   --references <json>
#   --config <json>
#   --actor <actor>           (used together with --status)
#   --reason <text>           (used together with --status)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

ID=""
TITLE=""; DESCRIPTION=""; PRIORITY=""; VALUE=""; STATUS=""; DUE_DATE=""
METADATA=""; LABELS=""; AFFECTED_RESOURCES=""; REFERENCES=""; CONFIG=""
ACTOR=""; REASON=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --id) ID="$2"; shift 2 ;;
        --title) TITLE="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --value) VALUE="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --due-date) DUE_DATE="$2"; shift 2 ;;
        --metadata) METADATA="$2"; shift 2 ;;
        --labels) LABELS="$2"; shift 2 ;;
        --affected-resources) AFFECTED_RESOURCES="$2"; shift 2 ;;
        --references) REFERENCES="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        --actor) ACTOR="$2"; shift 2 ;;
        --reason) REASON="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg id "$ID"

DATA=$(jq -n \
    --arg title "$TITLE" \
    --arg description "$DESCRIPTION" \
    --arg priority "$PRIORITY" \
    --arg value "$VALUE" \
    --arg status "$STATUS" \
    --arg due_date "$DUE_DATE" \
    --argjson metadata "${METADATA:-null}" \
    --argjson labels "${LABELS:-null}" \
    --argjson affected_resources "${AFFECTED_RESOURCES:-null}" \
    --argjson references "${REFERENCES:-null}" \
    --argjson config "${CONFIG:-null}" \
    --arg actor "$ACTOR" \
    --arg reason "$REASON" \
    '{}
    + (if $title != "" then {title: $title} else {} end)
    + (if $description != "" then {description: $description} else {} end)
    + (if $priority != "" then {priority: $priority} else {} end)
    + (if $value != "" then {value: ($value | tonumber)} else {} end)
    + (if $status != "" then {status: $status} else {} end)
    + (if $due_date != "" then {due_date: $due_date} else {} end)
    + (if $metadata != null then {metadata: $metadata} else {} end)
    + (if $labels != null then {labels: $labels} else {} end)
    + (if $affected_resources != null then {affected_resources: $affected_resources} else {} end)
    + (if $references != null then {references: $references} else {} end)
    + (if $config != null then {config: $config} else {} end)
    + (if $actor != "" then {actor: $actor} else {} end)
    + (if $reason != "" then {reason: $reason} else {} end)')

if [ "$DATA" = "{}" ]; then
    echo "Error: at least one field to update is required" >&2
    exit 1
fi

call_api PATCH "$(gov_path "action_item/${ID}")" "$DATA"
