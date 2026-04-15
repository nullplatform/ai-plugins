#!/bin/bash
#
# check_auth.sh - Validate nullplatform authentication is configured and working
#
# Usage:
#   ./check_auth.sh
#
# Exit codes:
#   0 - Authentication configured and valid
#   1 - No authentication found or invalid
#
# Authentication precedence:
#   1. NP_API_KEY environment variable (exchanges for token, caches in ~/.claude/)
#   2. NP_TOKEN environment variable (direct bearer token, no cache)

# Configuration
BASE_URL="https://api.nullplatform.com"
TOKEN_CACHE_DIR="$HOME/.claude"

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

# Function to check if JWT token is expired and show info
# Returns 0 if valid, 1 if expired or invalid
check_jwt_token() {
    local token="$1"
    local source="$2"

    # Check if it's a JWT (has 3 parts separated by dots)
    if [[ "$token" != *"."*"."* ]]; then
        return 1
    fi

    # Extract payload (second part)
    local payload=$(echo "$token" | cut -d'.' -f2)
    local decoded=$(decode_base64 "$payload")

    if [ -z "$decoded" ]; then
        echo "WARNING: Could not decode JWT token"
        return 1
    fi

    # Extract exp and organization
    local exp=$(echo "$decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
    local org_id=$(echo "$decoded" | grep -o '"@nullplatform\\/organization=[0-9]*"' | grep -o '[0-9]*')

    if [ -z "$exp" ]; then
        echo "WARNING: Could not extract expiration from JWT"
        return 1
    fi

    local now=$(date +%s)

    if [ "$now" -gt "$exp" ]; then
        local exp_date=$(date -r "$exp" 2>/dev/null || date -d "@$exp" 2>/dev/null || echo "unknown")
        echo ""
        echo "ERROR: JWT token is EXPIRED"
        echo ""
        echo "  Source: $source"
        echo "  Organization ID: ${org_id:-unknown}"
        echo "  Expired at: $exp_date"
        echo "  Current time: $(date)"
        return 1
    fi

    # Token is valid - show info
    local exp_date=$(date -r "$exp" 2>/dev/null || date -d "@$exp" 2>/dev/null || echo "unknown")
    local remaining=$(( (exp - now) / 60 ))
    echo "  Organization ID: ${org_id:-unknown}"
    echo "  Expires at: $exp_date ($remaining minutes remaining)"

    # Auto-refresh if less than 5 minutes remaining and NP_API_KEY is available
    if [ "$remaining" -lt 5 ] && [ -n "${NP_API_KEY:-}" ]; then
        echo ""
        echo "  Token near expiry, auto-refreshing from NP_API_KEY..."
        local response=$(curl -s -X POST "${BASE_URL}/token" \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            -d "{\"api_key\": \"$NP_API_KEY\"}" 2>&1)
        local new_token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$new_token" ]; then
            local cache_file=$(get_token_cache_file "$NP_API_KEY")
            mkdir -p "$TOKEN_CACHE_DIR"
            echo "$new_token" > "$cache_file"
            echo "  Token refreshed and cached in: $cache_file"
            # Show new expiration
            local new_payload=$(echo "$new_token" | cut -d'.' -f2)
            local new_decoded=$(decode_base64 "$new_payload")
            local new_exp=$(echo "$new_decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
            if [ -n "$new_exp" ]; then
                local new_exp_date=$(date -r "$new_exp" 2>/dev/null || date -d "@$new_exp" 2>/dev/null || echo "unknown")
                local new_remaining=$(( (new_exp - now) / 60 ))
                echo "  New expiration: $new_exp_date ($new_remaining minutes remaining)"
            fi
        else
            echo "  WARNING: Auto-refresh failed, continuing with current token"
        fi
    fi

    return 0
}

# Function to get token cache file path based on API key hash
get_token_cache_file() {
    local api_key="$1"
    local key_hash=$(echo -n "$api_key" | md5 | cut -c1-8)
    echo "${TOKEN_CACHE_DIR}/.np-token-${key_hash}.cache"
}

# Function to validate API Key by exchanging it for a token
validate_api_key() {
    local api_key="$1"
    local response

    echo "  Validating API Key (exchanging for token)..."

    response=$(curl -s -X POST "${BASE_URL}/token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -d "{\"api_key\": \"$api_key\"}" 2>&1)

    # Check if we got an access_token
    if echo "$response" | grep -q '"access_token"'; then
        local org_id=$(echo "$response" | grep -o '"organization_id":[0-9]*' | cut -d':' -f2)
        local expires_ms=$(echo "$response" | grep -o '"token_expires_at":[0-9]*' | cut -d':' -f2)

        echo "  API Key is valid"
        echo "  Organization ID: ${org_id:-unknown}"

        if [ -n "$expires_ms" ]; then
            local expires_s=$((expires_ms / 1000))
            local exp_date=$(date -r "$expires_s" 2>/dev/null || date -d "@$expires_s" 2>/dev/null || echo "unknown")
            local now=$(date +%s)
            local remaining=$(( (expires_s - now) / 60 ))
            echo "  Token expires: $exp_date ($remaining minutes)"
        fi

        # Cache the token for future use
        local access_token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$access_token" ]; then
            local cache_file=$(get_token_cache_file "$api_key")
            mkdir -p "$TOKEN_CACHE_DIR"
            echo "$access_token" > "$cache_file"
            echo "  Token cached in: $cache_file"
        fi

        return 0
    else
        echo ""
        echo "ERROR: API Key validation failed"
        echo "Response: $response"
        return 1
    fi
}

# On macOS, if npcurl doesn't exist, use curl as fallback
if [[ "$(uname)" == "Darwin" ]] && ! command -v npcurl &> /dev/null; then
    npcurl() { curl "$@"; }
fi

# Main logic
echo "Checking Nullplatform authentication..."
echo ""

AUTH_SOURCE=""
AUTH_VALID=false

# 1. Try NP_API_KEY environment variable (with token cache)
if [ -n "${NP_API_KEY:-}" ]; then
    echo "Found: NP_API_KEY environment variable"
    local_cache_file=$(get_token_cache_file "$NP_API_KEY")
    if [ -f "$local_cache_file" ]; then
        echo "Found cached token: $local_cache_file"
        cached_token=$(cat "$local_cache_file")
        if check_jwt_token "$cached_token" "NP_API_KEY (cached token: $local_cache_file)"; then
            AUTH_SOURCE="NP_API_KEY (cached token: $local_cache_file)"
            AUTH_VALID=true
        else
            echo "  Cached token expired, exchanging API Key for new token..."
        fi
    fi
    if [ "$AUTH_VALID" = false ]; then
        if validate_api_key "$NP_API_KEY"; then
            AUTH_SOURCE="NP_API_KEY environment variable"
            AUTH_VALID=true
        fi
    fi
fi

# 2. Try NP_TOKEN environment variable (direct token, no cache)
if [ "$AUTH_VALID" = false ] && [ -n "${NP_TOKEN:-}" ]; then
    echo "Found: NP_TOKEN environment variable"
    if check_jwt_token "$NP_TOKEN" "NP_TOKEN env var"; then
        AUTH_SOURCE="NP_TOKEN environment variable"
        AUTH_VALID=true
    else
        echo "  Token expired or invalid"
        echo ""
    fi
fi

# Final result
echo ""
if [ "$AUTH_VALID" = true ]; then
    echo "Authentication configured via: $AUTH_SOURCE"
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
    echo "    1. Go to Nullplatform UI -> Platform Settings -> API Keys"
    echo "    2. Create new API Key with permissions for the organization"
    exit 1
fi
