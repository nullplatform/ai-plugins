#!/bin/bash
#
# ping.sh - Verify NP_WORKFLOW_URL is reachable and the token is accepted.
#
# Phase 1: anonymous GET ${NP_WORKFLOW_URL}${NP_WORKFLOW_BASE_PATH}/metadata
#          — confirms the URL is actually a workflow engine.
# Phase 2: authenticated GET /workflows/plugins?limit=1 — confirms the bearer
#          token is accepted by the engine. The engine does NOT expose a
#          /whoami endpoint; identity resolution is the auth layer's job
#          (decode the JWT or hit the Nullplatform auth API for details).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to the public NP control plane (the engine is mounted at
# api.nullplatform.com/workflows). Override for self-hosted deployments.
NP_WORKFLOW_URL="${NP_WORKFLOW_URL:-https://api.nullplatform.com}"

# Normalise base path
BASE_PATH="${NP_WORKFLOW_BASE_PATH:-/workflows}"
case "$BASE_PATH" in
    /*) ;;
    *)  BASE_PATH="/$BASE_PATH" ;;
esac
BASE_PATH="${BASE_PATH%/}"

META_URL="${NP_WORKFLOW_URL%/}${BASE_PATH}/metadata"

# Phase 1: anonymous /metadata — does not use workflow-api.sh because it
# should work BEFORE auth is configured.
echo "GET $META_URL"
RESP=$(curl -s -S -w '\n__HTTP_STATUS__%{http_code}' "$META_URL")
STATUS=$(printf '%s' "$RESP" | awk -F'__HTTP_STATUS__' '{print $2}' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | awk -F'__HTTP_STATUS__' '{print $1}')

if [ "$STATUS" != "200" ]; then
    echo "" >&2
    echo "ERROR: Expected HTTP 200, got HTTP $STATUS." >&2
    echo "$BODY" >&2
    echo "" >&2
    echo "This URL does not look like a workflow engine. Verify:" >&2
    echo "  1. NP_WORKFLOW_URL has no trailing /workflows suffix (it's added)" >&2
    echo "  2. NP_WORKFLOW_BASE_PATH matches the engine's REST prefix (default /workflows)" >&2
    echo "  3. The URL is reachable from this machine (DNS, VPN, etc.)" >&2
    exit 1
fi

echo "$BODY" | jq -r '
"API:           reachable",
"Version:       \(.apiVersion)",
"Plugins:       \(.pluginCount) registered",
"Plugin types:  \(.supportedPluginTypes | join(", "))",
"Topology:      \(.topology)",
"Max executions:\(.maxNodeExecutions)",
"Features:      temporal=\(.features.temporal) rbac=\(.features.rbac) multiOrg=\(.features.multiOrg)"
'

# Phase 2: authenticated probe via any RBAC-gated endpoint. We use plugins
# (limit=1) because it's the cheapest read; a 200 means the token is
# accepted, 401 means rejected, 403 means accepted-but-no-permission.
# The engine does not expose its own /whoami — use the JWT payload or the
# Nullplatform auth API for identity details.
echo ""
echo "Checking authentication..."
AUTH_PROBE_URL="${NP_WORKFLOW_URL%/}${BASE_PATH}/plugins?limit=1"
RESP=$("$SCRIPT_DIR/workflow-api.sh" GET "/plugins?limit=1" 2>&1)
AUTH_EXIT=$?

case "$AUTH_EXIT" in
    0)
        echo "Auth:          OK (token accepted by engine)"
        ;;
    4)
        # workflow-api.sh exits 4 for any 4xx — distinguish 401 vs 403 from the body.
        echo "Auth:          rejected (4xx)" >&2
        echo "Response:" >&2
        echo "$RESP" >&2
        echo "" >&2
        echo "Common causes:" >&2
        echo "  401 — token missing/invalid/expired" >&2
        echo "  403 — token valid, identity lacks 'plugin:read' permission" >&2
        echo "" >&2
        echo "Run for details: $AUTH_PROBE_URL" >&2
        exit 0
        ;;
    *)
        echo "Auth:          probe error" >&2
        echo "$RESP" >&2
        exit 0
        ;;
esac
