#!/bin/bash
#
# Resend a notification to its configured channels
# Uses the terraform admin API key (np_api_key from secrets.tfvars)
#
# Usage:
#   ./resend_notification.sh <notification_id> [channel_id]
#
# Examples:
#   ./resend_notification.sh 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7
#   ./resend_notification.sh 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7 476678878
#
# Notes:
#   - Resends to all channels by default
#   - Pass a channel_id to resend to a specific channel only
#   - Useful for retesting after fixing entrypoint/script bugs
#   - Uses the admin API key from secrets.tfvars (not the troubleshooting key)

set -e

# Find project root (where secrets.tfvars lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

BASE_URL="https://api.nullplatform.com"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <notification_id> [channel_id]"
    echo ""
    echo "Resend a notification to its configured channels."
    echo ""
    echo "Arguments:"
    echo "  notification_id  - UUID of the notification to resend"
    echo "  channel_id       - Optional. Resend only to this specific channel"
    echo ""
    echo "Examples:"
    echo "  $0 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7"
    echo "  $0 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7 476678878"
    echo ""
    echo "Finding notification IDs:"
    echo "  /np-api fetch-api \"/notification?nrn=<nrn_encoded>&source=service\""
    echo ""
    echo "Checking delivery results:"
    echo "  /np-api fetch-api \"/notification/<id>/result\""
    exit 1
fi

NOTIFICATION_ID="$1"
CHANNEL_ID="${2:-}"

# Get admin API key from secrets.tfvars
SECRETS_FILE="$PROJECT_ROOT/secrets.tfvars"
if [ ! -f "$SECRETS_FILE" ]; then
    echo "Error: secrets.tfvars not found at $SECRETS_FILE"
    echo "Run './tfvars-sync.sh pull' to recover from SSM"
    exit 1
fi

API_KEY=$(grep 'np_api_key' "$SECRETS_FILE" | cut -d'"' -f2)
if [ -z "$API_KEY" ]; then
    echo "Error: np_api_key not found in secrets.tfvars"
    exit 1
fi

# Exchange API key for access token
TOKEN=$(curl -s -X POST "${BASE_URL}/token" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "{\"api_key\": \"$API_KEY\"}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to exchange API key for token"
    exit 1
fi

# Build request body
if [ -n "$CHANNEL_ID" ]; then
    REQUEST_BODY=$(jq -n --arg cid "$CHANNEL_ID" '{"channel_ids": [$cid | tonumber]}')
else
    REQUEST_BODY='{}'
fi

echo "Resending notification $NOTIFICATION_ID..."
if [ -n "$CHANNEL_ID" ]; then
    echo "  Target channel: $CHANNEL_ID"
fi

# Execute resend
RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    "${BASE_URL}/notification/$NOTIFICATION_ID/resend")

echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
