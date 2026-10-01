#!/bin/bash
# Verifies config.sh treats a rejected write as a failure rather than a success.
#
# The engine reports failures as RFC7807 problem+json and the transport exits 0
# on any HTTP status, so `fail_on_error_body` is the only thing standing between
# a 403 and a success report. It used to match `.error`, a field the engine never
# sends: `config.sh set` printed `{}` and exited 0 on a rejected write, so a
# secret that was never stored looked stored.
#
# Hermetic: no network, no token. config.sh resolves its transport as
# "$SCRIPT_DIR/workflow-api.sh", so each case runs a copy of config.sh next to a
# stub that replays an error body.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/config.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

# A real rejection shape from the engine.
FIX_403='{"type":"https://workflow-system.dev/errors/forbidden","title":"Forbidden","status":403,"detail":"Not permitted to write config at /","instance":"/workflows/config"}'
# The legacy shape the guard already handled — must keep working.
FIX_LEGACY='{"error":"something broke"}'

make_sandbox() {
    local dir="$TMPROOT/$1"
    mkdir -p "$dir"
    cp "$SUT" "$dir/config.sh"
    { echo '#!/bin/bash'; printf '%s\n' "cat <<'JSON'
$2
JSON"; } > "$dir/workflow-api.sh"
    chmod +x "$dir/workflow-api.sh"
    echo "$dir"
}

# run_case <label> <fixture> <args...> — assert non-zero exit and no success render
run_case() {
    local label="$1" fixture="$2"; shift 2
    local dir out rc
    dir=$(make_sandbox "$(echo "$label" | tr ' /' '__')" "$fixture")
    set +e
    out=$(printf '%s' "supersecret" | "$dir/config.sh" "$@" 2>&1)
    rc=$?
    set -e

    [ "$rc" -ne 0 ] || fail "$label: exited 0 on an error body — the write was rejected"
    # `{}` / all-null renders are what a success path prints when handed an
    # error body; seeing one means the guard did not fire.
    if [ "$(echo "$out" | tr -d '[:space:]')" = "{}" ]; then
        fail "$label: printed '{}' and reported success over a rejected write"
    fi
    echo "$out" | grep -q '"id": null' \
        && fail "$label: rendered a null record instead of failing"
    echo "$out"
}

OUT=$(run_case "set --secret (403)" "$FIX_403" set TOKEN --path=/ --secret)
echo "$OUT" | grep -q 'HTTP 403' \
  || fail "set: did not surface the status. Got: $OUT"
echo "$OUT" | grep -q 'Not permitted to write config' \
  || fail "set: did not surface the engine's detail. Got: $OUT"

OUT=$(run_case "rotate (403)" "$FIX_403" rotate cfg_abc --value=v)
echo "$OUT" | grep -q 'HTTP 403' \
  || fail "rotate: did not surface the status. Got: $OUT"

# The pre-existing `.error` shape must still be caught.
OUT=$(run_case "set with legacy .error body" "$FIX_LEGACY" set TOKEN --path=/ --secret)
echo "$OUT" | grep -q 'something broke' \
  || fail "legacy .error body no longer reported. Got: $OUT"

if [ "$FAILED" -ne 0 ]; then
    echo "RESULT: FAILED"
    exit 1
fi
echo "PASS: config.sh fails on rejected writes instead of reporting success"
