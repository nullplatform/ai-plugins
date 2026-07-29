#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EX="${SCRIPT_DIR}/../examples"
fails=0
check() { # <path>
  local f="$EX/$1"
  [ -f "$f" ] || { echo "FAIL: $1 missing"; fails=$((fails+1)); return; }
  python3 - "$f" <<'PY' || fails=$((fails+1))
import json,sys
d=json.load(open(sys.argv[1]))
assert isinstance(d.get("name"),str) and d["name"], "name required"
assert "ui_schema" in d, "ui_schema key (snake_case) required"
assert "uiSchema" not in d, "must not use camelCase uiSchema"
assert isinstance(d.get("schema"),dict), "schema object required"
q=d.get("queries",{})
assert isinstance(q,dict) and q, "queries required"
for k,v in q.items():
    assert "source" in v, f"query {k} missing source"
    assert v["source"].rstrip().endswith("FORMAT JSON"), f"query {k} must end FORMAT JSON"
    assert "target" in v or v.get("mapping")=="enum", f"query {k} needs target or enum mapping"
    for p,pv in v.get("params",{}).items():
        assert "scope" in pv, f"query {k} param {p} needs scope"
    import re
    NUMERIC_PH = re.compile(r"\{[A-Za-z_]+:U?Int[0-9]+\}|\{[A-Za-z_]+:Float[0-9]+\}")
    assert not NUMERIC_PH.search(v["source"]), f"query {k}: numeric-typed placeholder found; read numeric filters as String + toUInt32OrZero/toInt32OrZero/toFloat64OrZero"
print("OK",sys.argv[1].split('/')[-2])
PY
}
check deployments-overview/report.json
check build-success/report.json
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
