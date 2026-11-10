#!/bin/bash
# Resend a notification to its channels (or to one channel).
#
# Usage:
#   ./resend_notification.sh <notification_id> [channel_id]
#
# Thin wrapper over the np-api skill's resend script, which authenticates with
# the usual tiers (NP_API_KEY, NP_TOKEN, or the `np login` session). It makes no
# assumption about the project's layout or where its secrets live.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NP_API_RESEND="$SCRIPT_DIR/../../np-api/scripts/resend_notification.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <notification_id> [channel_id]"
    echo ""
    echo "Finding notification IDs:"
    echo "  /np-api fetch-api \"/notification?nrn=<nrn>&source=service&per_page=5\""
    echo "Checking delivery results:"
    echo "  /np-api fetch-api \"/notification/<id>/result\""
    exit 1
fi

if [ ! -x "$NP_API_RESEND" ]; then
    echo "Error: np-api skill not found next to this one (expected $NP_API_RESEND)."
    echo "Install it: ./install.sh --skills np-api --target <project>/.claude/skills"
    exit 1
fi

exec "$NP_API_RESEND" "$@"
