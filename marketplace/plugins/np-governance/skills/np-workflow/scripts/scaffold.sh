#!/bin/bash
#
# scaffold.sh - Drop a starter workflow YAML into the current directory.
#
# Usage:
#   scaffold.sh <workflow-id> [template]
#     template: hello-http (default) | webhook-echo | signal-wait | claude-agent
#
# Writes <workflow-id>.yaml in $PWD; refuses to overwrite an existing file.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/../docs/examples"

ID="${1:-}"
TEMPLATE="${2:-hello-http}"
if [ -z "$ID" ]; then
    echo "Usage: scaffold.sh <workflow-id> [hello-http|webhook-echo|signal-wait|claude-agent]" >&2
    exit 2
fi

SRC="$EXAMPLES_DIR/${TEMPLATE}.yaml"
if [ ! -f "$SRC" ]; then
    echo "ERROR: unknown template '$TEMPLATE'. Available:" >&2
    ls "$EXAMPLES_DIR" | sed 's/\.yaml$//' | sed 's/^/  /' >&2
    exit 2
fi

OUT="${ID}.yaml"
if [ -e "$OUT" ]; then
    echo "ERROR: $OUT already exists. Aborting." >&2
    exit 1
fi

# Replace placeholders. Use a safe delimiter (#) to avoid clashes with paths.
# BSD tr (macOS) treats a leading '-' as a flag, so go via sed.
NAME=$(echo "$ID" | sed -e 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')
sed -e "s#WORKFLOW_ID#$ID#g" -e "s#WORKFLOW_NAME#$NAME#g" "$SRC" > "$OUT"

echo "Wrote $OUT (template=$TEMPLATE)"
echo ""
echo "Next steps:"
echo "  1. Edit $OUT — at minimum review inputs and steps."
echo "  2. Publish:  /np-workflow publish $OUT"
echo "  3. Trigger:  /np-workflow trigger $ID   (for webhook templates)"
echo "             or /np-workflow run     $ID   (for manual-triggered)"
