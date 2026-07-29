#!/bin/bash
#
# config.sh - Manage workflow config (secrets + variables) on the engine.
#
# Entries are addressed by a server-minted `cfg_…` id; the pair (name, place)
# is unique, where a place is a folder --path ('/', '/jira') XOR a --workflow
# ref (wf_… id or client key). Referenced from YAML as ${{ secrets.NAME }}
# (write-only, always redacted) or ${{ vars.NAME }} (plain).
#
# Usage:
#   config.sh list --path=/jira | --workflow=wf_abc [--ancestors]
#                                                   Entries DEFINED at that place.
#                                                   --ancestors: the whole chain (both axes),
#                                                   each row flagged effective=winner|shadowed.
#   config.sh get <cfg_id>                          One entry by id (value only for vars)
#   config.sh set <name> (--path=P | --workflow=W) [--secret] [--value=V]
#                                                   Idempotent upsert (create or rotate).
#                                                   Without --value the value is read from STDIN —
#                                                   PREFER stdin for secrets (keeps them off argv):
#                                                     printf '%s' "$TOKEN" | config.sh set JIRA_TOKEN --path=/jira --secret
#   config.sh rotate <cfg_id> [--value=V]           Rotate by id (value via stdin preferred)
#   config.sh delete <cfg_id>                       Delete by id
#
# Resolution precedence: workflow → deepest folder → ancestors → '/'. Same
# name at two places is SHADOWING (most specific wins), never a merge.
# The `secret` flag and `name` are immutable — delete + recreate to change.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

CMD="${1:-}"
shift || true

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

# Parse --path/--workflow into a query-string fragment. Sets PLACE_QS.
place_qs() {
  PLACE_QS=""
  local path="" wf=""
  for arg in "$@"; do
    case "$arg" in
      --path=*)     path="${arg#--path=}" ;;
      --workflow=*) wf="${arg#--workflow=}" ;;
    esac
  done
  if [ -n "$path" ] && [ -z "$wf" ]; then PLACE_QS="path=$(urlenc "$path")";
  elif [ -n "$wf" ] && [ -z "$path" ]; then PLACE_QS="workflow=$(urlenc "$wf")";
  else
    echo "Provide exactly one of --path= or --workflow=" >&2
    return 2
  fi
}

fail_on_error_body() { # $1: response body; prints+exits when it's an error payload
  if echo "$1" | jq -e '.error? // empty' >/dev/null 2>&1; then
    echo "$1" | jq . >&2
    exit 1
  fi
}

case "$CMD" in
  list)
    ANC=false
    for arg in "$@"; do [ "$arg" = "--ancestors" ] && ANC=true; done
    place_qs "$@" || exit 2
    QS="$PLACE_QS"; [ "$ANC" = true ] && QS="$QS&ancestors=true"
    BODY=$("$API" GET "/config?$QS") || exit $?
    fail_on_error_body "$BODY"
    COUNT=$(echo "$BODY" | jq -r '.data // [] | length')
    echo "Entries: $COUNT"
    if [ "$ANC" = true ]; then
      printf '%-18s %-28s %-8s %-10s %-20s %s\n' ID NAME SECRET EFFECTIVE PLACE VALUE
      echo "$BODY" | jq -r '.data[]? | [.id, .name, (.secret|tostring), (if .effective then "winner" else "shadowed" end), (.workflow // .path // ""), (.value // "(write-only)")] | @tsv' \
        | while IFS=$'\t' read -r i n s e p v; do printf '%-18s %-28s %-8s %-10s %-20s %s\n' "$i" "$n" "$s" "$e" "$p" "$v"; done
    else
      printf '%-18s %-28s %-8s %-28s %s\n' ID NAME SECRET VALUE UPDATED
      echo "$BODY" | jq -r '.data[]? | [.id, .name, (.secret|tostring), (.value // "(write-only)"), .updatedAt] | @tsv' \
        | while IFS=$'\t' read -r i n s v u; do printf '%-18s %-28s %-8s %-28s %s\n' "$i" "$n" "$s" "$v" "$u"; done
    fi
    ;;

  get)
    ID="${1:-}"
    if [ -z "$ID" ]; then echo "Usage: config.sh get <cfg_id>" >&2; exit 2; fi
    BODY=$("$API" GET "/config/$(urlenc "$ID")") || exit $?
    fail_on_error_body "$BODY"
    echo "$BODY" | jq .
    ;;

  set)
    NAME="${1:-}"; shift || true
    SECRET=false; VALUE=""; VALUE_SET=false; PATH_ARG=""; WF_ARG=""
    for arg in "$@"; do
      case "$arg" in
        --path=*)     PATH_ARG="${arg#--path=}" ;;
        --workflow=*) WF_ARG="${arg#--workflow=}" ;;
        --secret)     SECRET=true ;;
        --value=*)    VALUE="${arg#--value=}"; VALUE_SET=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 2 ;;
      esac
    done
    if [ -z "$NAME" ] || { [ -z "$PATH_ARG" ] && [ -z "$WF_ARG" ]; }; then
      echo "Usage: config.sh set <name> (--path=P | --workflow=W) [--secret] [--value=V]  (or value on stdin)" >&2
      exit 2
    fi
    if [ "$VALUE_SET" = false ]; then
      if [ -t 0 ]; then
        echo "No --value and stdin is a TTY. Pipe the value in (preferred for secrets):" >&2
        echo "  printf '%s' \"\$TOKEN\" | config.sh set $NAME --path=/jira --secret" >&2
        exit 2
      fi
      VALUE=$(cat)
    fi
    if [ -n "$PATH_ARG" ]; then
      BODY=$(jq -n --arg n "$NAME" --arg v "$VALUE" --arg p "$PATH_ARG" --argjson sec "$SECRET" '{name:$n, value:$v, secret:$sec, path:$p}')
    else
      BODY=$(jq -n --arg n "$NAME" --arg v "$VALUE" --arg w "$WF_ARG" --argjson sec "$SECRET" '{name:$n, value:$v, secret:$sec, workflow:$w}')
    fi
    RESP=$("$API" POST "/config" "$BODY") || { echo "$RESP" >&2; exit 1; }
    fail_on_error_body "$RESP"
    echo "$RESP" | jq '{id, name, path, workflow, secret, mode} | with_entries(select(.value != null))'
    ;;

  rotate)
    ID="${1:-}"; shift || true
    VALUE=""; VALUE_SET=false
    for arg in "$@"; do
      case "$arg" in
        --value=*) VALUE="${arg#--value=}"; VALUE_SET=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 2 ;;
      esac
    done
    if [ -z "$ID" ]; then echo "Usage: config.sh rotate <cfg_id> [--value=V]  (or value on stdin)" >&2; exit 2; fi
    if [ "$VALUE_SET" = false ]; then
      if [ -t 0 ]; then echo "No --value and stdin is a TTY — pipe the value in." >&2; exit 2; fi
      VALUE=$(cat)
    fi
    RESP=$("$API" PATCH "/config/$(urlenc "$ID")" "$(jq -n --arg v "$VALUE" '{value:$v}')") || { echo "$RESP" >&2; exit 1; }
    fail_on_error_body "$RESP"
    echo "$RESP" | jq '{id, name, mode}'
    ;;

  delete)
    ID="${1:-}"
    if [ -z "$ID" ]; then echo "Usage: config.sh delete <cfg_id>" >&2; exit 2; fi
    # Success is a 204 with an empty body; any body is an error payload
    # (the HTTP layer does not fail on 4xx/5xx).
    RESP=$("$API" DELETE "/config/$(urlenc "$ID")") || { echo "$RESP" >&2; exit 1; }
    if [ -n "$RESP" ]; then
      echo "$RESP" | jq . >&2 2>/dev/null || echo "$RESP" >&2
      exit 1
    fi
    echo "Deleted $ID"
    ;;

  *)
    sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
