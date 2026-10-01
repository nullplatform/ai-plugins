#!/bin/bash
# Tests for np-context.sh (project context from .np/ and application discovery).
#
# Network is replaced by NP_CONTEXT_FETCH, a fake fetch script that answers from
# fixtures. Live check (manual): create a temp git repo with
#   git remote add origin https://github.com/nullplatform/frontend-ui-plugins
# and run `np-context.sh discover` — expect match = 1449966796 (ui-plugins).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${SCRIPT_DIR}/np-context.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

assert_eq() { # name expected actual
    if [[ "$2" == "$3" ]]; then echo "  ok   $1"; else echo "  FAIL $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=1; fi
}
assert_exit() { # name expected_code cmd...
    local name="$1" want="$2"; shift 2
    "$@" >/dev/null 2>&1; local got=$?
    assert_eq "$name (exit $want)" "$want" "$got"
}

[[ -x "$S" ]] || { echo "FAIL: $S missing or not executable"; exit 1; }

echo "remote-url normalization"
assert_eq "ssh scp-like"       "https://github.com/org/repo" "$("$S" remote-url 'git@github.com:org/repo.git')"
assert_eq "ssh url"            "https://github.com/org/repo" "$("$S" remote-url 'ssh://git@github.com/org/repo.git')"
assert_eq "https .git"         "https://github.com/org/repo" "$("$S" remote-url 'https://github.com/org/repo.git')"
assert_eq "host case + slash"  "https://github.com/org/repo" "$("$S" remote-url 'https://GitHub.com/org/repo/')"
assert_eq "credentials"        "https://github.com/org/repo" "$("$S" remote-url 'https://user:token@github.com/org/repo')"
assert_eq "path case kept"     "https://gitlab.acme.io/Team/My-Repo" "$("$S" remote-url 'git@gitlab.acme.io:Team/My-Repo.git')"
assert_exit "empty input" 2 "$S" remote-url ''

echo "parse-link"
LINK='https://acme.app.nullplatform.io/account/17/namespace/483721746/application/1449966796'
assert_eq "plain link" \
  '{"base_url":"https://acme.app.nullplatform.io","account_id":"17","namespace_id":"483721746","application_id":"1449966796"}' \
  "$("$S" parse-link "$LINK" | jq -c .)"
assert_eq "link with trailing route" \
  '{"base_url":"https://acme.app.nullplatform.io","account_id":"17","namespace_id":"483721746","application_id":"1449966796"}' \
  "$("$S" parse-link "$LINK/scopes/123/deployments?x=1" | jq -c .)"
assert_eq "custom console host accepted" "3" \
  "$("$S" parse-link 'https://console.acme.com/account/1/namespace/2/application/3' | jq -r .application_id)"
assert_exit "wrong path order" 2 "$S" parse-link 'https://acme.app.nullplatform.io/namespace/2/account/1/application/3'
assert_exit "no app in path" 2 "$S" parse-link 'https://acme.app.nullplatform.io/account/17/namespace/483721746'
assert_exit "garbage"      2 "$S" parse-link 'not a link'

echo "load"
ROOT="$TMP/proj"; mkdir -p "$ROOT"
assert_exit "no .np/" 3 "$S" load --root "$ROOT"
mkdir -p "$ROOT/.np"
printf 'version: 1\nnullplatform:\n  application_id: "1"\n' > "$ROOT/.np/application.yaml"
printf 'deploy with care\n' > "$ROOT/.np/notes.md"
head -c 70000 /dev/zero | tr '\0' 'x' > "$ROOT/.np/huge.txt"
OUT="$("$S" load --root "$ROOT")"
assert_eq "load lists application.yaml" "yes" "$(grep -q '^### .np/application.yaml' <<<"$OUT" && echo yes || echo no)"
assert_eq "load includes content"       "yes" "$(grep -q 'deploy with care' <<<"$OUT" && echo yes || echo no)"
assert_eq "load skips huge file"        "yes" "$(grep -q 'huge.txt.*skipped' <<<"$OUT" && ! grep -q 'xxxxxxxxxx' <<<"$OUT" && echo yes || echo no)"

# ---- fake fetch: answers like np-api.sh fetch-api would ----
FAKE="$TMP/fake_fetch.sh"
cat > "$FAKE" <<'EOF'
#!/bin/bash
case "$1" in
  /application/1449966796)
    echo '{"id":1449966796,"name":"ui-plugins","slug":"ui-plugins","status":"active","nrn":"organization=4:account=17:namespace=483721746:application=1449966796","repository_url":"https://github.com/nullplatform/frontend-ui-plugins","is_mono_repo":false,"repository_app_path":null,"namespace_id":483721746}' ;;
  /application/222)
    echo '{"id":222,"name":"api","slug":"api","status":"active","nrn":"organization=4:account=17:namespace=99:application=222","repository_url":"https://github.com/acme/mono","is_mono_repo":true,"repository_app_path":"services/api","namespace_id":99}' ;;
  /application/404404)
    echo '{"error":"not found"}'; exit 1 ;;
  /organization/4)
    echo '{"id":4,"name":"nullplatform","slug":"nullplatform"}' ;;
  "/application?repository_url=https%3A%2F%2Fgithub.com%2Fnullplatform%2Ffrontend-ui-plugins"*)
    echo '{"paging":{"total":1},"results":[{"id":1449966796,"name":"ui-plugins","slug":"ui-plugins","namespace_id":483721746,"is_mono_repo":false,"repository_app_path":null}]}' ;;
  "/application?repository_url=https%3A%2F%2Fgithub.com%2Facme%2Fmono"*)
    echo '{"paging":{"total":2},"results":[{"id":222,"name":"api","slug":"api","namespace_id":99,"is_mono_repo":true,"repository_app_path":"services/api"},{"id":333,"name":"web","slug":"web","namespace_id":99,"is_mono_repo":true,"repository_app_path":"apps/web"}]}' ;;
  "/application?repository_url=https%3A%2F%2Fgithub.com%2Fdotgit%2Frepo.git"*)
    echo '{"paging":{"total":1},"results":[{"id":555,"name":"dotgit","slug":"dotgit","namespace_id":1,"is_mono_repo":false,"repository_app_path":null}]}' ;;
  "/application?repository_url="*)
    echo '{"paging":{"total":0},"results":[]}' ;;
  *) echo "unexpected endpoint: $1" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKE"
export NP_CONTEXT_FETCH="$FAKE"

echo "discover"
assert_eq "single match" \
  '{"canonical_url":"https://github.com/nullplatform/frontend-ui-plugins","candidates":[{"id":1449966796,"name":"ui-plugins","slug":"ui-plugins","namespace_id":483721746,"is_mono_repo":false,"repository_app_path":null}],"match":1449966796}' \
  "$("$S" discover --remote 'git@github.com:nullplatform/frontend-ui-plugins.git' | jq -c .)"
assert_eq "monorepo resolved by path" "222" \
  "$("$S" discover --remote 'https://github.com/acme/mono' --path 'services/api/' | jq -r .match)"
assert_eq "monorepo ambiguous without path" "null" \
  "$("$S" discover --remote 'https://github.com/acme/mono' | jq -r .match)"
assert_eq "monorepo keeps both candidates when ambiguous" "2" \
  "$("$S" discover --remote 'https://github.com/acme/mono' | jq '.candidates | length')"
assert_eq "zero results" '{"candidates":[],"match":null}' \
  "$("$S" discover --remote 'https://github.com/nobody/nothing' | jq -c '{candidates, match}')"
assert_eq "retries with .git suffix" "555" \
  "$("$S" discover --remote 'https://github.com/dotgit/repo' | jq -r .match)"

echo "match-app"
assert_eq "same repo → match" "true" \
  "$("$S" match-app 1449966796 --remote 'git@github.com:nullplatform/frontend-ui-plugins.git' | jq -r .match)"
assert_exit "same repo → exit 0" 0 "$S" match-app 1449966796 --remote 'https://github.com/nullplatform/frontend-ui-plugins'
assert_eq "different repo → no match" "false" \
  "$("$S" match-app 1449966796 --remote 'https://github.com/acme/other' | jq -r .match)"
assert_exit "different repo → exit 1" 1 "$S" match-app 1449966796 --remote 'https://github.com/acme/other'
assert_eq "monorepo with matching path → match" "true" \
  "$("$S" match-app 222 --remote 'https://github.com/acme/mono' --path 'services/api' | jq -r .match)"
assert_eq "monorepo with other path → no match" "false" \
  "$("$S" match-app 222 --remote 'https://github.com/acme/mono' --path 'apps/web' | jq -r .match)"
assert_exit "unknown app → exit 1" 1 "$S" match-app 404404 --remote 'https://github.com/acme/mono'
assert_exit "no remote → exit 2" 2 "$S" match-app 1449966796 --remote ''

echo "init"
EXPECTED_APP='version: 1
repository:
  name: nullplatform/frontend-ui-plugins
  url: https://github.com/nullplatform/frontend-ui-plugins
nullplatform:
  base_url: https://nullplatform.app.nullplatform.io
  account_id: "17"
  namespace_id: "483721746"
  application_id: "1449966796"
  application_slug: ui-plugins'
assert_eq "init --app derives everything (base_url from org slug)" "$EXPECTED_APP" "$(unset NP_LOGIN_URL; "$S" init --app 1449966796)"
assert_eq "init --app honours NP_LOGIN_URL" "https://custom.app.nullplatform.io" \
  "$(NP_LOGIN_URL='https://custom.app.nullplatform.io/' "$S" init --app 1449966796 | awk '/base_url/{print $2}')"
assert_eq "init --link takes base_url from the link" "https://acme.app.nullplatform.io" \
  "$(unset NP_LOGIN_URL; "$S" init --link "$LINK" | awk '/base_url/{print $2}')"
assert_eq "init monorepo adds app_path" "services/api" \
  "$(unset NP_LOGIN_URL; "$S" init --app 222 | awk '/app_path/{print $2}')"
assert_exit "init 404 fails" 1 "$S" init --app 404404
assert_exit "init needs --app or --link" 2 "$S" init

echo "init --write"
ROOT2="$TMP/proj2"; mkdir -p "$ROOT2"
( unset NP_LOGIN_URL; "$S" init --app 1449966796 --write --root "$ROOT2" >/dev/null )
assert_eq "writes .np/application.yaml" "$EXPECTED_APP" "$(cat "$ROOT2/.np/application.yaml")"
assert_exit "rewrite identical content is fine" 0 "$S" init --app 1449966796 --write --root "$ROOT2"
assert_exit "refuses to overwrite different content" 4 "$S" init --app 222 --write --root "$ROOT2"
assert_eq "file untouched after refusal" "$EXPECTED_APP" "$(cat "$ROOT2/.np/application.yaml")"
assert_exit "--force overwrites" 0 "$S" init --app 222 --write --force --root "$ROOT2"
assert_eq "file replaced after --force" '"222"' "$(awk '/application_id/{print $2}' "$ROOT2/.np/application.yaml")"

if [[ $FAIL -eq 0 ]]; then echo "PASS: np-context.sh"; else echo "FAIL: np-context.sh"; exit 1; fi
