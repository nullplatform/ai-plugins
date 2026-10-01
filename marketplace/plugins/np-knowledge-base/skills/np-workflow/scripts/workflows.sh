#!/bin/bash
#
# workflows.sh - List workflow definitions or describe one.
#
# Usage:
#   workflows.sh                     List workflow definitions
#   workflows.sh describe <id>       Show definition + revisions + aliases + triggers
#
# Resource paths are the BARE engine paths (/definitions, /triggers, ...).
# workflow-api.sh prepends NP_WORKFLOW_BASE_PATH (default /workflows), so a path
# written as "/workflows" becomes /workflows/workflows and 404s. Definitions live
# under /definitions — there is no /workflows resource.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$SCRIPT_DIR/workflow-api.sh"

# The engine reports failures as RFC7807 problem+json, and the transport
# (fetch_np_api_url.sh runs `curl -s` with no --fail) exits 0 whatever the HTTP
# status. A caller that reads `.data // []` therefore renders a 404 as an empty
# list — which is how a "Workflows: 0" once hid 14 published workflows. Every
# response has to be screened for the error envelope before it is parsed.
#
# api_get <path> — echo the body, or explain the failure on stderr and return 1.
api_get() {
    local path="$1" body status title detail
    body=$("$API" GET "$path") || return 1

    if ! echo "$body" | jq -e . >/dev/null 2>&1; then
        echo "[workflows] ERROR: GET $path returned a non-JSON response:" >&2
        echo "$body" | head -5 | sed 's/^/  /' >&2
        return 1
    fi

    # problem+json carries a numeric .status. Guard on the numeric type so a
    # record with a string status (e.g. an execution's "running") is not
    # mistaken for an error.
    if echo "$body" | jq -e '(.status? | numbers) >= 400' >/dev/null 2>&1; then
        status=$(echo "$body" | jq -r '.status')
        title=$(echo "$body" | jq -r '.title // "error"')
        detail=$(echo "$body" | jq -r '.detail // ""')
        echo "[workflows] ERROR: GET $path -> HTTP $status ($title)" >&2
        [ -n "$detail" ] && echo "  $detail" >&2
        return 1
    fi

    echo "$body"
}

# print_list_section <label> <body> <jq-filter> — render a .data array, telling
# "the request failed" apart from "there is nothing here".
print_list_section() {
    local label="$1" body="$2" filter="$3" rows
    echo "$label:"
    if [ -z "$body" ]; then
        echo "  (unavailable - request failed)"
        return
    fi
    rows=$(echo "$body" | jq -r "$filter" 2>/dev/null)
    if [ -z "$rows" ]; then
        echo "  (none)"
    else
        echo "$rows"
    fi
}

CMD="${1:-list}"

if [ "$CMD" = "list" ] || [ "$CMD" = "" ]; then
    # Definitions are returned as {data, limit, offset, total}. The limit is the
    # page size, not a filter: when total exceeds it the count line says so
    # rather than quietly showing a short list.
    BODY=$(api_get "/definitions?limit=200") || exit 1

    if ! echo "$BODY" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
        echo "[workflows] ERROR: GET /definitions returned no .data array." >&2
        echo "  Response shape: $(echo "$BODY" | jq -c 'if type == "object" then keys else type end')" >&2
        exit 1
    fi

    SHOWN=$(echo "$BODY" | jq -r '.data | length')
    TOTAL=$(echo "$BODY" | jq -r 'if (.total | type) == "number" then .total else (.data | length) end')

    if [ "$SHOWN" -lt "$TOTAL" ]; then
        echo "Workflows: $SHOWN of $TOTAL (page limit reached)"
    else
        echo "Workflows: $TOTAL"
    fi
    echo ""

    # Definition records expose id/key/name; they carry no revision field, so
    # there is no revision column to show here (see `describe` for that).
    #
    # Ids are either `wf_<12>` or a client-chosen key of up to 63 chars, so the
    # columns are sized from the rows rather than fixed — a fixed width silently
    # skews every following column the first time a long key appears.
    ROWS=$(echo "$BODY" | jq -r '.data[]? | [.id, (.key // "-"), (.name // "")] | @tsv')
    IDW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v m=2 '{if (length($1) > m) m = length($1)} END {print m}')
    KEYW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v m=3 '{if (length($2) > m) m = length($2)} END {print m}')
    NAMEW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v m=4 '{if (length($3) > m) m = length($3)} END {print m}')
    rule() { printf '%*s' "$1" '' | tr ' ' '-'; }

    printf "%-${IDW}s  %-${KEYW}s  %s\n" ID KEY NAME
    printf "%-${IDW}s  %-${KEYW}s  %s\n" "$(rule "$IDW")" "$(rule "$KEYW")" "$(rule "$NAMEW")"
    [ -n "$ROWS" ] && printf '%s\n' "$ROWS" \
      | while IFS=$'\t' read -r id key name; do
          printf "%-${IDW}s  %-${KEYW}s  %s\n" "$id" "$key" "$name"
        done
    exit 0
fi

if [ "$CMD" = "describe" ]; then
    ID="${2:-}"
    if [ -z "$ID" ]; then
        echo "Usage: workflows.sh describe <id>" >&2
        exit 2
    fi

    # GET /definitions/:id answers {workflow, revision, resolvedVia} — the
    # record is nested under .workflow, and the revision it resolved to sits
    # alongside it. Reading these fields off the top level yields all nulls.
    WF=$(api_get "/definitions/$ID") || exit 1
    if ! echo "$WF" | jq -e '.workflow | type == "object"' >/dev/null 2>&1; then
        echo "[workflows] ERROR: GET /definitions/$ID returned no .workflow object." >&2
        echo "  Response shape: $(echo "$WF" | jq -c 'if type == "object" then keys else type end')" >&2
        exit 1
    fi

    echo "Workflow:"
    echo "$WF" | jq '.workflow + {
        currentRevision: .revision.revision,
        resolvedVia: .resolvedVia
    }'
    echo ""

    REVS=$(api_get "/definitions/$ID/revisions?limit=20") || REVS=""
    print_list_section "Revisions" "$REVS" \
      '.data[]? | "  r\(.revision)  \(.createdAt)  \(.message // "")"'
    echo ""

    ALIASES=$(api_get "/definitions/$ID/aliases") || ALIASES=""
    print_list_section "Aliases" "$ALIASES" \
      '.data[]? | "  \(.name) -> r\(.revision)  \(if .activatedAt then "[ACTIVE since " + .activatedAt + "]" else "[inactive]" end)"'
    echo ""

    TRIGS=$(api_get "/triggers?workflowId=$ID&status=active") || TRIGS=""
    print_list_section "Active triggers" "$TRIGS" \
      '.data[]? | "  [\(.aliasName) / \(.pluginType)] \(.triggerId) \(.runtimeMetadata.webhookUrl // "")"'
    exit 0
fi

echo "Usage: workflows.sh [list|describe <id>]" >&2
exit 2
