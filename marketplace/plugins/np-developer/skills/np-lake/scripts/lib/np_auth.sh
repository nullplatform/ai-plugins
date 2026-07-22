#!/bin/bash
#
# np_auth.sh - Nullplatform authentication helpers (sourced library).
#
# This file is NOT intended to be executed directly. Source it from a script:
#
#     source "${SCRIPT_DIR}/lib/np_auth.sh"
#
# Exposes:
#   resolve_http_client  -> sets HTTP_CLIENT global (npcurl or curl)
#   get_valid_token      -> prints a valid Bearer token on stdout
#                           exit 0 on success, 1 on failure
#
# Token precedence:
#   1. NP_API_KEY (exchanged for a JWT, cached in ~/.claude/)
#   2. NP_TOKEN   (direct personal JWT, ~24h expiry)

NP_BASE_URL="${NP_BASE_URL:-https://api.nullplatform.com}"
NP_TOKEN_CACHE_DIR="$HOME/.claude"

resolve_http_client() {
    if command -v npcurl &>/dev/null; then
        HTTP_CLIENT="npcurl"
    elif command -v curl &>/dev/null; then
        HTTP_CLIENT="curl"
    else
        echo "[auth] ERROR: No HTTP client available (tried npcurl, curl)" >&2
        return 1
    fi
    return 0
}

_np_decode_base64_url() {
    local input="$1"
    local pad=$((4 - ${#input} % 4))
    if [ $pad -ne 4 ]; then
        input="${input}$(printf '=%.0s' $(seq 1 $pad))"
    fi
    echo "$input" | tr '_-' '/+' | base64 -d 2>/dev/null
}

_np_is_jwt_valid() {
    local token="$1"
    [[ "$token" != *"."*"."* ]] && return 1

    local payload
    payload=$(echo "$token" | cut -d'.' -f2)

    local decoded
    decoded=$(_np_decode_base64_url "$payload")
    [ -z "$decoded" ] && return 1

    local exp
    exp=$(echo "$decoded" | grep -o '"exp":[0-9]*' | cut -d':' -f2)
    [ -z "$exp" ] && return 1

    local now
    now=$(date +%s)
    [ "$now" -gt "$exp" ] && return 1

    return 0
}

_np_token_cache_file() {
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
    echo "${NP_TOKEN_CACHE_DIR}/.np-token-${key_hash}.cache"
}

_np_exchange_api_key() {
    local api_key="$1"
    resolve_http_client || return 1

    local response
    response=$("$HTTP_CLIENT" -s -X POST "${NP_BASE_URL}/token" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -d "{\"api_key\": \"$api_key\"}")

    local token
    token=$(echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$token" ]; then
        echo "[auth] ERROR: Failed to exchange NP_API_KEY for token." >&2
        echo "[auth] Response: $response" >&2
        return 1
    fi

    echo "$token"
}

get_valid_token() {
    if [ -n "${NP_API_KEY:-}" ]; then
        local cache_file
        cache_file=$(_np_token_cache_file "$NP_API_KEY") || return 1

        if [ -f "$cache_file" ]; then
            local cached
            cached=$(cat "$cache_file")
            if _np_is_jwt_valid "$cached"; then
                echo "$cached"
                return 0
            fi
            echo "[auth] Cached token expired, renewing from NP_API_KEY..." >&2
        else
            echo "[auth] No cached token found, exchanging NP_API_KEY for token..." >&2
        fi

        local new_token
        new_token=$(_np_exchange_api_key "$NP_API_KEY") || return 1
        mkdir -p "$NP_TOKEN_CACHE_DIR"
        echo "$new_token" > "$cache_file"
        echo "[auth] Token renewed and cached in $cache_file" >&2
        echo "$new_token"
        return 0
    fi

    if [ -n "${NP_TOKEN:-}" ]; then
        if _np_is_jwt_valid "$NP_TOKEN"; then
            echo "$NP_TOKEN"
            return 0
        fi
        echo "[auth] ERROR: NP_TOKEN is expired. Get a new one from the Nullplatform UI > Profile > Copy personal access token." >&2
        return 1
    fi

    echo "[auth] ERROR: No authentication configured. Set one of:" >&2
    echo "" >&2
    echo "  NP_API_KEY (recommended - never expires, token cached in ~/.claude/)" >&2
    echo "    export NP_API_KEY='your-api-key'" >&2
    echo "" >&2
    echo "  NP_TOKEN (personal JWT - expires in ~24h)" >&2
    echo "    export NP_TOKEN='eyJ...'" >&2
    return 1
}
