#!/bin/bash
# List all providers for an organization at all NRN levels
# Usage: ./list_all_providers.sh <org_id> [output_dir]
#
# Uses show_descendants=true (snake_case) to get ALL providers in one query
# See: api/provider_api.md for details

set -e

ORG_ID=${1:?Usage: $0 <org_id> [output_dir]}
# Default to temp directory to avoid permission issues when running as appuser
OUTPUT_DIR=${2:-${TMPDIR:-/tmp}/providers_org_$ORG_ID}
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(dirname "$0")"

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=== Fetching all providers for organization $ORG_ID ==="
echo "Output directory: $OUTPUT_DIR"
echo ""

# Step 1: Fetch all providers with show_descendants=true (handles all NRN levels in one query)
echo "1. Fetching all providers (with show_descendants=true)..."
OFFSET=0
LIMIT=200
ALL_PROVIDERS="[]"
PAGE=1

while true; do
    "$SCRIPT_DIR/fetch_np_api_url.sh" "provider?nrn=organization=$ORG_ID&show_descendants=true&limit=$LIMIT&offset=$OFFSET" "$OUTPUT_DIR/page_$PAGE.json" 2>/dev/null
    COUNT=$(jq '.results | length' "$OUTPUT_DIR/page_$PAGE.json")
    ALL_PROVIDERS=$(echo "$ALL_PROVIDERS" | jq --slurpfile page "$OUTPUT_DIR/page_$PAGE.json" '. + $page[0].results')

    echo "   Page $PAGE: fetched $COUNT providers (offset $OFFSET)"

    if [ "$COUNT" -lt "$LIMIT" ]; then
        break
    fi
    OFFSET=$((OFFSET + LIMIT))
    PAGE=$((PAGE + 1))
done

# Save combined results
echo "$ALL_PROVIDERS" | jq 'unique_by(.id) | sort_by(.nrn)' > "$OUTPUT_DIR/all_providers.json"
TOTAL=$(jq 'length' "$OUTPUT_DIR/all_providers.json")

# Clean up page files
rm -f "$OUTPUT_DIR"/page_*.json

# Step 2: Generate summary by NRN level
echo ""
echo "2. Analyzing results..."

# Count by NRN level
ORG_COUNT=$(jq '[.[] | select(.nrn | split(":") | length == 1)] | length' "$OUTPUT_DIR/all_providers.json")
ACCOUNT_COUNT=$(jq '[.[] | select(.nrn | split(":") | length == 2)] | length' "$OUTPUT_DIR/all_providers.json")
NAMESPACE_COUNT=$(jq '[.[] | select(.nrn | split(":") | length == 3)] | length' "$OUTPUT_DIR/all_providers.json")
APPLICATION_COUNT=$(jq '[.[] | select(.nrn | split(":") | length == 4)] | length' "$OUTPUT_DIR/all_providers.json")

# Step 3: Generate summary
echo ""
echo "3. Generating summary..."
cat > "$OUTPUT_DIR/summary.txt" << SUMMARY
Provider Summary for Organization $ORG_ID
==========================================
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Method: show_descendants=true (single query with pagination)

Total Providers: $TOTAL

By NRN Level:
  - Organization level: $ORG_COUNT
  - Account level: $ACCOUNT_COUNT
  - Namespace level: $NAMESPACE_COUNT
  - Application level: $APPLICATION_COUNT

By Specification:
$(jq -r 'group_by(.specification_id) | sort_by(-length) | .[] | "  \(.[0].specification_id): \(length)"' "$OUTPUT_DIR/all_providers.json")

Unique NRN Paths:
$(jq -r '[.[].nrn] | unique | .[]' "$OUTPUT_DIR/all_providers.json" | head -20)
$(if [ "$(jq '[.[].nrn] | unique | length' "$OUTPUT_DIR/all_providers.json")" -gt 20 ]; then echo "  ... and more"; fi)

Files:
  - all_providers.json: All providers (deduplicated, sorted by NRN)
SUMMARY

cat "$OUTPUT_DIR/summary.txt"

echo ""
echo "=== Complete! ==="
echo "Total: $TOTAL providers"
echo "Output: $OUTPUT_DIR/all_providers.json"
