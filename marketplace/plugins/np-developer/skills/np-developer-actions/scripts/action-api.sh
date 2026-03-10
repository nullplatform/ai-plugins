#!/bin/bash
#
# action-api.sh - Nullplatform Developer Actions CLI
#
# Write operations against the Nullplatform API.
# Complements np-api (read-only) with POST/PATCH/PUT/DELETE.
#
# Usage:
#   action-api.sh                              Show available actions
#   action-api.sh check-auth                   Verify authentication
#   action-api.sh search-action <term>         Search actions by term
#   action-api.sh describe-action <action>     Show full action documentation
#   action-api.sh exec-api --method M --data '{...}' "/endpoint"
#
# Authentication precedence:
#   1. NP_API_KEY environment variable (exchanges for token, caches in ~/.claude/)
#   2. NP_TOKEN environment variable (direct bearer token, no cache)

set -euo pipefail

# Configuration
BASE_URL="https://api.nullplatform.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$SCRIPT_DIR/../docs"
TOKEN_CACHE_DIR="$HOME/.claude"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# On macOS, if npcurl doesn't exist, use curl as fallback
if [[ "$(uname)" == "Darwin" ]] && ! command -v npcurl &> /dev/null; then
    npcurl() { curl "$@"; }
fi

################################################################################
# Auth Functions
################################################################################

decode_base64() {
    local input="$1"
    local pad=$((4 - ${#input} % 4))
    if [ $pad -ne 4 ]; then
        input="${input}$(printf '=%.0s' $(seq 1 $pad))"
    fi
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

is_jwt_valid() {
    local token="$1"
    if [[ "$token" != *"."*"."* ]]; then
        return 1
    fi
    local payload=$(echo "$token" | cut -d'.' -f2)
    local decoded=$(decode_base64 "$payload")
    if [ -z "$decoded" ]; then
        return 1
    fi
    local exp=$(echo "$decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
    if [ -z "$exp" ]; then
        return 1
    fi
    local now=$(date +%s)
    if [ "$now" -gt "$exp" ]; then
        return 1
    fi
    return 0
}

exchange_api_key_for_token() {
    local api_key="$1"
    local response
    response=$(npcurl -s -X POST "${BASE_URL}/token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -d "{\"api_key\": \"$api_key\"}")
    local token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$token" ]; then
        echo "Error: Failed to exchange API key for token" >&2
        echo "Response: $response" >&2
        return 1
    fi
    echo "$token"
}

get_token_cache_file() {
    local api_key="$1"
    local key_hash=$(echo -n "$api_key" | md5 | cut -c1-8)
    echo "${TOKEN_CACHE_DIR}/.np-token-${key_hash}.cache"
}

get_valid_token() {
    # 1. Try NP_API_KEY environment variable (with token cache)
    if [ -n "${NP_API_KEY:-}" ]; then
        local cache_file=$(get_token_cache_file "$NP_API_KEY")
        if [ -f "$cache_file" ]; then
            local cached_token=$(cat "$cache_file")
            if is_jwt_valid "$cached_token"; then
                echo "$cached_token"
                return 0
            fi
            echo "[auth] Cached token expired, renewing from NP_API_KEY..." >&2
        else
            echo "[auth] No cached token found, exchanging NP_API_KEY for token..." >&2
        fi
        local new_token=$(exchange_api_key_for_token "$NP_API_KEY")
        if [ -n "$new_token" ]; then
            mkdir -p "$TOKEN_CACHE_DIR"
            echo "$new_token" > "$cache_file"
            echo "[auth] Token renewed and cached in $cache_file" >&2
            echo "$new_token"
            return 0
        fi
        echo "[auth] ERROR: Failed to exchange NP_API_KEY for token. Check that your API key is valid." >&2
        return 1
    fi

    # 2. Try NP_TOKEN environment variable (direct token, no cache)
    if [ -n "${NP_TOKEN:-}" ]; then
        if is_jwt_valid "$NP_TOKEN"; then
            echo "$NP_TOKEN"
            return 0
        fi
        echo "[auth] ERROR: NP_TOKEN is expired. Get a new token from Nullplatform UI > Profile > Copy personal access token." >&2
        return 1
    fi

    echo "[auth] ERROR: No authentication configured. Set one of these environment variables:" >&2
    echo "" >&2
    echo "  NP_API_KEY (recommended - never expires, token cached in ~/.claude/)" >&2
    echo "    export NP_API_KEY='your-api-key'" >&2
    echo "" >&2
    echo "  NP_TOKEN (bearer token - expires in ~24h)" >&2
    echo "    export NP_TOKEN='eyJ...'" >&2
    return 1
}

################################################################################
# Check Auth (detailed output like check_auth.sh)
################################################################################

check_auth() {
    echo "Checking np-developer-actions authentication..."
    echo ""

    local auth_valid=false
    local auth_source=""

    # 1. Try NP_API_KEY environment variable (with token cache)
    if [ -n "${NP_API_KEY:-}" ]; then
        echo "Found: NP_API_KEY environment variable"
        local cache_file=$(get_token_cache_file "$NP_API_KEY")
        if [ -f "$cache_file" ]; then
            echo "Found cached token: $cache_file"
            local token=$(cat "$cache_file")
            if is_jwt_valid "$token"; then
                local payload=$(echo "$token" | cut -d'.' -f2)
                local decoded=$(decode_base64 "$payload")
                local exp=$(echo "$decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
                local org_id=$(echo "$decoded" | grep -o '"@nullplatform\\/organization=[0-9]*"' | grep -o '[0-9]*')
                local now=$(date +%s)
                local exp_date=$(date -r "$exp" 2>/dev/null || echo "unknown")
                local remaining=$(( (exp - now) / 60 ))
                echo "  Organization ID: ${org_id:-unknown}"
                echo "  Expires at: $exp_date ($remaining minutes remaining)"
                auth_source="NP_API_KEY (cached token: $cache_file)"
                auth_valid=true
            else
                echo "  Cached token expired, exchanging API Key for new token..."
            fi
        fi
        if [ "$auth_valid" = false ]; then
            echo "  Validating API Key (exchanging for token)..."
            local response=$(npcurl -s -X POST "${BASE_URL}/token" \
                -H 'Content-Type: application/json' \
                -H 'Accept: application/json' \
                -d "{\"api_key\": \"$NP_API_KEY\"}" 2>&1)
            if echo "$response" | grep -q '"access_token"'; then
                local org_id=$(echo "$response" | grep -o '"organization_id":[0-9]*' | cut -d':' -f2)
                local access_token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
                echo "  API Key is valid"
                echo "  Organization ID: ${org_id:-unknown}"
                if [ -n "$access_token" ]; then
                    mkdir -p "$TOKEN_CACHE_DIR"
                    echo "$access_token" > "$cache_file"
                    echo "  Token cached in: $cache_file"
                fi
                auth_source="NP_API_KEY environment variable"
                auth_valid=true
            else
                echo "  ERROR: API Key validation failed"
                echo "  Response: $response"
            fi
        fi
    fi

    # 2. Try NP_TOKEN environment variable (direct token, no cache)
    if [ "$auth_valid" = false ] && [ -n "${NP_TOKEN:-}" ]; then
        echo "Found: NP_TOKEN environment variable"
        if is_jwt_valid "$NP_TOKEN"; then
            auth_source="NP_TOKEN environment variable"
            auth_valid=true
        fi
    fi

    echo ""
    if [ "$auth_valid" = true ]; then
        echo "Authentication configured via: $auth_source"
        exit 0
    else
        echo "ERROR: No valid authentication configured."
        echo ""
        echo "Configure authentication using ONE of these options:"
        echo ""
        echo "  Option 1: NP_API_KEY (recommended - never expires, token cached in ~/.claude/)"
        echo "    export NP_API_KEY='your-api-key'"
        echo ""
        echo "  Option 2: NP_TOKEN (bearer token - expires in ~24h)"
        echo "    export NP_TOKEN='eyJ...'"
        echo ""
        echo "  To get an API Key:"
        echo "    1. Go to Nullplatform UI -> Settings -> API Keys"
        echo "    2. Create new API Key with write permissions for the organization"
        exit 1
    fi
}

################################################################################
# Doc Functions
################################################################################

show_overview() {
    if [ -f "$DOCS_DIR/actions-overview.md" ]; then
        cat "$DOCS_DIR/actions-overview.md"
    else
        echo -e "${RED}Error: actions-overview.md not found in $DOCS_DIR${NC}"
        exit 1
    fi
}

search_actions() {
    local term="$1"

    if [[ -z "$term" ]]; then
        echo -e "${RED}Error: search-action requires a term${NC}"
        echo "Usage: action-api.sh search-action <term>"
        exit 1
    fi

    echo -e "${CYAN}Searching for actions matching '$term'...${NC}"
    echo ""

    local found=0
    for file in "$DOCS_DIR"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "actions-overview.md" ]] && continue

        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                action=$(echo "$line" | sed 's/## @action //')
                echo -e "${GREEN}$action${NC}"

                desc=$(grep -A2 "$line" "$file" | tail -n1 | head -c 100)
                if [[ -n "$desc" && ! "$desc" =~ ^## && ! "$desc" =~ ^### ]]; then
                    echo "  $desc"
                fi
                echo ""
                found=$((found + 1))
            fi
        done < <(grep -h "## @action" "$file" 2>/dev/null | grep -i "$term")
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}No actions found matching '$term'${NC}"
        echo ""
        echo "Try: action-api.sh search-action scope"
    else
        echo -e "${CYAN}Found $found action(s)${NC}"
    fi
}

describe_action() {
    local action="$1"

    if [[ -z "$action" ]]; then
        echo -e "${RED}Error: describe-action requires an action${NC}"
        echo "Usage: action-api.sh describe-action <action>"
        echo "Example: action-api.sh describe-action \"POST /scope\""
        exit 1
    fi

    local search_pattern="$action"

    for file in "$DOCS_DIR"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "actions-overview.md" ]] && continue

        if grep -q "## @action.*$search_pattern" "$file" 2>/dev/null; then
            awk -v pattern="$search_pattern" '
                BEGIN { printing = 0 }
                /^## @action/ {
                    if (printing) exit
                    if ($0 ~ pattern) {
                        printing = 1
                    }
                }
                printing { print }
            ' "$file"
            return 0
        fi
    done

    echo -e "${RED}Action '$action' not found${NC}"
    echo ""
    echo "Try searching first: action-api.sh search-action $(echo "$action" | awk '{print $NF}' | tr '/' ' ' | awk '{print $1}')"
    return 1
}

################################################################################
# Exec API (HTTP engine for write operations)
################################################################################

exec_api() {
    local method=""
    local data=""
    local endpoint=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --method)
                method="$2"
                shift 2
                ;;
            --data)
                data="$2"
                shift 2
                ;;
            *)
                endpoint="$1"
                shift
                ;;
        esac
    done

    # Validate endpoint
    if [ -z "$endpoint" ]; then
        echo -e "${RED}Error: endpoint required${NC}"
        echo "Usage: action-api.sh exec-api --method POST --data '{...}' \"/endpoint\""
        exit 1
    fi

    # Validate method
    if [ -z "$method" ]; then
        echo -e "${RED}Error: --method is required (POST, PATCH, PUT, DELETE)${NC}"
        exit 1
    fi

    case "$method" in
        POST|PATCH|PUT|DELETE) ;;
        GET)
            echo -e "${RED}Error: GET is not supported. Use /np-api fetch-api for read operations.${NC}"
            exit 1
            ;;
        *)
            echo -e "${RED}Error: Unsupported method '$method'. Use POST, PATCH, PUT, or DELETE.${NC}"
            exit 1
            ;;
    esac

    # Validate data for methods that need it
    if [[ "$method" != "DELETE" && -z "$data" ]]; then
        echo -e "${RED}Error: --data is required for $method requests${NC}"
        exit 1
    fi

    # Get auth token
    local bearer_token
    bearer_token=$(get_valid_token)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Build URL
    local url
    if [[ "$endpoint" == http* ]]; then
        url="$endpoint"
    else
        endpoint="${endpoint#/}"
        url="${BASE_URL}/${endpoint}"
    fi

    # Execute request with HTTP status capture
    local response
    local curl_args=(-s -w "\n%{http_code}" -H "Authorization: Bearer $bearer_token" -H "Content-Type: application/json")

    if [ "$method" = "DELETE" ] && [ -z "$data" ]; then
        response=$(npcurl "${curl_args[@]}" -X DELETE "$url")
    else
        response=$(npcurl "${curl_args[@]}" -X "$method" -d "$data" "$url")
    fi

    # Extract HTTP status code from last line
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    # Output body
    echo "$body"

    # Exit with error if HTTP status indicates failure
    if [[ "$http_code" -ge 400 ]]; then
        echo "" >&2
        echo -e "${RED}Error: HTTP $http_code${NC}" >&2
        exit 1
    fi
}

################################################################################
# Help
################################################################################

show_help() {
    echo -e "${CYAN}action-api.sh - Nullplatform Developer Actions${NC}"
    echo ""
    echo -e "${YELLOW}Write operations only (POST/PATCH/PUT/DELETE).${NC}"
    echo -e "${YELLOW}For reads, use: /np-api fetch-api${NC}"
    echo ""
    echo "Usage:"
    echo "  action-api.sh                              Show available actions"
    echo "  action-api.sh check-auth                   Verify authentication"
    echo "  action-api.sh search-action <term>         Search actions by term"
    echo "  action-api.sh describe-action <action>     Show full action docs"
    echo "  action-api.sh exec-api <args>              Execute write request"
    echo ""
    echo "Examples:"
    echo "  action-api.sh search-action scope"
    echo "  action-api.sh describe-action \"POST /scope\""
    echo "  action-api.sh exec-api --method POST --data '{...}' \"/scope\""
}

################################################################################
# Main Router
################################################################################

case "${1:-}" in
    "")
        show_overview
        ;;
    "check-auth")
        check_auth
        ;;
    "search-action")
        search_actions "${2:-}"
        ;;
    "describe-action")
        describe_action "${2:-}"
        ;;
    "exec-api")
        shift
        exec_api "$@"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
