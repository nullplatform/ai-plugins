#!/bin/bash
#
# np-context.sh - Project context from .np/ and application discovery by git remote
#
# Usage:
#   np-context.sh load [--root <dir>]                 Print every file in <root>/.np/ (exit 3 if none)
#   np-context.sh remote-url [<url>]                  Canonical https URL of the git remote (or of <url>)
#   np-context.sh parse-link <ui-link>                JSON {base_url, account_id, namespace_id, application_id}
#   np-context.sh discover [--remote <url>] [--path <p>]
#                                                     JSON {canonical_url, candidates[], match}
#   np-context.sh match-app <id> [--remote <url>] [--path <p>]
#                                                     Is <id> the app of this repo? JSON {match, reason,...}; exit 0 yes / 1 no
#   np-context.sh init (--app <id> | --link <ui-link>) [--write [--force]] [--root <dir>]
#                                                     Print application.yaml; --write saves it to <root>/.np/
#
# Exit codes: 0 ok · 1 API/not found/no match · 2 bad input · 3 no .np/ · 4 refused overwrite (use --force)
#
# Never prompts. Questions and confirmations live in the np-api skill prose so the
# behaviour is identical on every runtime. All API calls go through
# fetch_np_api_url.sh (same auth as the rest of np-api); NP_CONTEXT_FETCH overrides
# the fetch command (used by np-context_test.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH="${NP_CONTEXT_FETCH:-$SCRIPT_DIR/fetch_np_api_url.sh}"
MAX_FILE_BYTES=65536

die() { echo "np-context: $*" >&2; exit "${CODE:-2}"; }

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------- helpers ----------

api_get() { "$FETCH" "$1"; }

url_encode() { jq -rn --arg s "$1" '$s|@uri'; }

project_root() { # $1 = --root override (may be empty)
    if [[ -n "${1:-}" ]]; then echo "$1"; return; fi
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

git_remote() {
    git remote get-url origin 2>/dev/null && return 0
    local first; first="$(git remote 2>/dev/null | head -n1)"
    [[ -n "$first" ]] && git remote get-url "$first" 2>/dev/null
}

git_prefix() { git rev-parse --show-prefix 2>/dev/null || true; }

# Canonical https form of a git remote: host lowercased, credentials/port stripped,
# .git and trailing slash removed, path case preserved. Works for any host.
normalize_remote() {
    local url="$1" rest host path
    [[ -n "$url" ]] || die "remote-url: empty URL"
    case "$url" in
        *://*) rest="${url#*://}" ;;                 # https://, ssh://, git://
        *)     rest="$url"
               local head="${rest%%/*}"
               [[ "$head" == *:* ]] || die "remote-url: not a git remote URL: $url"
               rest="${head%%:*}/${rest#*:}" ;;      # scp-like git@host:org/repo
    esac
    rest="${rest#*@}"                                 # user[:token]@
    host="${rest%%/*}"; path="${rest#*/}"
    host="${host%%:*}"                                # :port
    host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
    path="${path%/}"; path="${path%.git}"; path="${path%/}"
    [[ -n "$host" && -n "$path" && "$path" != "$rest" ]] || die "remote-url: not a git remote URL: $url"
    echo "https://$host/$path"
}

# Strip a trailing route/query so the origin of a URL remains.
url_origin() { printf '%s' "$1" | sed -E 's#^(https?://[^/?]+).*$#\1#'; }

nrn_field() { printf '%s' "$1" | sed -nE "s/.*${2}=([0-9]+).*/\1/p"; }

# ---------- commands ----------

cmd_load() {
    local root=""
    while [[ $# -gt 0 ]]; do case "$1" in --root) root="$2"; shift 2 ;; *) die "load: unknown option $1" ;; esac; done
    root="$(project_root "$root")"
    local dir="$root/.np"
    [[ -d "$dir" ]] || { echo "No .np/ directory in $root" >&2; exit 3; }
    local f name size
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        size=$(wc -c < "$f" | tr -d ' ')
        if (( size > MAX_FILE_BYTES )); then
            echo "### .np/$name (skipped: $size bytes > $MAX_FILE_BYTES)"; echo; continue
        fi
        if [[ "$(LC_ALL=C tr -cd '\000' < "$f" | wc -c | tr -d ' ')" != "0" ]]; then   # NUL bytes → binary
            echo "### .np/$name (skipped: binary)"; echo; continue
        fi
        echo "### .np/$name"
        cat "$f"; [[ -n "$(tail -c1 "$f")" ]] && echo
        echo
    done
}

cmd_remote_url() {
    local url="${1-}"
    if [[ $# -eq 0 ]]; then url="$(git_remote || true)"; [[ -n "$url" ]] || die "remote-url: no git remote found"; fi
    normalize_remote "$url"
}

cmd_parse_link() {
    local link="${1-}"
    [[ -n "$link" ]] || die "parse-link: missing link"
    local re='^(https://[^/?#]+)/account/([0-9]+)/namespace/([0-9]+)/application/([0-9]+)([/?#].*)?$'
    [[ "$link" =~ $re ]] || die "parse-link: not a nullplatform application link: $link"
    jq -cn --arg b "${BASH_REMATCH[1]}" --arg a "${BASH_REMATCH[2]}" --arg n "${BASH_REMATCH[3]}" --arg i "${BASH_REMATCH[4]}" \
        '{base_url:$b, account_id:$a, namespace_id:$n, application_id:$i}'
}

cmd_discover() {
    local remote="" path="" path_given=0
    while [[ $# -gt 0 ]]; do case "$1" in
        --remote) remote="$2"; shift 2 ;;
        --path)   path="$2"; path_given=1; shift 2 ;;
        *) die "discover: unknown option $1" ;;
    esac; done
    [[ -n "$remote" ]] || remote="$(git_remote || true)"
    [[ -n "$remote" ]] || die "discover: no git remote found (use --remote)"
    (( path_given )) || path="$(git_prefix)"
    path="${path%/}"

    local canonical results
    canonical="$(normalize_remote "$remote")"
    results="$(api_get "/application?repository_url=$(url_encode "$canonical")&limit=100")"
    if [[ "$(jq -r '.results | length' <<<"$results")" == "0" ]]; then
        results="$(api_get "/application?repository_url=$(url_encode "$canonical.git")&limit=100")"
    fi
    jq -c --arg url "$canonical" --arg path "$path" '
        [ .results[] | {id, name, slug, namespace_id, is_mono_repo, repository_app_path} ] as $c
        | ($c | map(select((.repository_app_path // "" | sub("/$"; "")) == $path))) as $by_path
        | { canonical_url: $url,
            candidates: $c,
            match: ( if ($c | length) == 1 and ($c[0].is_mono_repo != true) then $c[0].id
                     elif ($by_path | length) == 1 then $by_path[0].id
                     else null end ) }' <<<"$results"
}

# Is application <id> the one this repository belongs to? Exact match of the
# canonical repository URL, plus repository_app_path for monorepo applications.
cmd_match_app() {
    local app_id="" remote="" path="" remote_given=0 path_given=0
    [[ $# -gt 0 && "$1" != --* ]] && { app_id="$1"; shift; }
    while [[ $# -gt 0 ]]; do case "$1" in
        --app)    app_id="$2"; shift 2 ;;
        --remote) remote="$2"; remote_given=1; shift 2 ;;
        --path)   path="$2"; path_given=1; shift 2 ;;
        *) die "match-app: unknown option $1" ;;
    esac; done
    [[ "$app_id" =~ ^[0-9]+$ ]] || die "match-app: numeric application id required"
    (( remote_given )) || remote="$(git_remote || true)"
    [[ -n "$remote" ]] || die "match-app: no git remote found (use --remote)"
    (( path_given )) || path="$(git_prefix)"
    path="${path%/}"

    local canonical app
    canonical="$(normalize_remote "$remote")"
    app="$(api_get "/application/$app_id" 2>/dev/null || true)"
    [[ "$(jq -r '.id // empty' <<<"$app" 2>/dev/null)" == "$app_id" ]] || { CODE=1 die "match-app: application $app_id not found (or not accessible)"; }

    local app_repo="" app_path="" match=false reason
    app_repo="$(jq -r '.repository_url // empty' <<<"$app")"
    [[ -n "$app_repo" ]] && app_repo="$(normalize_remote "$app_repo" 2>/dev/null || echo "$app_repo")"
    if [[ "$(jq -r '.is_mono_repo // false' <<<"$app")" == "true" ]]; then
        app_path="$(jq -r '.repository_app_path // empty' <<<"$app")"; app_path="${app_path%/}"
    fi
    if [[ -z "$app_repo" ]]; then reason="application has no repository_url"
    elif [[ "$app_repo" != "$canonical" ]]; then reason="repository differs: $app_repo vs $canonical"
    elif [[ -n "$app_path" && "$app_path" != "$path" ]]; then reason="monorepo path differs: $app_path vs ${path:-<root>}"
    else match=true; reason="repository${app_path:+ and path} match"
    fi
    jq -cn --argjson m "$match" --arg id "$app_id" --arg slug "$(jq -r '.slug // .name' <<<"$app")" \
        --arg url "$canonical" --arg path "$path" --arg reason "$reason" \
        '{match:$m, application_id:$id, application_slug:$slug, canonical_url:$url, path:$path, reason:$reason}'
    [[ "$match" == "true" ]]
}

cmd_init() {
    local app_id="" link="" write=0 force=0 root=""
    while [[ $# -gt 0 ]]; do case "$1" in
        --app)   app_id="$2"; shift 2 ;;
        --link)  link="$2"; shift 2 ;;
        --write) write=1; shift ;;
        --force) force=1; shift ;;
        --root)  root="$2"; shift 2 ;;
        *) die "init: unknown option $1" ;;
    esac; done

    local link_json="" base_url="" link_account="" link_namespace=""
    if [[ -n "$link" ]]; then
        link_json="$(cmd_parse_link "$link")"
        [[ -n "$app_id" ]] || app_id="$(jq -r .application_id <<<"$link_json")"
        base_url="$(jq -r .base_url <<<"$link_json")"
        link_account="$(jq -r .account_id <<<"$link_json")"
        link_namespace="$(jq -r .namespace_id <<<"$link_json")"
    fi
    [[ -n "$app_id" ]] || die "init: --app <id> or --link <ui-link> is required"
    [[ "$app_id" =~ ^[0-9]+$ ]] || die "init: application id must be numeric: $app_id"

    local app
    app="$(api_get "/application/$app_id" 2>/dev/null || true)"
    [[ "$(jq -r '.id // empty' <<<"$app" 2>/dev/null)" == "$app_id" ]] || { CODE=1 die "init: application $app_id not found (or not accessible)"; }

    local nrn slug account_id namespace_id org_id
    nrn="$(jq -r '.nrn // ""' <<<"$app")"
    slug="$(jq -r '.slug // .name' <<<"$app")"
    account_id="$(nrn_field "$nrn" account)"
    namespace_id="$(nrn_field "$nrn" namespace)"
    org_id="$(nrn_field "$nrn" organization)"
    [[ -n "$namespace_id" ]] || namespace_id="$(jq -r '.namespace_id // ""' <<<"$app")"
    if [[ -n "$link_account" && -n "$account_id" && "$link_account" != "$account_id" ]]; then
        echo "np-context: link says account $link_account but the application's NRN says $account_id; using the NRN" >&2
    fi
    if [[ -n "$link_namespace" && -n "$namespace_id" && "$link_namespace" != "$namespace_id" ]]; then
        echo "np-context: link says namespace $link_namespace but the application's NRN says $namespace_id; using the NRN" >&2
    fi
    [[ -n "$account_id" ]] || account_id="$link_account"

    if [[ -z "$base_url" && -n "${NP_LOGIN_URL:-}" ]]; then base_url="$(url_origin "$NP_LOGIN_URL")"; fi
    if [[ -z "$base_url" ]]; then
        local org_slug=""
        [[ -n "$org_id" ]] && org_slug="$(api_get "/organization/$org_id" 2>/dev/null | jq -r '.slug // empty' || true)"
        [[ -n "$org_slug" ]] || { CODE=1 die "init: cannot derive base_url (no link, no NP_LOGIN_URL, organization slug unavailable)"; }
        base_url="https://$org_slug.app.nullplatform.io"
    fi

    local repo_url repo_name app_path="" is_mono
    repo_url="$(jq -r '.repository_url // empty' <<<"$app")"
    [[ -n "$repo_url" ]] || repo_url="$(git_remote || true)"
    if [[ -n "$repo_url" ]]; then
        repo_url="$(normalize_remote "$repo_url")"
        repo_name="${repo_url#https://*/}"
    fi
    is_mono="$(jq -r '.is_mono_repo // false' <<<"$app")"
    [[ "$is_mono" == "true" ]] && app_path="$(jq -r '.repository_app_path // empty' <<<"$app")"

    local yaml
    yaml="version: 1"$'\n'
    if [[ -n "$repo_url" ]]; then
        yaml+="repository:"$'\n'"  name: $repo_name"$'\n'"  url: $repo_url"$'\n'
        [[ -n "$app_path" ]] && yaml+="  app_path: ${app_path%/}"$'\n'
    fi
    yaml+="nullplatform:"$'\n'
    yaml+="  base_url: $base_url"$'\n'
    yaml+="  account_id: \"$account_id\""$'\n'
    yaml+="  namespace_id: \"$namespace_id\""$'\n'
    yaml+="  application_id: \"$app_id\""$'\n'
    yaml+="  application_slug: $slug"$'\n'

    printf '%s' "$yaml"

    if (( write )); then
        root="$(project_root "$root")"
        local target="$root/.np/application.yaml"
        if [[ -f "$target" ]] && ! (( force )) && [[ "$(cat "$target")" != "$(printf '%s' "$yaml")" ]]; then
            echo "np-context: $target exists with different content; re-run with --force to overwrite" >&2
            exit 4
        fi
        mkdir -p "$root/.np"
        printf '%s' "$yaml" > "$target"
        echo "np-context: wrote $target" >&2
    fi
}

# ---------- dispatch ----------

case "${1-}" in
    load)        shift; cmd_load "$@" ;;
    remote-url)  shift; cmd_remote_url "$@" ;;
    parse-link)  shift; cmd_parse_link "$@" ;;
    discover)    shift; cmd_discover "$@" ;;
    match-app)   shift; cmd_match_app "$@" ;;
    init)        shift; cmd_init "$@" ;;
    -h|--help|help|"") usage; [[ -n "${1-}" ]] || exit 2 ;;
    *) die "unknown command: $1" ;;
esac
