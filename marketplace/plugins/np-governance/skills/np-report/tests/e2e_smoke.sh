#!/bin/bash
# Live smoke test — requires NP_API_KEY or NP_TOKEN. Creates a [SMOKE] report, reads it,
# publishes it, then deletes it. Non-idempotent against prod; run deliberately.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"
AUTH="${SCRIPT_DIR}/../../np-api/scripts/check_auth.sh"

"$AUTH" >/dev/null || { echo "no auth"; exit 1; }

tmp="$(mktemp)"
python3 - "$tmp" <<'PY'
import json,sys
json.dump({"name":"[SMOKE] np-report e2e","slug":"smoke-np-report-e2e","description":"temporary","visibility":"user","schema":{"type":"object","properties":{"total":{"type":"number","title":"Total"}}},"ui_schema":{"type":"VerticalLayout","elements":[{"type":"Control","scope":"#/properties/total","options":{"widget":"kpi"}}]},"queries":{"total":{"source":"SELECT count() AS total FROM core_entities_deployment FINAL WHERE _deleted = 0 FORMAT JSON","target":"#/properties/total"}}}, open(sys.argv[1],"w"))
PY

created="$("$FETCH" --method POST --data "@$tmp" "/report")"
echo "$created"
id="$(echo "$created" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')"
echo "created id=$id"
"$FETCH" "/report/$id" >/dev/null && echo "show OK"
"$FETCH" --method POST --data '{}' "/report/$id/publish" >/dev/null && echo "publish OK"
"$FETCH" --method DELETE "/report/$id" >/dev/null && echo "delete OK"
rm -f "$tmp"
echo "E2E SMOKE PASS"
