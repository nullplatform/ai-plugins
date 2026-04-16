#!/bin/bash
#
# ch_query.sh - Execute Customer Lake queries via np-api delegation.
#
# Usage:
#   ./ch_query.sh "SELECT * FROM table WHERE ..."
#   ./ch_query.sh "SELECT * FROM table" output.json
#   ./ch_query.sh --file query.sql
#   ./ch_query.sh --file query.sql output.json
#   ./ch_query.sh --format pretty "SELECT * FROM table LIMIT 10"
#   ./ch_query.sh --format tsv "SELECT * FROM table LIMIT 10"
#   ./ch_query.sh --param entity=deployment "SELECT count() FROM audit_events WHERE entity = {entity:String}"
#
# Parameters:
#   Use {name:Type} placeholders in your SQL query and pass values with --param name=value.
#   Each --param flag maps to a ?param_name=value query string in the request URL.
#
# SECURITY: This script enforces read-only queries (SELECT, WITH, DESCRIBE, SHOW, EXPLAIN).
# Authentication, token exchange, and caching are delegated to np-api.
#
# Endpoint: POST https://api.nullplatform.com/data/lake/query

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Resolve the np-api wrapper (required)
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    NP_API="${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NP_API="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"
fi

if [ ! -x "$NP_API" ]; then
    echo -e "${RED}Error: np-api fetch script not found at $NP_API${NC}" >&2
    echo "Make sure the np-api skill is installed alongside np-lake." >&2
    exit 1
fi

LAKE_PATH="/data/lake/query"

error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

validate_read_only() {
    local query="$1"
    local cleaned
    cleaned=$(echo "$query" | sed 's/^[[:space:]]*//' | sed '/^--/d' | sed '/^$/d')
    local first_keyword
    first_keyword=$(echo "$cleaned" | head -1 | awk '{print toupper($1)}')
    case "$first_keyword" in
        SELECT|WITH|DESCRIBE|DESC|SHOW|EXPLAIN) return 0 ;;
        *)
            error_exit "SECURITY: Only read-only queries are allowed.

Blocked keyword: $first_keyword

Allowed query types:
  - SELECT ... FROM ...
  - WITH ... SELECT ...
  - DESCRIBE TABLE ...  (alias: DESC)
  - SHOW ...            (e.g. SHOW TABLES, SHOW CREATE TABLE)
  - EXPLAIN ..."
            ;;
    esac
}

QUERY=""
OUTPUT_FILE=""
FROM_FILE=false
OUTPUT_FORMAT="json"
QUERY_PARAMS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --file|-f)
            FROM_FILE=true
            shift
            [ -z "$1" ] && error_exit "--file requires a filename argument"
            QUERY_FILE="$1"
            shift
            ;;
        --format)
            shift
            [ -z "$1" ] && error_exit "--format requires a format argument (json, pretty, tsv)"
            OUTPUT_FORMAT="$1"
            shift
            ;;
        --param|-p)
            shift
            [ -z "$1" ] && error_exit "--param requires a name=value argument"
            if ! echo "$1" | grep -q "="; then
                error_exit "--param value must be in name=value format (got: $1)"
            fi
            QUERY_PARAMS+=("$1")
            shift
            ;;
        *)
            if [ -z "$QUERY" ]; then
                QUERY="$1"
            else
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

if [ "$FROM_FILE" = true ]; then
    [ -f "$QUERY_FILE" ] || error_exit "Query file not found: $QUERY_FILE"
    QUERY="$(cat "$QUERY_FILE")"
fi

if [ -z "$QUERY" ]; then
    cat <<EOF
Usage: $0 "SQL_QUERY" [output_file]
       $0 --file query.sql [output_file]
       $0 --format pretty "SQL_QUERY"
       $0 --param name=value "SELECT ... WHERE col = {name:String}"

Options:
  --file, -f        Read SQL from a file
  --format          Output format: json (default), pretty, tsv
  --param, -p       Query parameter as name=value (repeatable)

NOTE: Organization filtering is applied automatically server-side.
NOTE: Only read-only queries are allowed (SELECT, WITH, DESCRIBE, SHOW, EXPLAIN).
NOTE: Authentication is delegated to np-api (NP_API_KEY or NP_TOKEN).
EOF
    exit 1
fi

validate_read_only "$QUERY"

validate_params() {
    local query="$1"
    shift
    local provided_params=("$@")

    local placeholders
    placeholders=$(echo "$query" | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*:[^}]+\}' | sed 's/{\([^:]*\):[^}]*}/\1/' | sort -u)
    [ -z "$placeholders" ] && return 0

    local provided_names=()
    for param in "${provided_params[@]}"; do
        provided_names+=("${param%%=*}")
    done

    local missing=()
    while IFS= read -r placeholder; do
        local found=false
        for name in "${provided_names[@]}"; do
            [ "$name" = "$placeholder" ] && { found=true; break; }
        done
        [ "$found" = false ] && missing+=("$placeholder")
    done <<< "$placeholders"

    if [ ${#missing[@]} -gt 0 ]; then
        local missing_defs
        missing_defs=$(echo "$query" | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*:[^}]+\}' | sort -u | while IFS= read -r ph; do
            local ph_name
            ph_name=$(echo "$ph" | sed 's/{\([^:]*\):[^}]*}/\1/')
            for m in "${missing[@]}"; do
                [ "$ph_name" = "$m" ] && echo "  $ph"
            done
        done)
        error_exit "Missing required query parameters: ${missing[*]}

The query contains placeholders that require --param flags:
${missing_defs}

Provided params: $([ ${#provided_params[@]} -eq 0 ] && echo "(none)" || printf '%s ' "${provided_params[@]}")"
    fi
}

validate_params "$QUERY" "${QUERY_PARAMS[@]}"

build_query_string() {
    local params=("$@")
    [ ${#params[@]} -eq 0 ] && return
    local qs=""
    for param in "${params[@]}"; do
        local name="${param%%=*}"
        local value="${param#*=}"
        local encoded_value
        if command -v python3 &> /dev/null; then
            encoded_value=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$value")
        else
            encoded_value=$(printf '%s' "$value" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/\*/%2A/g; s/+/%2B/g; s/,/%2C/g; s|/|%2F|g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g')
        fi
        if [ -z "$qs" ]; then
            qs="param_${name}=${encoded_value}"
        else
            qs="${qs}&param_${name}=${encoded_value}"
        fi
    done
    echo "?$qs"
}

QUERY_STRING=$(build_query_string "${QUERY_PARAMS[@]}")
REQUEST_PATH="${LAKE_PATH}${QUERY_STRING}"

# ClickHouse rejects duplicate FORMAT clauses, so skip appending if the caller already set one.
QUERY_UPPER=$(echo "$QUERY" | tr '[:lower:]' '[:upper:]')
if ! echo "$QUERY_UPPER" | grep -q "FORMAT "; then
    case "$OUTPUT_FORMAT" in
        json)   QUERY="${QUERY} FORMAT JSONEachRow" ;;
        pretty) QUERY="${QUERY} FORMAT PrettyCompact" ;;
        tsv)    QUERY="${QUERY} FORMAT TabSeparatedWithNames" ;;
        *)      error_exit "Unknown --format value: $OUTPUT_FORMAT (expected: json, pretty, tsv)" ;;
    esac
fi

echo -e "${YELLOW}Querying Customer Lake via np-api...${NC}" >&2

NP_API_ARGS=(
    --method POST
    --content-type "text/plain"
    --data-binary
    --data "$QUERY"
)

if [ -n "$OUTPUT_FILE" ]; then
    OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
    if [ "$OUTPUT_DIR" != "." ] && [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi
    "$NP_API" "${NP_API_ARGS[@]}" "$REQUEST_PATH" "$OUTPUT_FILE"
    echo -e "${GREEN}Results saved to: $OUTPUT_FILE${NC}" >&2
else
    "$NP_API" "${NP_API_ARGS[@]}" "$REQUEST_PATH"
fi
