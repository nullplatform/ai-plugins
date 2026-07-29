#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D="${SCRIPT_DIR}/../docs"
fails=0
exists() { [ -f "$D/$1" ] || { echo "FAIL: docs/$1 missing"; fails=$((fails+1)); }; }
has() { grep -q "$2" "$D/$1" 2>/dev/null || { echo "FAIL: docs/$1 missing text: $2"; fails=$((fails+1)); }; }

for f in json-schema-reference.md api-reference.md widget-cookbook.md filters-reference.md lake-query-recipes.md; do exists "$f"; done
has json-schema-reference.md "ui_schema"
has json-schema-reference.md '"scope"'
has api-reference.md "POST /report"
has api-reference.md "PATCH /report/"
has api-reference.md "publish"
has filters-reference.md "toUInt32OrZero"
has json-schema-reference.md "toUInt32OrZero"
exists verification.md
has verification.md "empty-param"
has verification.md "anomal"
# The definition docs must not leak the chatbot-only mechanics:
for f in json-schema-reference.md widget-cookbook.md filters-reference.md; do
  grep -q "uiSchema" "$D/$f" 2>/dev/null && { echo "FAIL: docs/$f uses camelCase uiSchema"; fails=$((fails+1)); }
  grep -q "SESSION_TEMP_DIR\|build_widget\|meta.json" "$D/$f" 2>/dev/null && { echo "FAIL: docs/$f leaks chatbot mechanics"; fails=$((fails+1)); }
done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
