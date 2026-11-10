#!/bin/bash
#
# Dump K8s status for a scope via the runtime agent
#
# Usage:
#   ./scope-agent-dump.sh <scope_id> [nrn] [selector_key] [selector_value]
#
# Examples:
#   ./scope-agent-dump.sh 12345
#   ./scope-agent-dump.sh 12345 "organization=1:account=2"
#   ./scope-agent-dump.sh 12345 "organization=1:account=2" environment production
#
# Output:
#   JSON with K8s deployment status, pod events, and logs
#
# Notes:
#   - Without an nrn, the agent search uses the organization of the scope (read from its NRN)
#   - Default selector is {cluster: "runtime"}; organizations may use others (e.g., environment: production)
#   - Check the notification channel configuration to find the correct selector
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <scope_id> [nrn] [selector_key] [selector_value]"
    echo ""
    echo "Dump K8s status for a scope via the runtime agent."
    echo ""
    echo "Arguments:"
    echo "  scope_id        - The scope ID to dump status for"
    echo "  nrn             - Optional. NRN to scope the agent search (default: the scope's organization)"
    echo "  selector_key    - Optional. Selector key for agent matching (default: cluster)"
    echo "  selector_value  - Optional. Selector value for agent matching (default: runtime)"
    echo ""
    echo "Examples:"
    echo "  $0 12345"
    echo "  $0 12345 \"organization=1:account=2\""
    echo "  $0 12345 \"organization=1:account=2\" environment production"
    echo ""
    echo "Notes:"
    echo "  Different organizations use different agent selectors. Common ones:"
    echo "    cluster runtime       - Default"
    echo "    environment <name>    - Agents tagged by environment"
    echo "  Check the notification channel config to find the correct selector."
    exit 1
fi

SCOPE_ID="$1"
NRN="${2:-}"
SELECTOR_KEY="${3:-cluster}"
SELECTOR_VALUE="${4:-runtime}"

# Default the agent search to the scope's own organization
if [ -z "$NRN" ]; then
    NRN=$("$SCRIPT_DIR/fetch_np_api_url.sh" "/scope/$SCOPE_ID" | jq -r '.nrn // empty | split(":")[0]' 2>/dev/null || true)
    if [ -z "$NRN" ]; then
        echo "Error: could not read the NRN of scope $SCOPE_ID; pass it as the second argument" >&2
        exit 1
    fi
fi

# Build request body with configurable selector
REQUEST_BODY=$(jq -n \
    --arg nrn "$NRN" \
    --arg scope_id "$SCOPE_ID" \
    --arg sel_key "$SELECTOR_KEY" \
    --arg sel_value "$SELECTOR_VALUE" \
    '{
        nrn: $nrn,
        selector: {($sel_key): $sel_value},
        command: {
            type: "exec",
            data: {
                cmdline: "nullplatform/scopes/k8s/troubleshooting/dump-status",
                arguments: ["--scope-id", $scope_id, "--k8s-namespace", "nullplatform"]
            }
        }
    }')

# Execute via fetch_np_api_url.sh (handles authentication)
"$SCRIPT_DIR/fetch_np_api_url.sh" --method POST --data "$REQUEST_BODY" "/controlplane/agent_command"
