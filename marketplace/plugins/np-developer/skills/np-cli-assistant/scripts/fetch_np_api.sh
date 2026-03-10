#!/bin/bash
#
# fetch_np_api.sh - Fetch nullplatform API endpoints with authentication
#
# Usage:
#   ./fetch_np_api.sh <endpoint>
#
# Examples:
#   ./fetch_np_api.sh "/notification/84147783-fc53-404f-beff-2d0172d61baa"
#   ./fetch_np_api.sh "/application/441069822"
#   ./fetch_np_api.sh "/deployment/123456?include_messages=true"
#
# Authentication precedence (environment variables only):
#   1. NULLPLATFORM_API_KEY (same variable the np CLI uses)
#   2. NP_API_KEY (legacy alias)
#   3. NP_TOKEN (JWT access token)

set -e

# Source shell profile to pick up env vars in non-interactive shells
source ~/.zshrc > /dev/null 2>&1 || source ~/.bashrc > /dev/null 2>&1 || true

# Configuration
BASE_URL="https://api.nullplatform.com"

ENDPOINT="$1"

if [ -z "$ENDPOINT" ]; then
    echo "Error: endpoint required"
    echo "Usage: $0 <endpoint>"
    echo "Example: $0 /application/441069822"
    exit 1
fi

# Require curl
if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is not available"
    exit 1
fi

# Function to decode base64 (handles URL-safe base64)
decode_base64() {
    local input="$1"
    local pad=$((4 - ${#input} % 4))
    if [ $pad -ne 4 ]; then
        input="${input}$(printf '=%.0s' $(seq 1 $pad))"
    fi
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

# Function to check if JWT token is expired
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

# Function to exchange API Key for Access Token
exchange_api_key_for_token() {
    local api_key="$1"
    local response

    response=$(curl -s -X POST "${BASE_URL}/token" \
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

# Function to get a valid Bearer token
get_valid_token() {
    # 1. Try NULLPLATFORM_API_KEY (same variable the np CLI uses — preferred)
    if [ -n "$NULLPLATFORM_API_KEY" ]; then
        local new_token=$(exchange_api_key_for_token "$NULLPLATFORM_API_KEY")
        if [ -n "$new_token" ]; then
            echo "$new_token"
            return 0
        fi
    fi

    # 2. Try NP_API_KEY (legacy alias)
    if [ -n "$NP_API_KEY" ]; then
        local new_token=$(exchange_api_key_for_token "$NP_API_KEY")
        if [ -n "$new_token" ]; then
            echo "$new_token"
            return 0
        fi
    fi

    # 3. Try NP_TOKEN (JWT access token)
    if [ -n "$NP_TOKEN" ]; then
        if is_jwt_valid "$NP_TOKEN"; then
            echo "$NP_TOKEN"
            return 0
        else
            echo "Error: NP_TOKEN is expired or invalid" >&2
            return 1
        fi
    fi

    echo "Error: No valid authentication found." >&2
    echo "" >&2
    echo "Run check_auth.sh for setup instructions, or configure one of:" >&2
    echo "  1. export NULLPLATFORM_API_KEY='your-api-key'  (recommended)" >&2
    echo "  2. export NP_API_KEY='your-api-key'" >&2
    echo "  3. export NP_TOKEN='your-jwt-token'" >&2
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
    ENDPOINT="${ENDPOINT#/}"
    URL="${BASE_URL}/${ENDPOINT}"
fi

# Make GET request
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $BEARER_TOKEN" "$URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Handle response
case $HTTP_CODE in
    200|201|204)
        echo "$BODY"
        exit 0
        ;;
    401)
        echo "ERROR: Authentication Failed (HTTP 401)" >&2
        echo "" >&2
        echo "Possible causes:" >&2
        echo "  - Token expired (check with scripts/check_auth.sh)" >&2
        echo "  - Resource belongs to a different organization than your token" >&2
        echo "  - API key was revoked or invalidated" >&2
        echo "" >&2
        echo "Your token's org ID may differ from the resource's NRN organization." >&2
        echo "$BODY" >&2
        exit 1
        ;;
    403)
        echo "ERROR: Forbidden (HTTP 403) - Insufficient permissions" >&2
        echo "$BODY" >&2
        exit 1
        ;;
    404)
        echo "ERROR: Not Found (HTTP 404) - Resource or endpoint does not exist" >&2
        echo "Endpoint: $URL" >&2
        echo "$BODY" >&2
        exit 1
        ;;
    *)
        echo "ERROR: HTTP $HTTP_CODE" >&2
        echo "Endpoint: $URL" >&2
        echo "$BODY" >&2
        exit 1
        ;;
esac
