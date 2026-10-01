#!/bin/bash
#
# Dump K8s status for a deployment via the runtime agent
#
# Usage:
#   ./deploy-agent-dump.sh <deployment_id> [nrn] [selector_key] [selector_value]
#
# Examples:
#   ./deploy-agent-dump.sh 1850350294
#   ./deploy-agent-dump.sh 1850350294 "organization=4:account=17"
#   ./deploy-agent-dump.sh 1850350294 "organization=1255165411:account=95118862" environment javi-k8s
#
# Output:
#   JSON with K8s deployment status, pod events, and logs
#
# Notes:
#   - Default selector is {cluster: "runtime"} for org=4
#   - Different organizations may use different selectors (e.g., environment: javi-k8s)
#   - Check the notification channel configuration to find the correct selector
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <deployment_id> [nrn] [selector_key] [selector_value]"
    echo ""
    echo "Dump K8s status for a deployment via the runtime agent."
    echo ""
    echo "Arguments:"
    echo "  deployment_id   - The deployment ID to dump status for"
    echo "  nrn             - Optional. NRN to scope the agent search (default: organization=4)"
    echo "  selector_key    - Optional. Selector key for agent matching (default: cluster)"
    echo "  selector_value  - Optional. Selector value for agent matching (default: runtime)"
    echo ""
    echo "Examples:"
    echo "  $0 1850350294"
    echo "  $0 1850350294 \"organization=4:account=17\""
    echo "  $0 1850350294 \"organization=1255165411:account=95118862\" environment javi-k8s"
    echo ""
    echo "Notes:"
    echo "  Different organizations use different agent selectors. Common ones:"
    echo "    cluster runtime       - Default for org=4"
    echo "    environment javi-k8s  - Kwik-e-mart org"
    echo "  Check the notification channel config to find the correct selector."
    exit 1
fi

DEPLOYMENT_ID="$1"
NRN="${2:-organization=4}"
SELECTOR_KEY="${3:-cluster}"
SELECTOR_VALUE="${4:-runtime}"

# Build request body with configurable selector
REQUEST_BODY=$(jq -n \
    --arg nrn "$NRN" \
    --arg deployment_id "$DEPLOYMENT_ID" \
    --arg sel_key "$SELECTOR_KEY" \
    --arg sel_value "$SELECTOR_VALUE" \
    '{
        nrn: $nrn,
        selector: {($sel_key): $sel_value},
        command: {
            type: "exec",
            data: {
                cmdline: "nullplatform/scopes/k8s/troubleshooting/dump-status",
                arguments: ["--deployment-id", $deployment_id, "--k8s-namespace", "nullplatform"]
            }
        }
    }')

# Execute via fetch_np_api_url.sh (handles authentication)
"$SCRIPT_DIR/fetch_np_api_url.sh" --method POST --data "$REQUEST_BODY" "/controlplane/agent_command"
