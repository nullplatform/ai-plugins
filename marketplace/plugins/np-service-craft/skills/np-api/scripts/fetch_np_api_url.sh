#!/bin/bash
#
# fetch_np_api_url.sh - Fetch Nullplatform API endpoints with authentication
#
# Usage:
#   ./fetch_np_api_url.sh <endpoint> [output_file]
#
# Examples:
#   ./fetch_np_api_url.sh "/application/441069822"
#   ./fetch_np_api_url.sh "/application/441069822?include_messages=true" app.json
#   ./fetch_np_api_url.sh "/deployment/123456?include_messages=true"
#
# Authentication precedence:
#   1. NP_API_KEY environment variable (exchanges for token, caches in ~/.claude/)
#   2. NP_TOKEN environment variable (direct bearer token, no cache)

set -e

# Configuration
BASE_URL="https://api.nullplatform.com"
TOKEN_CACHE_DIR="$HOME/.claude"

# Endpoints (after stripping leading "/" and query string) where modifying
# methods (POST/PUT/PATCH/DELETE) are allowed. Each entry is a bash case glob.
# Add new entries here when exposing new mutable endpoints to skills.
ALLOWED_MODIFY=(
    "controlplane/agent_command"
    "notification/*/resend"
    "governance/action_item"
    "governance/action_item/*"
    "governance/action_item_category"
    "governance/action_item_category/*"
)

is_modify_allowed() {
    local path="$1"
    for allowed in "${ALLOWED_MODIFY[@]}"; do
        # shellcheck disable=SC2254
        case "$path" in
            $allowed) return 0 ;;
        esac
    done
    return 1
}

# Parse arguments
METHOD="GET"
DATA=""
ENDPOINT=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --method)
            METHOD="$2"
            shift 2
            ;;
        --data)
            DATA="$2"
            shift 2
            ;;
        *)
            if [ -z "$ENDPOINT" ]; then
                ENDPOINT="$1"
            else
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Check if endpoint is provided
if [ -z "$ENDPOINT" ]; then
    echo "Error: endpoint required"
    echo "Usage: $0 [--method GET|POST|PUT|PATCH|DELETE] [--data <json>] <endpoint> [output_file]"
    echo "Example: $0 /application/441069822"
    echo "Example: $0 --method PATCH --data '{\"status\":\"resolved\"}' /governance/action_item/abc123"
    exit 1
fi

# Validate method + endpoint
case "$METHOD" in
    GET|HEAD)
        ;; # always allowed
    POST|PUT|PATCH|DELETE)
        ENDPOINT_PATH="${ENDPOINT#/}"
        ENDPOINT_PATH="${ENDPOINT_PATH%%\?*}"  # Remove query string
        if ! is_modify_allowed "$ENDPOINT_PATH"; then
            echo "Error: $METHOD method is only allowed for endpoints matching:" >&2
            for allowed in "${ALLOWED_MODIFY[@]}"; do
                echo "  /${allowed}" >&2
            done
            exit 1
        fi
        if [ "$METHOD" != "DELETE" ] && [ -z "$DATA" ]; then
            echo "Error: --data is required for $METHOD requests" >&2
            exit 1
        fi
        ;;
    *)
        echo "Error: unsupported method: $METHOD" >&2
        exit 1
        ;;
esac

# If npcurl doesn't exist, use curl as fallback
if ! command -v npcurl &> /dev/null; then
    npcurl() { curl "$@"; }
fi

# Function to decode base64 (handles URL-safe base64)
decode_base64() {
    local input="$1"
    # Add padding if needed
    local pad=$((4 - ${#input} % 4))
    if [ $pad -ne 4 ]; then
        input="${input}$(printf '=%.0s' $(seq 1 $pad))"
    fi
    # Replace URL-safe characters
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

# Function to check if JWT token is expired
# Returns 0 if valid, 1 if expired or invalid
is_jwt_valid() {
    local token="$1"

    # Check if it's a JWT (has 3 parts separated by dots)
    if [[ "$token" != *"."*"."* ]]; then
        return 1
    fi

    # Extract payload (second part)
    local payload=$(echo "$token" | cut -d'.' -f2)
    local decoded=$(decode_base64 "$payload")

    if [ -z "$decoded" ]; then
        return 1
    fi

    # Extract exp
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

# Function to exchange API Key for Access Token
exchange_api_key_for_token() {
    local api_key="$1"
    local response

    response=$(npcurl -s -X POST "${BASE_URL}/token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -d "{\"api_key\": \"$api_key\"}")

    # Extract access_token from response
    local token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$token" ]; then
        echo "Error: Failed to exchange API key for token" >&2
        echo "Response: $response" >&2
        return 1
    fi

    echo "$token"
}

# Function to get a valid Bearer token
# Handles precedence and caching
get_token_cache_file() {
    local api_key="$1"
    local key_hash
    if command -v md5 &>/dev/null; then
        key_hash=$(echo -n "$api_key" | md5 | cut -c1-8)
    elif command -v md5sum &>/dev/null; then
        key_hash=$(echo -n "$api_key" | md5sum | cut -c1-8)
    else
        echo "[auth] ERROR: Neither 'md5' nor 'md5sum' found. Install coreutils." >&2
        return 1
    fi
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

# Get valid token
BEARER_TOKEN=$(get_valid_token)
if [ $? -ne 0 ]; then
    exit 1
fi

# Build URL
if [[ "$ENDPOINT" == http* ]]; then
    URL="$ENDPOINT"
else
    # Remove leading slash if present
    ENDPOINT="${ENDPOINT#/}"
    URL="${BASE_URL}/${ENDPOINT}"
fi

# Make request
CURL_ARGS=(-s -X "$METHOD" -H "Authorization: Bearer $BEARER_TOKEN")

case "$METHOD" in
    POST|PUT|PATCH)
        CURL_ARGS+=(-H "Content-Type: application/json" -d "$DATA")
        ;;
    DELETE)
        # DELETE may or may not carry a body; forward if provided
        if [ -n "$DATA" ]; then
            CURL_ARGS+=(-H "Content-Type: application/json" -d "$DATA")
        fi
        ;;
esac

if [ -n "$OUTPUT_FILE" ]; then
    npcurl "${CURL_ARGS[@]}" "$URL" > "$OUTPUT_FILE"
    echo "Response saved to: $OUTPUT_FILE"
else
    npcurl "${CURL_ARGS[@]}" "$URL"
fi
