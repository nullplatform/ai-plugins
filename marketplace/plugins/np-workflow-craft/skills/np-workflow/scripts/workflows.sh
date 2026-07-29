#!/bin/bash
#
# workflows.sh - List workflows or describe one.
#
# Usage:
#   workflows.sh                     List workflows
#   workflows.sh describe <id>       Show workflow + aliases + triggerStates + webhook URLs

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

CMD="${1:-list}"

if [ "$CMD" = "list" ] || [ "$CMD" = "" ]; then
    BODY=$("$API" GET "/workflows?limit=100") || exit $?
    COUNT=$(echo "$BODY" | jq -r '.data // [] | length')
    echo "Workflows: $COUNT"
    echo ""
    printf '%-44s %-10s %s\n' ID LATEST NAME
    printf '%-44s %-10s %s\n' -- ------ ----
    echo "$BODY" | jq -r '.data[]? | [.id, (.latestRevision // "—"), (.name // "")] | @tsv' \
      | while IFS=$'\t' read -r id rev name; do
          printf '%-44s %-10s %s\n' "$id" "$rev" "$name"
        done
    exit 0
fi

if [ "$CMD" = "describe" ]; then
    ID="${2:-}"
    if [ -z "$ID" ]; then
        echo "Usage: workflows.sh describe <id>" >&2
        exit 2
    fi
    WF=$("$API" GET "/definitions/$ID") || exit $?
    echo "Workflow:"
    echo "$WF" | jq '{id, name, description, latestRevision, organizationId, createdAt}'
    echo ""

    REVS=$("$API" GET "/definitions/$ID/revisions?limit=20") || true
    echo "Revisions:"
    echo "$REVS" | jq -r '.data[] | "  r\(.revision)  \(.createdAt)  \(.message // "")"' 2>/dev/null \
      || echo "  (none)"
    echo ""

    ALIASES=$("$API" GET "/definitions/$ID/aliases") || true
    echo "Aliases:"
    echo "$ALIASES" | jq -r '.data[]? | "  \(.name) -> r\(.revision)  \(if .activatedAt then "[ACTIVE since " + .activatedAt + "]" else "[inactive]" end)"' 2>/dev/null \
      || echo "  (none)"
    echo ""

    TRIGS=$("$API" GET "/triggers?workflowId=$ID&status=active") || true
    echo "Active triggers:"
    echo "$TRIGS" | jq -r '.data[]? | "  [\(.aliasName) / \(.pluginType)] \(.triggerId) \(.runtimeMetadata.webhookUrl // "")"' 2>/dev/null \
      || echo "  (none)"
    exit 0
fi

echo "Usage: workflows.sh [list|describe <id>]" >&2
exit 2
