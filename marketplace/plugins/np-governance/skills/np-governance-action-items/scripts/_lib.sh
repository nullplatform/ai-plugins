#!/bin/bash
#
# _lib.sh - Shared helpers for np-governance-action-items scripts
#
# Provides:
#   - NP_API: path to np-api fetch_np_api_url.sh
#   - gov_path <endpoint>: prefixes the /governance gateway path
#   - urlencode <string>: percent-encodes a string for use in query params
#   - require_arg <name> <value>: errors out if value is empty
#   - call_api <method> <path> [<data>]: invokes np-api fetch with proper flags
#
# All calls go through api.nullplatform.com/governance/* via np-api. There is
# no backend override — if /governance/* returns 404, the gateway route has
# not been deployed yet; escalate to the team, do NOT point at internal hosts.

set -e

# Path to np-api wrapper. Use ${CLAUDE_PLUGIN_ROOT} if available, else relative.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    NP_API="${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NP_API="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"
fi

if [ ! -x "$NP_API" ]; then
    echo "Error: np-api fetch script not found at $NP_API" >&2
    echo "Make sure the np-api skill is installed alongside np-governance-action-items." >&2
    exit 1
fi

# Gateway path prefix. Hardcoded — all calls go through api.nullplatform.com.
GOVERNANCE_PREFIX="/governance"

# Build a governance endpoint path
gov_path() {
    echo "${GOVERNANCE_PREFIX}/$1"
}

# urlencode a string (basic implementation, sufficient for query values)
urlencode() {
    local s="$1"
    local out=""
    local i c
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$out"
}

# Fail with error message if a required arg is empty
require_arg() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "Error: --${name} is required" >&2
        exit 1
    fi
}

# Call the np-api wrapper with proper flags
# Usage: call_api <method> <endpoint> [<data>]
call_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [ "$method" = "GET" ] || [ "$method" = "HEAD" ]; then
        "$NP_API" "$endpoint"
    else
        if [ -n "$data" ]; then
            "$NP_API" --method "$method" --data "$data" "$endpoint"
        else
            "$NP_API" --method "$method" "$endpoint"
        fi
    fi
}
