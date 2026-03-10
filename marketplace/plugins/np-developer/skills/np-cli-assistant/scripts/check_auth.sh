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
# Authentication precedence (environment variables only):
#   1. NULLPLATFORM_API_KEY (same variable the np CLI uses)
#   2. NP_API_KEY (legacy alias)
#   3. NP_TOKEN (JWT access token)

# Configuration
BASE_URL="https://api.nullplatform.com"

# Source shell profile to pick up env vars in non-interactive shells
source ~/.zshrc > /dev/null 2>&1 || source ~/.bashrc > /dev/null 2>&1 || true

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

# Function to validate token with API call
validate_token_with_api() {
    local token="$1"
    local response

    response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $token" "${BASE_URL}/organization?limit=1" 2>&1)

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        return 0
    elif [ "$http_code" = "403" ]; then
        echo "  WARNING: Token is valid but has restricted permissions (HTTP 403)"
        return 0
    else
        return 1
    fi
}

# Function to check if JWT token is expired and show info
check_jwt_token() {
    local token="$1"
    local source="$2"

    if [[ "$token" != *"."*"."* ]]; then
        return 1
    fi

    local payload=$(echo "$token" | cut -d'.' -f2)
    local decoded=$(decode_base64 "$payload")

    if [ -z "$decoded" ]; then
        echo "WARNING: Could not decode JWT token, testing with API..."
        if validate_token_with_api "$token"; then
            echo "  Token validated successfully via API"
            return 0
        else
            echo "  Token validation failed"
            return 1
        fi
    fi

    local exp=$(echo "$decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)

    local org_id=$(echo "$decoded" | grep -o '"@nullplatform\\/organization=[0-9]*"' | grep -o '[0-9]*')
    if [ -z "$org_id" ]; then
        org_id=$(echo "$decoded" | grep -o '@nullplatform\\/organization=[0-9]*' | grep -o '[0-9]*' | head -1)
    fi
    if [ -z "$org_id" ]; then
        org_id=$(echo "$decoded" | grep -o '@nullplatform/organization=[0-9]*' | grep -o '[0-9]*' | head -1)
    fi

    if [ -z "$exp" ]; then
        echo "WARNING: Could not extract expiration from JWT, testing with API..."
        if validate_token_with_api "$token"; then
            echo "  Token validated successfully via API"
            return 0
        else
            echo "  Token validation failed"
            return 1
        fi
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

    local exp_date=$(date -r "$exp" 2>/dev/null || date -d "@$exp" 2>/dev/null || echo "unknown")
    local remaining=$(( (exp - now) / 60 ))
    echo "  Organization ID: ${org_id:-unknown}"
    echo "  Expires at: $exp_date ($remaining minutes remaining)"
    return 0
}

# Function to validate API Key by exchanging it for a token
validate_api_key() {
    local api_key="$1"
    local source="$2"

    echo "  Validating API Key from $source..."

    local response
    response=$(curl -s -X POST "${BASE_URL}/token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -d "{\"api_key\": \"$api_key\"}" 2>&1)

    if echo "$response" | grep -q '"access_token"'; then
        VALIDATED_ORG_ID=$(echo "$response" | grep -o '"organization_id":[0-9]*' | cut -d':' -f2)
        local expires_ms=$(echo "$response" | grep -o '"token_expires_at":[0-9]*' | cut -d':' -f2)

        echo "  API Key is valid"
        echo "  Organization ID: ${VALIDATED_ORG_ID:-unknown}"

        if [ -n "$expires_ms" ]; then
            local expires_s=$((expires_ms / 1000))
            local exp_date=$(date -r "$expires_s" 2>/dev/null || date -d "@$expires_s" 2>/dev/null || echo "unknown")
            local now=$(date +%s)
            local remaining=$(( (expires_s - now) / 60 ))
            echo "  Token expires: $exp_date ($remaining minutes)"
        fi

        return 0
    else
        echo ""
        echo "ERROR: API Key validation failed"
        echo "Response: $response"
        return 1
    fi
}

# Main logic
echo "Checking nullplatform authentication..."
echo ""

AUTH_SOURCE=""
AUTH_VALID=false
VALIDATED_ORG_ID=""

# 1. Check NULLPLATFORM_API_KEY (same variable the np CLI uses — preferred)
if [ "$AUTH_VALID" = false ] && [ -n "$NULLPLATFORM_API_KEY" ]; then
    echo "Found: NULLPLATFORM_API_KEY environment variable"
    if validate_api_key "$NULLPLATFORM_API_KEY" "NULLPLATFORM_API_KEY"; then
        AUTH_SOURCE="NULLPLATFORM_API_KEY environment variable"
        AUTH_VALID=true
    fi
fi

# 2. Check NP_API_KEY (legacy alias)
if [ "$AUTH_VALID" = false ] && [ -n "$NP_API_KEY" ]; then
    echo "Found: NP_API_KEY environment variable"
    if validate_api_key "$NP_API_KEY" "NP_API_KEY"; then
        AUTH_SOURCE="NP_API_KEY environment variable"
        AUTH_VALID=true
    fi
fi

# 3. Check NP_TOKEN (JWT access token)
if [ "$AUTH_VALID" = false ] && [ -n "$NP_TOKEN" ]; then
    echo "Found: NP_TOKEN environment variable"
    if check_jwt_token "$NP_TOKEN" "NP_TOKEN env var"; then
        AUTH_SOURCE="NP_TOKEN environment variable"
        AUTH_VALID=true
    fi
fi

# Warn if NP_TOKEN is set and expired/invalid — it poisons the CLI even when API key is valid
if [ "$AUTH_VALID" = true ] && [ -n "$NP_TOKEN" ] && [[ "$AUTH_SOURCE" != *"NP_TOKEN"* ]]; then
    # Auth succeeded via API key, but NP_TOKEN is also set — check if it's expired
    if ! check_jwt_token "$NP_TOKEN" "NP_TOKEN env var" > /dev/null 2>&1; then
        echo ""
        echo "WARNING: NP_TOKEN is set but expired or invalid."
        echo "  The np CLI prioritizes NP_TOKEN over NULLPLATFORM_API_KEY."
        echo "  This will cause 401 errors even though the API key is valid."
        echo ""
        echo "  Fix: Remove the NP_TOKEN line from your shell profile:"
        echo "    sed -i '' '/export NP_TOKEN/d' ~/.zshrc  # macOS"
        echo "    sed -i '/export NP_TOKEN/d' ~/.bashrc    # Linux"
        echo "  Then run: source ~/.zshrc"
    fi
fi

# CLI smoke test — verify the np CLI can actually authenticate (not just the API)
if [ "$AUTH_VALID" = true ] && command -v np &> /dev/null; then
    echo ""
    echo "Testing CLI access..."

    # Determine which credential to pass inline to the CLI smoke test.
    # Non-interactive shells (e.g., Claude Code) don't load ~/.zshrc, so
    # the CLI won't see env vars. Passing the credential inline mirrors
    # real usage and avoids false warnings.
    cli_auth_flag=""
    if [ -n "$NULLPLATFORM_API_KEY" ]; then
        cli_auth_flag="--api-key $NULLPLATFORM_API_KEY"
    elif [ -n "$NP_API_KEY" ]; then
        cli_auth_flag="--api-key $NP_API_KEY"
    elif [ -n "$NP_TOKEN" ]; then
        cli_auth_flag="--access-token $NP_TOKEN"
    fi

    if [ -n "$VALIDATED_ORG_ID" ]; then
        CLI_OUTPUT=$(np organization read --id "$VALIDATED_ORG_ID" --format json $cli_auth_flag 2>&1)
    else
        CLI_OUTPUT=$(np organization read --format json $cli_auth_flag 2>&1)
    fi
    CLI_EXIT=$?
    if [ $CLI_EXIT -ne 0 ]; then
        echo "  WARNING: API credentials are valid but the np CLI returned an error."
        echo "  This may indicate a CLI version issue or network problem."
        echo "  CLI output: $CLI_OUTPUT"
    else
        echo "  CLI access verified."
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
    echo "  RECOMMENDED: API Key in shell profile (one-time setup, never expires)"
    echo "  =================================================================="
    echo "  Add this line to your ~/.zshrc (or ~/.bashrc):"
    echo ""
    echo "    export NULLPLATFORM_API_KEY='your-api-key'"
    echo ""
    echo "  Then restart your terminal or run: source ~/.zshrc"
    echo ""
    echo "  ALTERNATIVE: JWT Token (expires in ~24h)"
    echo "  ========================================="
    echo "  export NP_TOKEN='your-jwt-token'"
    echo ""
    echo "  To get a token:"
    echo "    1. Go to nullplatform UI"
    echo "    2. Click your profile (top right)"
    echo "    3. Click 'Copy personal access token'"
    exit 1
fi
