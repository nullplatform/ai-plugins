#!/bin/bash
#
# ch_query.sh - Execute Customer Lake queries with automatic authentication and organization filtering
#
# Usage:
#   ./ch_query.sh "SELECT * FROM table WHERE ..."
#   ./ch_query.sh "SELECT * FROM table" output.json
#   ./ch_query.sh --file query.sql
#   ./ch_query.sh --file query.sql output.json
#   ./ch_query.sh --format pretty "SELECT * FROM table LIMIT 10"
#   ./ch_query.sh --format tsv "SELECT * FROM table LIMIT 10"
#   ./ch_query.sh --param entity=deployment "SELECT count() FROM audit_events WHERE entity = {entity:String}"
#   ./ch_query.sh --param entity=deployment --param status=active "SELECT ..."
#
# Parameters:
#   Use {name:Type} placeholders in your SQL query and pass values with --param name=value.
#   Each --param flag maps to a ?param_name=value query string in the request URL.
#   Supported types: String, Int64, UInt64, Float64, Date, DateTime
#
# SECURITY: This script enforces SELECT-only queries.
# Organization filtering is applied server-side via the token.
#
# Authentication: Uses nullplatform user token (Bearer header).
# The API resolves the organization from the token automatically.
#
# Token source (in order of priority):
#   1. NP_TOKEN environment variable
#   2. NP_API_KEY environment variable
#
# Endpoint: https://api.nullplatform.com/data/lake/query (same API, lake path)
#
# Output format is JSONEachRow by default.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Resolve HTTP client: npcurl (Docker) > curl (local)
if command -v npcurl &> /dev/null; then
    CURL_CMD="npcurl"
elif command -v curl &> /dev/null; then
    CURL_CMD="curl"
else
    echo -e "${RED}Error: No HTTP client available (tried npcurl, curl)${NC}" >&2
    exit 1
fi

# Customer Lake endpoint (same base as nullplatform API)
LAKE_URL="https://api.nullplatform.com/data/lake/query"

# Function to print error and exit
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to get nullplatform token
get_np_token() {
    local token=""

    if [ -n "$NP_TOKEN" ]; then
        token="$NP_TOKEN"
    elif [ -n "$NP_API_KEY" ]; then
        token="$NP_API_KEY"
    fi

    echo "$token"
}

# Function to validate query is SELECT-only
validate_select_only() {
    local query="$1"

    # Remove leading whitespace and comments
    local cleaned=$(echo "$query" | sed 's/^[[:space:]]*//' | sed '/^--/d' | sed '/^$/d')

    # Get the first keyword (case-insensitive)
    local first_keyword=$(echo "$cleaned" | head -1 | awk '{print toupper($1)}')

    case "$first_keyword" in
        SELECT|WITH)
            return 0
            ;;
        *)
            error_exit "SECURITY: Only SELECT queries are allowed.

Blocked keyword: $first_keyword

Allowed query types:
  - SELECT ... FROM ...
  - WITH ... SELECT ..."
            ;;
    esac
}

# Function to get authentication token
get_auth_token() {
    local token=""

    token=$(get_np_token)

    if [ -z "$token" ]; then
        error_exit "No authentication token found.

Set one of:
  1. NP_TOKEN environment variable
  2. NP_API_KEY environment variable

Example:
  export NP_TOKEN='your-nullplatform-token'"
    fi

    echo "$token"
}

# Parse arguments
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
            if [ -z "$1" ]; then
                error_exit "--file requires a filename argument"
            fi
            QUERY_FILE="$1"
            shift
            ;;
        --format)
            shift
            if [ -z "$1" ]; then
                error_exit "--format requires a format argument (json, pretty, tsv)"
            fi
            OUTPUT_FORMAT="$1"
            shift
            ;;
        --param|-p)
            shift
            if [ -z "$1" ]; then
                error_exit "--param requires a name=value argument"
            fi
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

# Load query from file if specified
if [ "$FROM_FILE" = true ]; then
    if [ ! -f "$QUERY_FILE" ]; then
        error_exit "Query file not found: $QUERY_FILE"
    fi
    QUERY="$(cat "$QUERY_FILE")"
fi

# Validate query is provided
if [ -z "$QUERY" ]; then
    echo "Usage: $0 \"SQL_QUERY\" [output_file]"
    echo "       $0 --file query.sql [output_file]"
    echo "       $0 --format pretty \"SQL_QUERY\""
    echo "       $0 --param name=value \"SELECT ... WHERE col = {name:String}\""
    echo ""
    echo "Options:"
    echo "  --file, -f        Read SQL from a file"
    echo "  --format          Output format: json (default), pretty, tsv"
    echo "  --param, -p       Query parameter as name=value (repeatable)"
    echo ""
    echo "Examples:"
    echo "  $0 \"SELECT * FROM core_entities_application WHERE _deleted = 0 LIMIT 10\""
    echo "  $0 \"SELECT name FROM core_entities_scope\" results.json"
    echo "  $0 --format pretty \"SELECT * FROM core_entities_scope LIMIT 5\""
    echo "  $0 --file query.sql output.json"
    echo "  $0 --param entity=deployment \"SELECT count() FROM audit_events WHERE entity = {entity:String}\""
    echo "  $0 --param entity=deployment --param status=active \"SELECT count() FROM audit_events WHERE entity = {entity:String} AND status = {status:String}\""
    echo ""
    echo "NOTE: Organization filtering is applied automatically server-side."
    echo "NOTE: Only SELECT queries are allowed."
    exit 1
fi

# Validate query is read-only
validate_select_only "$QUERY"

# Validate that all {name:Type} placeholders in the query have a corresponding --param
validate_params() {
    local query="$1"
    shift
    local provided_params=("$@")

    # Extract placeholder names from query: {name:Type}
    # Supports all ClickHouse types including complex ones: Array(String), Nullable(Int32),
    # LowCardinality(String), Tuple(Int32, String), FixedString(N), DateTime64(3), etc.
    local placeholders
    placeholders=$(echo "$query" | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*:[^}]+\}' | sed 's/{\([^:]*\):[^}]*}/\1/' | sort -u)

    if [ -z "$placeholders" ]; then
        return 0
    fi

    # Build a lookup of provided param names
    local provided_names=()
    for param in "${provided_params[@]}"; do
        provided_names+=("${param%%=*}")
    done

    local missing=()
    while IFS= read -r placeholder; do
        local found=false
        for name in "${provided_names[@]}"; do
            if [ "$name" = "$placeholder" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            missing+=("$placeholder")
        fi
    done <<< "$placeholders"

    if [ ${#missing[@]} -gt 0 ]; then
        # Extract full placeholder definitions (with types) for the error message
        local missing_defs
        missing_defs=$(echo "$query" | grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*:[^}]+\}' | sort -u | while IFS= read -r ph; do
            local ph_name
            ph_name=$(echo "$ph" | sed 's/{\([^:]*\):[^}]*}/\1/')
            for m in "${missing[@]}"; do
                if [ "$ph_name" = "$m" ]; then
                    echo "  $ph"
                fi
            done
        done)
        error_exit "Missing required query parameters: ${missing[*]}

The query contains placeholders that require --param flags:
${missing_defs}

Provided params: $([ ${#provided_params[@]} -eq 0 ] && echo "(none)" || printf '%s ' "${provided_params[@]}")

Example:
  $0 $(printf -- '--param %s=<value> ' "${missing[@]}")\"$query\""
    fi
}

validate_params "$QUERY" "${QUERY_PARAMS[@]}"

# Build URL with query parameters
build_url() {
    local base_url="$1"
    shift
    local params=("$@")

    if [ ${#params[@]} -eq 0 ]; then
        echo "$base_url"
        return
    fi

    local query_string=""
    for param in "${params[@]}"; do
        local name="${param%%=*}"
        local value="${param#*=}"
        # URL-encode the value using python3 (available on macOS/Linux) or basic sed fallback
        local encoded_value
        if command -v python3 &> /dev/null; then
            encoded_value=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$value")
        else
            encoded_value=$(printf '%s' "$value" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/\*/%2A/g; s/+/%2B/g; s/,/%2C/g; s|/|%2F|g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g')
        fi
        if [ -z "$query_string" ]; then
            query_string="param_${name}=${encoded_value}"
        else
            query_string="${query_string}&param_${name}=${encoded_value}"
        fi
    done

    echo "${base_url}?${query_string}"
}

REQUEST_URL=$(build_url "$LAKE_URL" "${QUERY_PARAMS[@]}")

# Get authentication token
AUTH_TOKEN=$(get_auth_token)
echo -e "${YELLOW}Using nullplatform token for authentication${NC}" >&2

# Append FORMAT if not specified in query
QUERY_UPPER=$(echo "$QUERY" | tr '[:lower:]' '[:upper:]')
if ! echo "$QUERY_UPPER" | grep -q "FORMAT "; then
    case "$OUTPUT_FORMAT" in
        pretty)
            QUERY="${QUERY} FORMAT PrettyCompact"
            ;;
        tsv)
            QUERY="${QUERY} FORMAT TabSeparatedWithNames"
            ;;
        json|*)
            QUERY="${QUERY} FORMAT JSONEachRow"
            ;;
    esac
fi

# Execute query
if [ -n "$OUTPUT_FILE" ]; then
    # Create output directory if needed
    OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
    if [ "$OUTPUT_DIR" != "." ] && [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    HTTP_CODE=$($CURL_CMD -s -o "$OUTPUT_FILE" -w "%{http_code}" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: text/plain" \
        --connect-timeout 10 \
        --max-time 300 \
        --data-binary "$QUERY" \
        "$REQUEST_URL")
else
    # Create a temp file to capture both output and HTTP code
    TEMP_OUTPUT=$(mktemp)
    trap "rm -f '$TEMP_OUTPUT'" EXIT

    HTTP_CODE=$($CURL_CMD -s -o "$TEMP_OUTPUT" -w "%{http_code}" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: text/plain" \
        --connect-timeout 10 \
        --max-time 300 \
        --data-binary "$QUERY" \
        "$REQUEST_URL")
fi

# Handle HTTP errors
case "$HTTP_CODE" in
    200)
        if [ -n "$OUTPUT_FILE" ]; then
            echo -e "${GREEN}Results saved to: $OUTPUT_FILE${NC}" >&2
        else
            cat "$TEMP_OUTPUT"
        fi
        ;;
    401)
        if [ -n "$OUTPUT_FILE" ]; then
            ERROR_BODY=$(cat "$OUTPUT_FILE" 2>/dev/null)
            rm -f "$OUTPUT_FILE"
        else
            ERROR_BODY=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        fi
        error_exit "Authentication failed (HTTP 401). Check your credentials.

$ERROR_BODY"
        ;;
    403)
        if [ -n "$OUTPUT_FILE" ]; then
            ERROR_BODY=$(cat "$OUTPUT_FILE" 2>/dev/null)
            rm -f "$OUTPUT_FILE"
        else
            ERROR_BODY=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        fi
        error_exit "Access denied (HTTP 403). Your credentials may not have access to the data lake.

$ERROR_BODY"
        ;;
    404)
        if [ -n "$OUTPUT_FILE" ]; then
            ERROR_BODY=$(cat "$OUTPUT_FILE" 2>/dev/null)
            rm -f "$OUTPUT_FILE"
        else
            ERROR_BODY=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        fi
        error_exit "Not found (HTTP 404). Check the database name and table exist.

$ERROR_BODY"
        ;;
    000)
        error_exit "Cannot connect to Customer Lake. Check network connectivity."
        ;;
    *)
        if [ -n "$OUTPUT_FILE" ]; then
            ERROR_BODY=$(cat "$OUTPUT_FILE" 2>/dev/null)
            rm -f "$OUTPUT_FILE"
        else
            ERROR_BODY=$(cat "$TEMP_OUTPUT" 2>/dev/null)
        fi
        error_exit "Customer Lake query failed (HTTP $HTTP_CODE).

Query: $(echo "$QUERY" | head -3)...

Response:
$ERROR_BODY"
        ;;
esac
