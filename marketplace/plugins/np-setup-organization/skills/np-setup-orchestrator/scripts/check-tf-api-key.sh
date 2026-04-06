#!/bin/bash
# Script to validate np_api_key from common.tfvars
# Usage: ./check-tf-api-key.sh [path_to_file]
# If no file is specified, uses common.tfvars in the current directory

set -e

SECRETS_FILE="${1:-common.tfvars}"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "ERROR: File not found: $SECRETS_FILE"
    exit 1
fi

# Extract np_api_key from the tfvars file
TF_API_KEY=$(grep 'np_api_key' "$SECRETS_FILE" | sed 's/.*= *"\(.*\)"/\1/' | tr -d '[:space:]')

if [ -z "$TF_API_KEY" ]; then
    echo "ERROR: np_api_key not found in $SECRETS_FILE"
    exit 1
fi

# Attempt to get token
RESPONSE=$(curl -s -X POST "https://api.nullplatform.com/token" \
    -H "Content-Type: application/json" \
    -d "{\"api_key\": \"$TF_API_KEY\"}")

# Verify if the response contains access_token
if echo "$RESPONSE" | grep -q "access_token"; then
    echo "OK"
    # Extract organization_id if available
    ORG_ID=$(echo "$RESPONSE" | grep -o '"organization_id":[0-9]*' | cut -d: -f2)
    if [ -n "$ORG_ID" ]; then
        echo "organization_id=$ORG_ID"
    fi
    exit 0
else
    echo "ERROR: Invalid API Key"
    echo "$RESPONSE"
    exit 1
fi
