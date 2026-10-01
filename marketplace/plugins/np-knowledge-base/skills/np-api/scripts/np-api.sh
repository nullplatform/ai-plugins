#!/bin/bash

# np-api.sh - Nullplatform API Navigator CLI
# Usage:
#   np-api                            - Show concepts and entity map
#   np-api search-endpoint <term>     - Search endpoints by term
#   np-api describe-endpoint <endpoint> - Show full documentation for endpoint
#   np-api fetch-api <url>            - Execute API request

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$SCRIPT_DIR/../docs"
FETCH_SCRIPT="$SCRIPT_DIR/fetch_np_api_url.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_concepts() {
    cat "$DOCS_DIR/concepts.md"
}

search_endpoints() {
    local term="$1"

    if [[ -z "$term" ]]; then
        echo -e "${RED}Error: search-endpoint requires a term${NC}"
        echo "Usage: np-api search-endpoint <term>"
        exit 1
    fi

    echo -e "${CYAN}Searching for endpoints matching '$term'...${NC}"
    echo ""

    # Search for @endpoint markers and filter by term
    local found=0
    for file in "$DOCS_DIR"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "concepts.md" ]] && continue

        # Extract @endpoint lines that match the term
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                # Extract just the endpoint path
                endpoint=$(echo "$line" | sed 's/## @endpoint //')
                echo -e "${GREEN}$endpoint${NC}"

                # Get the description (first non-empty line after @endpoint)
                desc=$(grep -A2 "$line" "$file" | tail -n1 | head -c 100)
                if [[ -n "$desc" && ! "$desc" =~ ^## && ! "$desc" =~ ^### ]]; then
                    echo "  $desc"
                fi
                echo ""
                found=$((found + 1))
            fi
        done < <(grep -h "## @endpoint" "$file" 2>/dev/null | grep -i "$term")
    done

    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}No endpoints found matching '$term'${NC}"
        echo ""
        echo "Try: np-api search-endpoint deployment"
        echo "     np-api search-endpoint application"
        echo "     np-api search-endpoint scope"
    else
        echo -e "${CYAN}Found $found endpoint(s)${NC}"
    fi
}

describe_endpoint() {
    local endpoint="$1"

    if [[ -z "$endpoint" ]]; then
        echo -e "${RED}Error: describe-endpoint requires an endpoint${NC}"
        echo "Usage: np-api describe-endpoint <endpoint>"
        echo "Example: np-api describe-endpoint /deployment"
        exit 1
    fi

    # Normalize endpoint - remove leading slash for matching
    local search_pattern="$endpoint"

    # Search for the endpoint in all doc files
    for file in "$DOCS_DIR"/*.md; do
        [[ -f "$file" ]] || continue
        [[ "$(basename "$file")" == "concepts.md" ]] && continue

        # Check if this file contains the endpoint
        if grep -q "## @endpoint.*$search_pattern" "$file" 2>/dev/null; then
            # Extract content from @endpoint marker to next @endpoint or end of file
            awk -v pattern="$search_pattern" '
                BEGIN { printing = 0 }
                /^## @endpoint/ {
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

    echo -e "${RED}Endpoint '$endpoint' not found${NC}"
    echo ""
    echo "Try searching first: np-api search-endpoint $(echo "$endpoint" | tr '/' ' ' | awk '{print $1}')"
    return 1
}

fetch_endpoint() {
    local url="$1"

    if [[ -z "$url" ]]; then
        echo -e "${RED}Error: fetch-api requires a URL${NC}"
        echo "Usage: np-api fetch-api <url>"
        echo "Example: np-api fetch-api \"/application/123\""
        exit 1
    fi

    if [[ ! -x "$FETCH_SCRIPT" ]]; then
        echo -e "${RED}Error: fetch_np_api_url.sh not found or not executable${NC}"
        exit 1
    fi

    "$FETCH_SCRIPT" "$url"
}

show_help() {
    echo -e "${CYAN}np-api - Nullplatform API Navigator${NC}"
    echo ""
    echo "Usage:"
    echo "  np-api                              Show concepts and entity map"
    echo "  np-api search-endpoint <term>       Search endpoints by term"
    echo "  np-api describe-endpoint <endpoint> Show full documentation for endpoint"
    echo "  np-api fetch-api <url>              Execute API request"
    echo ""
    echo "Examples:"
    echo "  np-api                                  # Show entity hierarchy"
    echo "  np-api search-endpoint deployment       # Find deployment endpoints"
    echo "  np-api describe-endpoint /deployment    # Full docs for endpoint"
    echo "  np-api fetch-api \"/application/123\"    # Call the API"
}

# Main
case "${1:-}" in
    "")
        show_concepts
        ;;
    "search-endpoint")
        search_endpoints "$2"
        ;;
    "describe-endpoint")
        describe_endpoint "$2"
        ;;
    "fetch-api")
        fetch_endpoint "$2"
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
