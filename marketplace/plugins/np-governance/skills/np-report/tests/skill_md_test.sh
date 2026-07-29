#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${SCRIPT_DIR}/../SKILL.md"
fails=0
need() { grep -q "$1" "$S" || { echo "FAIL: SKILL.md missing: $1"; fails=$((fails+1)); }; }

[ -f "$S" ] || { echo "FAIL: SKILL.md missing"; exit 1; }
need "name: np-report"
need "allowed-tools:"
need 'skills/np-api/scripts/\*.sh'
need 'skills/np-lake/scripts/\*.sh'
need "ui_schema"
need "FORMAT JSON"
need "toUInt32OrZero"
need "EMPTY"
need "check_auth.sh"
need "fetch_np_api_url.sh"
need "AskUserQuestion"
need "Adaptive content discovery"
need "vague"
need "same-slug"
need "Post-persist"
need "render verification"
need "date-range picker"
grep -q "uiSchema" "$S" && { echo "FAIL: SKILL.md must not use camelCase uiSchema"; fails=$((fails+1)); }
grep -q "SESSION_TEMP_DIR" "$S" && { echo "FAIL: SKILL.md must not reference SESSION_TEMP_DIR"; fails=$((fails+1)); }
grep -q "build_widget" "$S" && { echo "FAIL: SKILL.md must not reference build_widget"; fails=$((fails+1)); }
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
