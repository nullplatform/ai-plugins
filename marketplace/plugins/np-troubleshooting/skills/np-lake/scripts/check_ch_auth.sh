#!/bin/bash
#
# check_ch_auth.sh - Validate Customer Lake authentication and connectivity.
#
# Usage:
#   ./check_ch_auth.sh
#
# Exit codes:
#   0 - Authentication verified and lake reachable
#   1 - Authentication or connectivity failed
#
# Reads NP_API_KEY (preferred) or NP_TOKEN env var. See scripts/lib/np_auth.sh.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/np_auth.sh
source "${SCRIPT_DIR}/lib/np_auth.sh"

CH_QUERY="${SCRIPT_DIR}/ch_query.sh"

if [ ! -x "$CH_QUERY" ]; then
    echo -e "${RED}[FAIL]${NC} ch_query.sh is missing or not executable: $CH_QUERY" >&2
    exit 1
fi

echo "Checking nullplatform authentication..."
if ! BEARER_TOKEN=$(get_valid_token); then
    echo -e "${RED}[FAIL]${NC} No valid credentials. Configure NP_API_KEY or NP_TOKEN and retry." >&2
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Authentication token resolved"

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
    echo "  ${SCRIPT_DIR}/ch_query.sh \"SELECT * FROM core_entities_application LIMIT 5\""
    echo ""
    exit 0
fi

echo -e "${RED}[FAIL]${NC} Customer Lake request failed." >&2
echo "$LAKE_OUT" >&2
exit 1
