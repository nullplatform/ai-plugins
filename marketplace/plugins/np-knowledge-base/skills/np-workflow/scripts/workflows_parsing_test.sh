#!/bin/bash
# Verifies workflows.sh parses the workflow engine's real response envelopes, and
# that a failed request is reported as an error instead of an empty list.
#
# Regression test for D6: `workflows.sh list` printed "Workflows: 0" while
# GET /definitions returned 14 definitions. Cause: it requested the resource
# path "/workflows", which workflow-api.sh prefixes with NP_WORKFLOW_BASE_PATH
# (/workflows) -> /workflows/workflows -> 404. `.data // []` then turned the
# problem+json error body into an empty list, so the failure surfaced as 0.
#
# Hermetic: no network, no token. workflows.sh resolves its transport as
# "$SCRIPT_DIR/workflow-api.sh", so each case copies workflows.sh into a temp
# dir next to a stub transport that replays fixtures captured from the live
# engine (org 4, 2026-08-27) and records the resource paths it was asked for.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/workflows.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FAILED=0

# fail <message> — record a failure without aborting the remaining cases
fail() { echo "FAIL: $1"; FAILED=1; }

# --- fixtures: exact shapes returned by the engine -------------------------
# GET /definitions -> paginated envelope. Note the records carry `key` but NOT
# `latestRevision`; a column bound to latestRevision is always empty.
FIX_LIST='{"data":[
  {"id":"wf_mKBhfr1mCT21","key":"deploy-change-analysis","name":"Deploy change analysis","organizationId":"4","nrn":"organization=1","path":"/","description":null,"metadata":{},"createdAt":"2026-05-07T20:41:39.573Z","updatedAt":"2026-07-16T15:04:13.319Z"},
  {"id":"wf_gKjmPNXJjTrR","key":"falabella-demo-hotfix-check","name":"Falabella demo hotfix check","organizationId":"4","nrn":"organization=1","path":"/","description":null,"metadata":{},"createdAt":"2026-06-02T11:00:00.000Z","updatedAt":"2026-06-02T11:00:00.000Z"}
],"limit":200,"offset":0,"total":2}'

# GET /definitions/:id -> the record is nested under .workflow, with the
# revision alongside it. Top-level id/name do not exist.
# The resolved revision (18) is deliberately different from any revision listed
# in the Revisions fixture below (r7, r6). If they matched, an assert on "18"
# could be satisfied by the Revisions section and would not actually prove that
# describe read .revision.revision.
FIX_ONE='{"workflow":{"id":"wf_mKBhfr1mCT21","name":"Deploy change analysis","organizationId":"4","nrn":"organization=1","path":"/","createdAt":"2026-05-07T20:41:39.573Z","updatedAt":"2026-07-16T15:04:13.319Z"},"revision":{"workflowId":"wf_mKBhfr1mCT21","revision":18,"createdBy":"someone","createdAt":"2026-07-16T15:04:13.319Z","definition":{"steps":{}}},"resolvedVia":"latest"}'

# What the engine returns for an unrouted path. curl -s exits 0, so the
# transport hands this body back as a success.
FIX_404='{"type":"https://workflow-system.dev/errors/not-found","title":"Not found","status":404,"detail":"no route for GET /workflows/workflows?limit=200","instance":"/workflows/workflows?limit=200"}'

FIX_EMPTY='{"data":[],"limit":200,"offset":0,"total":0}'

# make_sandbox <name> <stub-body> — temp dir holding workflows.sh + a stub
# transport. The stub appends every requested path to $dir/paths.log.
make_sandbox() {
    local dir="$TMPROOT/$1"
    mkdir -p "$dir"
    cp "$SUT" "$dir/workflows.sh"
    { echo '#!/bin/bash'
      echo 'echo "$2" >> "$(dirname "$0")/paths.log"'
      cat
    } > "$dir/workflow-api.sh" <<< "$2"
    chmod +x "$dir/workflow-api.sh"
    echo "$dir"
}

# ---------------------------------------------------------------------------
# Case 1: list parses the real envelope — right count, every row printed.
# ---------------------------------------------------------------------------
D=$(make_sandbox list_ok "cat <<'JSON'
$FIX_LIST
JSON")
OUT=$("$D/workflows.sh" list 2>&1) || fail "list exited non-zero on a valid response"

echo "$OUT" | grep -qE '^Workflows: 2$' \
  || fail "list did not report 2 workflows. Got: $(echo "$OUT" | grep -i '^Workflows:' || echo '<no count line>')"
echo "$OUT" | grep -q 'wf_mKBhfr1mCT21' || fail "list omitted wf_mKBhfr1mCT21"
echo "$OUT" | grep -q 'wf_gKjmPNXJjTrR' || fail "list omitted wf_gKjmPNXJjTrR"
echo "$OUT" | grep -q 'deploy-change-analysis' \
  || fail "list omitted the workflow key (deploy-change-analysis)"

# The path must be the /definitions resource. "/workflows" is double-prefixed
# by workflow-api.sh into /workflows/workflows and 404s.
grep -qE '^/definitions(\?|$)' "$D/paths.log" \
  || fail "list requested $(tr '\n' ' ' < "$D/paths.log")— expected /definitions"
grep -qE '^/workflows' "$D/paths.log" \
  && fail "list requested a /workflows path, which workflow-api.sh double-prefixes"

# ---------------------------------------------------------------------------
# Case 2: THE D6 REGRESSION. A failed request must not read as "0 workflows".
# ---------------------------------------------------------------------------
D=$(make_sandbox list_404 "cat <<'JSON'
$FIX_404
JSON")
set +e
OUT=$("$D/workflows.sh" list 2>&1)
RC=$?
set -e

[ "$RC" -ne 0 ] || fail "list exited 0 on a 404 error body — a failed list must fail"
echo "$OUT" | grep -qE '^Workflows: 0$' \
  && fail "list reported 'Workflows: 0' for an error response; a silent zero is worse than an error"

# Pin the problem+json screening specifically. A generic "did it say error?"
# assert is also satisfied by the .data-shape check downstream, so deleting the
# RFC7807 guard would leave this case green. What must survive is the engine's
# OWN diagnosis — status code, title and detail — because that is what makes a
# 401/403 tell you it is auth rather than an empty org.
echo "$OUT" | grep -q 'HTTP 404' \
  || fail "list did not surface the HTTP status from the problem+json body. Got: $OUT"
echo "$OUT" | grep -q 'Not found' \
  || fail "list did not surface the engine's .title. Got: $OUT"
echo "$OUT" | grep -q 'no route for GET /workflows/workflows' \
  || fail "list did not surface the engine's .detail, which names the failing path. Got: $OUT"

# ---------------------------------------------------------------------------
# Case 2b: an auth failure must be diagnosable as auth, not as an empty org.
# ---------------------------------------------------------------------------
D=$(make_sandbox list_401 "cat <<'JSON'
{\"type\":\"https://workflow-system.dev/errors/unauthorized\",\"title\":\"Unauthorized\",\"status\":401,\"detail\":\"Bearer token rejected\",\"instance\":\"/workflows/definitions\"}
JSON")
set +e
OUT=$("$D/workflows.sh" list 2>&1)
RC=$?
set -e
[ "$RC" -ne 0 ] || fail "list exited 0 on a 401"
echo "$OUT" | grep -q 'HTTP 401' \
  || fail "a 401 must report its status, not a count. Got: $OUT"
echo "$OUT" | grep -q 'Bearer token rejected' \
  || fail "a 401 must surface the engine's detail. Got: $OUT"

# ---------------------------------------------------------------------------
# Case 3: a genuinely empty org still reports zero (must not become an error).
# ---------------------------------------------------------------------------
D=$(make_sandbox list_empty "cat <<'JSON'
$FIX_EMPTY
JSON")
OUT=$("$D/workflows.sh" list 2>&1) || fail "list exited non-zero on a valid empty list"
echo "$OUT" | grep -qE '^Workflows: 0$' \
  || fail "an empty-but-valid list should report 'Workflows: 0'. Got: $OUT"

# ---------------------------------------------------------------------------
# Case 4: describe reads the nested .workflow record, not absent top-level keys.
# ---------------------------------------------------------------------------
D=$(make_sandbox describe_ok "
case \"\$2\" in
  */revisions*) cat <<'JSON'
{\"data\":[{\"revision\":7,\"createdAt\":\"2026-07-16T15:04:13.319Z\",\"message\":null}],\"total\":1}
JSON
  ;;
  */aliases*)   echo '{\"data\":[{\"name\":\"latest\",\"revision\":7,\"activatedAt\":null}],\"total\":1}' ;;
  /triggers*)   echo '{\"data\":[],\"total\":0}' ;;
  *) cat <<'JSON'
$FIX_ONE
JSON
  ;;
esac")
OUT=$("$D/workflows.sh" describe wf_mKBhfr1mCT21 2>&1) \
  || fail "describe exited non-zero on a valid response"

echo "$OUT" | grep -q 'wf_mKBhfr1mCT21' \
  || fail "describe did not print the workflow id (nested under .workflow)"
echo "$OUT" | grep -q 'Deploy change analysis' \
  || fail "describe did not print the workflow name (nested under .workflow)"
# The header block must not be a wall of nulls, which is what reading absent
# top-level keys produces.
if echo "$OUT" | sed -n '/^Workflow:/,/^}/p' | grep -q '"id": null'; then
    fail "describe printed a null id — it is reading top-level keys instead of .workflow"
fi
# Bind this to the field by name. A bare "18" could be matched by the Revisions
# section rather than by the resolved revision the header is supposed to show.
echo "$OUT" | grep -q '"currentRevision": 18' \
  || fail "describe did not surface currentRevision from .revision.revision. Got: $(echo "$OUT" | sed -n '/^Workflow:/,/^}/p')"
echo "$OUT" | grep -q '"resolvedVia": "latest"' \
  || fail "describe did not surface resolvedVia"
# The Revisions section still renders from its own endpoint, unaffected.
echo "$OUT" | grep -q 'r7 ' || fail "describe lost the Revisions section"

# ---------------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "RESULT: FAILED"
    exit 1
fi
echo "PASS: workflows.sh parses list + describe envelopes and fails loudly on errors"
