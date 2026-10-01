#!/bin/bash
#
# plugins.sh - List or describe plugins available on the deployed workflow engine.
#
# Usage:
#   plugins.sh                         List all plugins (compact table)
#   plugins.sh <category>              Filter by category (case-insensitive substring)
#   plugins.sh --type trigger          Filter by plugin type
#   plugins.sh --type module --q webhook
#   plugins.sh describe <plugin-name>  Show full descriptor for one plugin
#
# Returns table-format output ready for the user.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

if [ "${1:-}" = "describe" ]; then
    NAME="${2:-}"
    if [ -z "$NAME" ]; then
        echo "Usage: plugins.sh describe <plugin-name>" >&2
        exit 2
    fi
    BODY=$("$API" GET "/plugins/$NAME") || exit $?
    echo "$BODY" | jq '{
        name, version, pluginType, category,
        description, semanticDescription,
        executeMode,
        configSchema,
        inputPorts, outputPorts,
        examples: (.examples // [])
    }'
    exit 0
fi

# Build query string
QUERY=""
TYPE=""
Q=""
while [ $# -gt 0 ]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --q) Q="$2"; shift 2 ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)  # treat first positional as a substring filter on category
            if [ -z "$Q" ]; then Q="$1"; fi
            shift
            ;;
    esac
done
if [ -n "$TYPE" ]; then QUERY="${QUERY}&type=${TYPE}"; fi
if [ -n "$Q" ]; then QUERY="${QUERY}&q=${Q}"; fi
QUERY="${QUERY#&}"
PATH_WITH_Q="/plugins?limit=200"
if [ -n "$QUERY" ]; then PATH_WITH_Q="${PATH_WITH_Q}&${QUERY}"; fi

BODY=$("$API" GET "$PATH_WITH_Q") || exit $?

# Compact table
COUNT=$(echo "$BODY" | jq -r '.data | length')
echo "Plugins: $COUNT"
echo ""
printf '%-32s %-9s %-22s %s\n' NAME TYPE CATEGORY DESCRIPTION
printf '%-32s %-9s %-22s %s\n' -------- ---- -------- -----------
echo "$BODY" | jq -r '.data[] | [.name, .pluginType, (.category // "—"), ((.semanticDescription // .description // "") | .[0:80])] | @tsv' \
  | while IFS=$'\t' read -r name type category desc; do
      printf '%-32s %-9s %-22s %s\n' "$name" "$type" "$category" "$desc"
    done
