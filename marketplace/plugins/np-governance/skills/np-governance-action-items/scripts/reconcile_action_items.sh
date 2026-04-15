#!/bin/bash
#
# reconcile_action_items.sh - Reconcile action items with current scan results
#
# Implements the reconciliation pattern:
#  1. Read current problems from --problems-file (JSON array)
#  2. List existing items created by --agent-id with metadata.<key> indexing
#  3. For each current problem without matching item: CREATE
#  4. For each existing item without matching current problem: RESOLVE
#     (only if status=open; deferred/pending_* are skipped to respect humans)
#  5. Print summary report
#
# Usage:
#   reconcile_action_items.sh \
#     --nrn <nrn> \
#     --agent-id <agent_id> \
#     --metadata-key <key> \
#     --problems-file <path-to-json> \
#     [--dry-run]
#
# Problems file format (JSON array). Each object MUST contain the metadata key
# at top level OR inside a `metadata` object. Other recognized fields:
#   title (required for create), priority, category_slug, category_id, value,
#   description, metadata (object), labels (object),
#   affected_resources (array), references (array)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

NRN=""; AGENT_ID=""; METADATA_KEY=""; PROBLEMS_FILE=""; DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --nrn) NRN="$2"; shift 2 ;;
        --agent-id) AGENT_ID="$2"; shift 2 ;;
        --metadata-key) METADATA_KEY="$2"; shift 2 ;;
        --problems-file) PROBLEMS_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_arg nrn "$NRN"
require_arg agent-id "$AGENT_ID"
require_arg metadata-key "$METADATA_KEY"
require_arg problems-file "$PROBLEMS_FILE"

if [ ! -f "$PROBLEMS_FILE" ]; then
    echo "Error: problems file not found: $PROBLEMS_FILE" >&2
    exit 1
fi

# Validate file is a JSON array
if ! jq -e 'type == "array"' "$PROBLEMS_FILE" >/dev/null; then
    echo "Error: problems file must be a JSON array" >&2
    exit 1
fi

CURRENT_PROBLEMS=$(cat "$PROBLEMS_FILE")
PROBLEM_COUNT=$(echo "$CURRENT_PROBLEMS" | jq 'length')

# 1. Fetch all existing live items from this agent (paginated)
EXISTING="[]"
OFFSET=0
LIMIT=100
LIVE_STATUSES="open,deferred,pending_deferral,pending_verification,pending_rejection"

while true; do
    QS="nrn=$(urlencode "$NRN")&created_by=$(urlencode "$AGENT_ID")&offset=${OFFSET}&limit=${LIMIT}"
    IFS=',' read -ra STS <<< "$LIVE_STATUSES"
    for st in "${STS[@]}"; do
        QS+="&status[]=$(urlencode "$st")"
    done
    PAGE=$(call_api GET "$(gov_path "action_item")?${QS}")
    PAGE_RESULTS=$(echo "$PAGE" | jq '.results // []')
    PAGE_COUNT=$(echo "$PAGE_RESULTS" | jq 'length')
    if [ "$PAGE_COUNT" = "0" ]; then break; fi
    EXISTING=$(echo "$EXISTING $PAGE_RESULTS" | jq -s 'add')
    if [ "$PAGE_COUNT" -lt "$LIMIT" ]; then break; fi
    OFFSET=$((OFFSET + LIMIT))
done

EXISTING_COUNT=$(echo "$EXISTING" | jq 'length')

# 2. Build maps by metadata key
EXISTING_KEYS=$(echo "$EXISTING" | jq -r --arg key "$METADATA_KEY" \
    '[.[] | (.metadata // {}) | .[$key] // empty] | unique | .[]')

CURRENT_KEYS=$(echo "$CURRENT_PROBLEMS" | jq -r --arg key "$METADATA_KEY" \
    '[.[] | (.[$key] // (.metadata // {})[$key]) // empty] | unique | .[]')

CREATED=0; RESOLVED=0; UNCHANGED=0; SKIPPED=0
CREATED_IDS="[]"; RESOLVED_IDS="[]"; SKIPPED_DETAILS="{}"

# Helper: log action
log_action() {
    if [ "$DRY_RUN" = "true" ]; then
        echo "WOULD $1" >&2
    else
        echo "DOING $1" >&2
    fi
}

# 3. Create for new problems
echo "$CURRENT_PROBLEMS" | jq -c '.[]' | while read -r problem; do
    KEY=$(echo "$problem" | jq -r --arg k "$METADATA_KEY" '.[$k] // (.metadata // {})[$k] // empty')
    [ -z "$KEY" ] && continue

    EXISTS=$(echo "$EXISTING" | jq --arg key "$METADATA_KEY" --arg val "$KEY" \
        '[.[] | select((.metadata // {})[$key] == $val)] | length')

    if [ "$EXISTS" = "0" ]; then
        TITLE=$(echo "$problem" | jq -r '.title // empty')
        if [ -z "$TITLE" ]; then
            echo "Skipping problem with no title: key=$KEY" >&2
            continue
        fi

        log_action "CREATE: $KEY ($TITLE)"

        if [ "$DRY_RUN" = "false" ]; then
            ARGS=(--nrn "$NRN" --title "$TITLE" --created-by "$AGENT_ID")

            CSLUG=$(echo "$problem" | jq -r '.category_slug // empty')
            CID=$(echo "$problem" | jq -r '.category_id // empty')
            [ -n "$CSLUG" ] && ARGS+=(--category-slug "$CSLUG")
            [ -n "$CID" ] && ARGS+=(--category-id "$CID")

            DESC=$(echo "$problem" | jq -r '.description // empty')
            [ -n "$DESC" ] && ARGS+=(--description "$DESC")

            PRIO=$(echo "$problem" | jq -r '.priority // empty')
            [ -n "$PRIO" ] && ARGS+=(--priority "$PRIO")

            VAL=$(echo "$problem" | jq -r '.value // empty')
            [ -n "$VAL" ] && ARGS+=(--value "$VAL")

            META=$(echo "$problem" | jq -c '.metadata // empty')
            [ -n "$META" ] && [ "$META" != "null" ] && ARGS+=(--metadata "$META")

            LABS=$(echo "$problem" | jq -c '.labels // empty')
            [ -n "$LABS" ] && [ "$LABS" != "null" ] && ARGS+=(--labels "$LABS")

            AR=$(echo "$problem" | jq -c '.affected_resources // empty')
            [ -n "$AR" ] && [ "$AR" != "null" ] && ARGS+=(--affected-resources "$AR")

            REFS=$(echo "$problem" | jq -c '.references // empty')
            [ -n "$REFS" ] && [ "$REFS" != "null" ] && ARGS+=(--references "$REFS")

            "${SCRIPT_DIR}/create_action_item.sh" "${ARGS[@]}" >/dev/null
        fi
    fi
done

# 4. Auto-resolve obsolete (only items in 'open')
echo "$EXISTING" | jq -c '.[]' | while read -r item; do
    ITEM_ID=$(echo "$item" | jq -r '.id')
    ITEM_STATUS=$(echo "$item" | jq -r '.status')
    KEY=$(echo "$item" | jq -r --arg k "$METADATA_KEY" '(.metadata // {})[$k] // empty')
    [ -z "$KEY" ] && continue

    STILL_PRESENT=$(echo "$CURRENT_PROBLEMS" | jq --arg key "$METADATA_KEY" --arg val "$KEY" \
        '[.[] | select((.[$key] // (.metadata // {})[$key]) == $val)] | length')

    if [ "$STILL_PRESENT" = "0" ]; then
        if [ "$ITEM_STATUS" = "open" ]; then
            log_action "RESOLVE: $ITEM_ID (key $METADATA_KEY=$KEY no longer detected)"
            if [ "$DRY_RUN" = "false" ]; then
                "${SCRIPT_DIR}/add_comment.sh" --id "$ITEM_ID" --author "$AGENT_ID" \
                    --content "## Auto-resolved by reconciler

The problem identified by \`${METADATA_KEY}=${KEY}\` is no longer detected in the latest scan by \`${AGENT_ID}\`.

Resolved at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
                "${SCRIPT_DIR}/resolve_action_item.sh" --id "$ITEM_ID" --actor "$AGENT_ID" >/dev/null
            fi
        else
            log_action "SKIP: $ITEM_ID (status=$ITEM_STATUS, respecting human decision)"
        fi
    fi
done

# 5. Compute summary
TOTAL_CURRENT=$(echo "$CURRENT_PROBLEMS" | jq 'length')
TOTAL_EXISTING=$(echo "$EXISTING" | jq 'length')

# Count by re-iterating (since we used while subshells, we lost variable updates)
CREATED=$(comm -23 <(echo "$CURRENT_KEYS" | sort -u) <(echo "$EXISTING_KEYS" | sort -u) | wc -l | tr -d ' ')
RESOLVED_CANDIDATES=$(comm -13 <(echo "$CURRENT_KEYS" | sort -u) <(echo "$EXISTING_KEYS" | sort -u) | wc -l | tr -d ' ')
UNCHANGED=$(comm -12 <(echo "$CURRENT_KEYS" | sort -u) <(echo "$EXISTING_KEYS" | sort -u) | wc -l | tr -d ' ')

# RESOLVED actually applied = resolved_candidates that were in 'open' status
# (others were skipped)
RESOLVED=0; SKIPPED=0
echo "$EXISTING" | jq -c '.[]' | while read -r item; do
    KEY=$(echo "$item" | jq -r --arg k "$METADATA_KEY" '(.metadata // {})[$k] // empty')
    STATUS=$(echo "$item" | jq -r '.status')
    [ -z "$KEY" ] && continue
    if ! echo "$CURRENT_KEYS" | grep -Fxq "$KEY"; then
        if [ "$STATUS" = "open" ]; then
            echo "RESOLVED" >> /tmp/.recon-counters.$$
        else
            echo "SKIPPED" >> /tmp/.recon-counters.$$
        fi
    fi
done

if [ -f "/tmp/.recon-counters.$$" ]; then
    RESOLVED=$(grep -c '^RESOLVED$' "/tmp/.recon-counters.$$" 2>/dev/null || echo 0)
    SKIPPED=$(grep -c '^SKIPPED$' "/tmp/.recon-counters.$$" 2>/dev/null || echo 0)
    rm -f "/tmp/.recon-counters.$$"
fi

jq -n \
    --argjson current "$TOTAL_CURRENT" \
    --argjson existing "$TOTAL_EXISTING" \
    --argjson created "$CREATED" \
    --argjson resolved "$RESOLVED" \
    --argjson unchanged "$UNCHANGED" \
    --argjson skipped "$SKIPPED" \
    --arg dry_run "$DRY_RUN" \
    '{
        dry_run: ($dry_run == "true"),
        scan: {
            current_problems: $current,
            existing_items: $existing
        },
        created: $created,
        resolved: $resolved,
        unchanged: $unchanged,
        skipped: $skipped
    }'
