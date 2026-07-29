#!/bin/bash
# Verifies the np-checklist approval write paths are present in the ALLOWED_MODIFY allowlist.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${SCRIPT_DIR}/fetch_np_api_url.sh"

grep -qE '^\s*"approval/checklist/template"\s*$' "$F"                       || { echo "FAIL: \"approval/checklist/template\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/template/\*"\s*$' "$F"                    || { echo "FAIL: \"approval/checklist/template/*\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/action/\*/checklist_template"\s*$' "$F"             || { echo "FAIL: \"approval/action/*/checklist_template\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/\*/checklist/items/\*/approve"\s*$' "$F"            || { echo "FAIL: \"approval/*/checklist/items/*/approve\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate-from-policy/apply"\s*$' "$F"      || { echo "FAIL: \"approval/checklist/migrate-from-policy/apply\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate-from-policy/rollback"\s*$' "$F"   || { echo "FAIL: \"approval/checklist/migrate-from-policy/rollback\" missing from ALLOWED_MODIFY"; exit 1; }
echo "PASS: checklist approval write paths allowlisted"
