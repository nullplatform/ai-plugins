#!/bin/bash
# Verifies the report write paths are present in the ALLOWED_MODIFY allowlist.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${SCRIPT_DIR}/fetch_np_api_url.sh"

grep -qE '^\s*"report"\s*$' "$F"   || { echo "FAIL: \"report\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"report/\*"\s*$' "$F" || { echo "FAIL: \"report/*\" missing from ALLOWED_MODIFY"; exit 1; }
echo "PASS: report write paths allowlisted"