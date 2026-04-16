#!/bin/bash
#
# check_ch_auth.sh - Validate Customer Lake authentication via np-api delegation.
#
# Usage:
#   ./check_ch_auth.sh
#
# Exit codes:
#   0 - Authentication verified and lake reachable
#   1 - Authentication or connectivity failed
#
# Authentication is delegated to np-api (NP_API_KEY exchange + cache, or NP_TOKEN).

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Resolve np-api scripts
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    NP_API_DIR="${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts"
    NP_LAKE_DIR="${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NP_API_DIR="${SCRIPT_DIR}/../../np-api/scripts"
    NP_LAKE_DIR="${SCRIPT_DIR}"
fi

CHECK_AUTH="${NP_API_DIR}/check_auth.sh"
CH_QUERY="${NP_LAKE_DIR}/ch_query.sh"

for f in "$CHECK_AUTH" "$CH_QUERY"; do
    if [ ! -x "$f" ]; then
        echo -e "${RED}[FAIL]${NC} Required script missing or not executable: $f"
        echo "Make sure np-api and np-lake are both installed." >&2
        exit 1
    fi
done

# Step 1: token sanity via np-api
echo "Checking nullplatform authentication..."
if ! "$CHECK_AUTH"; then
    echo -e "${RED}[FAIL]${NC} np-api authentication check failed. Configure NP_API_KEY or NP_TOKEN and retry."
    exit 1
fi

# Step 2: lake-specific reachability via ch_query.sh
echo ""
echo "Testing connectivity to Customer Lake..."

LAKE_OUT=$("$CH_QUERY" "SELECT 1 AS one" 2>&1) || LAKE_RC=$?
LAKE_RC=${LAKE_RC:-0}

if [ "$LAKE_RC" -eq 0 ] && echo "$LAKE_OUT" | grep -q '"one":1'; then
    echo -e "${GREEN}[OK]${NC} Customer Lake connectivity verified (SELECT 1 succeeded)"
    echo ""
    echo "========================================="
    echo -e "${GREEN}Customer Lake authentication is configured.${NC}"
    echo "========================================="
    echo ""
    echo "You can now run queries with:"
    echo "  \${CLAUDE_PLUGIN_ROOT}/skills/np-lake/scripts/ch_query.sh \"SELECT * FROM core_entities_application LIMIT 5\""
    echo ""
    exit 0
fi

echo -e "${RED}[FAIL]${NC} Customer Lake request failed."
echo "$LAKE_OUT"
exit 1
