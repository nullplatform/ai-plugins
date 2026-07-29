#!/bin/bash
#
# Resend a notification to its configured channels
#
# Usage:
#   ./resend_notification.sh <notification_id> [channel_id]
#
# Examples:
#   ./resend_notification.sh 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7
#   ./resend_notification.sh 957dc1b5-3cbd-4d5f-aa6e-47aa319174e7 476678878
#
# Output:
#   JSON with the resend result
#
# Notes:
#   - Resends to all channels by default
#   - Pass a channel_id to resend to a specific channel only
#   - Useful for retesting after fixing entrypoint/script bugs
#   - The notification must already exist (use fetch-api to find notification IDs)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
    echo "  np-api fetch-api \"/notification?nrn=organization%3D<org_id>%3Aaccount%3D<acct_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>&source=service\""
    echo ""
    echo "Checking delivery results:"
    echo "  np-api fetch-api \"/notification/<id>/result\""
    exit 1
fi

NOTIFICATION_ID="$1"
CHANNEL_ID="${2:-}"

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

# Execute via fetch_np_api_url.sh (handles authentication)
"$SCRIPT_DIR/fetch_np_api_url.sh" --method POST --data "$REQUEST_BODY" "/notification/$NOTIFICATION_ID/resend"
