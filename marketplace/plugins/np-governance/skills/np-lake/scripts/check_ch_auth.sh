#!/bin/bash
#
# check_ch_auth.sh - Validate Customer Lake authentication and connectivity
#
# Usage:
#   ./check_ch_auth.sh
#
# Exit codes:
#   0 - Authentication configured and connectivity verified
#   1 - Authentication or connectivity failed
#
# Authentication: Uses nullplatform user token (Bearer header).
# Token source (in order of priority):
#   1. NP_TOKEN environment variable
#   2. NP_API_KEY environment variable
#
# Endpoint: https://api.nullplatform.com/data/lake/query (same API, lake path)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Resolve HTTP client: npcurl (Docker) > curl (local)
if command -v npcurl &> /dev/null; then
    CURL_CMD="npcurl"
elif command -v curl &> /dev/null; then
    CURL_CMD="curl"
else
    echo -e "${RED}[FAIL]${NC} No HTTP client available (tried npcurl, curl)"
    exit 1
fi

# Customer Lake endpoint (same base as nullplatform API)
LAKE_URL="https://api.nullplatform.com/data/lake/query"

AUTH_TOKEN=""

# Step 1: Check authentication token
echo "Checking Customer Lake authentication..."
echo ""

if [ -n "$NP_TOKEN" ]; then
    AUTH_TOKEN="$NP_TOKEN"
    echo -e "${GREEN}[OK]${NC} Token found via: NP_TOKEN environment variable"
elif [ -n "$NP_API_KEY" ]; then
    AUTH_TOKEN="$NP_API_KEY"
    echo -e "${GREEN}[OK]${NC} Token found via: NP_API_KEY environment variable"
fi

if [ -z "$AUTH_TOKEN" ]; then
    echo -e "${RED}[FAIL]${NC} No authentication token found."
    echo ""
    echo "Please configure authentication using ONE of these options:"
    echo ""
    echo "  Option 1: Set NP_TOKEN environment variable"
    echo "    export NP_TOKEN='your-nullplatform-token'"
    echo ""
    echo "  Option 2: Set NP_API_KEY environment variable"
    echo "    export NP_API_KEY='your-nullplatform-api-key'"
    echo ""
    exit 1
fi

# Step 2: Test connectivity
echo ""
echo "Testing connectivity to Customer Lake..."

RESPONSE=$($CURL_CMD -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: text/plain" \
    --connect-timeout 10 \
    --max-time 15 \
    --data-binary "SELECT 1" \
    "${LAKE_URL}" 2>/dev/null)

if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}[OK]${NC} Customer Lake connectivity verified (SELECT 1 succeeded)"
elif [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "403" ]; then
    echo -e "${RED}[FAIL]${NC} Authentication failed (HTTP $RESPONSE). Your token may not have access to the data lake."
    exit 1
elif [ "$RESPONSE" = "000" ]; then
    echo -e "${RED}[FAIL]${NC} Cannot connect to Customer Lake. Check network connectivity."
    exit 1
else
    echo -e "${RED}[FAIL]${NC} Unexpected response from Customer Lake (HTTP $RESPONSE)."
    exit 1
fi

# Summary
echo ""
echo "========================================="
echo -e "${GREEN}Customer Lake authentication is configured.${NC}"
echo "========================================="
echo ""
echo "You can now run queries with:"
echo "  ${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh \"SELECT * FROM core_entities_application LIMIT 5\""
echo ""

exit 0
