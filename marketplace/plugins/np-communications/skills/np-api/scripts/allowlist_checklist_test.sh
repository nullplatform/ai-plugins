#!/bin/bash
# Verifies the np-checklist approval write paths are present in the ALLOWED_MODIFY allowlist.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${SCRIPT_DIR}/fetch_np_api_url.sh"

grep -qE '^\s*"approval/checklist/specification"\s*$' "$F"                  || { echo "FAIL: \"approval/checklist/specification\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/specification/\*"\s*$' "$F"               || { echo "FAIL: \"approval/checklist/specification/*\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/action/\*/checklist_specification"\s*$' "$F"        || { echo "FAIL: \"approval/action/*/checklist_specification\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/dry-run"\s*$' "$F"                                  || { echo "FAIL: \"approval/dry-run\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/template"\s*$' "$F"                       || { echo "FAIL: \"approval/checklist/template\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/template/\*"\s*$' "$F"                    || { echo "FAIL: \"approval/checklist/template/*\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/action/\*/checklist_template"\s*$' "$F"             || { echo "FAIL: \"approval/action/*/checklist_template\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/\*/checklist/items/\*"\s*$' "$F"                    || { echo "FAIL: \"approval/*/checklist/items/*\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate_from_policy/preview"\s*$' "$F"    || { echo "FAIL: \"approval/checklist/migrate_from_policy/preview\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate_from_policy/apply"\s*$' "$F"      || { echo "FAIL: \"approval/checklist/migrate_from_policy/apply\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate_from_policy/rollback"\s*$' "$F"   || { echo "FAIL: \"approval/checklist/migrate_from_policy/rollback\" missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate-from-policy/preview"\s*$' "$F"    || { echo "FAIL: \"approval/checklist/migrate-from-policy/preview\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate-from-policy/apply"\s*$' "$F"      || { echo "FAIL: \"approval/checklist/migrate-from-policy/apply\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
grep -qE '^\s*"approval/checklist/migrate-from-policy/rollback"\s*$' "$F"   || { echo "FAIL: \"approval/checklist/migrate-from-policy/rollback\" (legacy alias) missing from ALLOWED_MODIFY"; exit 1; }
echo "PASS: checklist approval write paths allowlisted"
