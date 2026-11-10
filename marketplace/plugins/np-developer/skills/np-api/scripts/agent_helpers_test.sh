#!/bin/bash
# Tests for the agent helpers (deploy-agent-dump.sh, scope-agent-dump.sh, agent-kubectl.sh):
# which NRN the agent command goes to, and that nothing is sent when that NRN is unknown.
#
# The helpers are copied next to a fake fetch_np_api_url.sh that answers GETs from
# STUB_GET (or fails when STUB_FAIL is set), prints POST bodies instead of sending them,
# and logs every call. No request reaches the API.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

assert_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then echo "  ok   $1"; else echo "  FAIL $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=1; fi
}

cp "$SCRIPT_DIR"/{deploy-agent-dump.sh,scope-agent-dump.sh,agent-kubectl.sh} "$TMP/"
cat > "$TMP/fetch_np_api_url.sh" <<'EOF'
#!/bin/bash
if [[ "$1" == "--method" ]]; then echo "POST $5" >> "$(dirname "$0")/calls"; printf '%s' "$4"; exit 0; fi
echo "GET $1" >> "$(dirname "$0")/calls"
if [[ -n "${STUB_FAIL:-}" ]]; then echo "Error: HTTP 404" >&2; exit 1; fi
printf '%s' "${STUB_GET:-}"
EOF
chmod +x "$TMP"/*.sh

NRN_JSON='{"nrn":"organization=7:account=8:namespace=9:application=10:scope=11"}'
run() { # script args... → prints the POST body's nrn and selector, or "exit N"
    : > "$TMP/calls"
    local out code
    out=$("$TMP/$@" 2>/dev/null); code=$?
    if [[ $code -ne 0 ]]; then echo "exit $code"; else echo "$out" | jq -c '[.nrn, .selector]'; fi
}
calls() { paste -sd"|" - < "$TMP/calls"; }

echo "deploy-agent-dump.sh"
assert_eq "org read from the deployment's NRN" '["organization=7",{"cluster":"runtime"}]' "$(STUB_GET=$NRN_JSON run deploy-agent-dump.sh 12345)"
assert_eq "  GET then POST" "GET /deployment/12345|POST /controlplane/agent_command" "$(calls)"
assert_eq "explicit nrn and selector" '["organization=3",{"environment":"production"}]' \
  "$(STUB_FAIL=1 run deploy-agent-dump.sh 12345 organization=3 environment production)"
assert_eq "  no GET" "POST /controlplane/agent_command" "$(calls)"
assert_eq "API error stops before sending" "exit 1" "$(STUB_FAIL=1 run deploy-agent-dump.sh 12345)"
assert_eq "  no POST" "GET /deployment/12345" "$(calls)"
assert_eq "response without nrn stops" "exit 1" "$(STUB_GET='{"code":404}' run deploy-agent-dump.sh 12345)"
assert_eq "non-JSON response stops" "exit 1" "$(STUB_GET='<html>' run deploy-agent-dump.sh 12345)"

echo "scope-agent-dump.sh"
assert_eq "org read from the scope's NRN" '["organization=7",{"cluster":"runtime"}]' "$(STUB_GET=$NRN_JSON run scope-agent-dump.sh 5)"
assert_eq "  GET then POST" "GET /scope/5|POST /controlplane/agent_command" "$(calls)"
assert_eq "API error stops before sending" "exit 1" "$(STUB_FAIL=1 run scope-agent-dump.sh 5)"
assert_eq "  no POST" "GET /scope/5" "$(calls)"

echo "agent-kubectl.sh"
assert_eq "--nrn is required" "exit 1" "$(run agent-kubectl.sh get -- pods -n nullplatform)"
assert_eq "  no POST" "" "$(calls)"
assert_eq "empty --nrn is refused" "exit 1" "$(run agent-kubectl.sh get --nrn '' -- pods)"
assert_eq "--nrn and selector are sent" '["organization=1:account=2",{"service":"my-service"}]' \
  "$(run agent-kubectl.sh get --nrn organization=1:account=2 --selector service=my-service -- pods)"

[[ $FAIL -eq 0 ]] && echo "PASS" || echo "FAILED"
exit $FAIL
