#!/bin/bash
#
# workflow-api.sh - Thin adapter over np-api's fetch_np_api_url.sh that points
# at the deployed workflow engine instead of the NP control plane.
#
# Auth (NP_TOKEN / NP_API_KEY exchange + cache) is delegated entirely to
# np-api. This script's only responsibilities are:
#   - resolve the target host from NP_WORKFLOW_URL
#   - tell np-api the REST base path (NP_WORKFLOW_BASE_PATH, default /api)
#   - translate the simple <METHOD> <path> [body] interface to
#     fetch_np_api_url.sh's --method/--data flags
#
# The allowlist that gates mutating methods lives in np-api/fetch_np_api_url.sh's
# ALLOWED_MODIFY array — the workflow engine paths (workflows, workflows/*,
# signals, executions/*/cancel, ...) are explicitly enumerated there.
# Adding a new mutating endpoint to the workflow engine requires updating that
# list too.
#
# Usage:
#   workflow-api.sh GET    /plugins
#   workflow-api.sh POST   /workflows '{"definition":{...}}'
#   workflow-api.sh PUT    /workflows/abc/aliases/live '{"revision":3}'
#   workflow-api.sh DELETE /workflows/abc
#
# Paths are written WITHOUT the /workflows prefix — workflow-api.sh prepends
# NP_WORKFLOW_BASE_PATH (default /workflows). If you pass a path that
# already starts with /workflows, /workflows/workflows/... will be produced;
# use the unprefixed form (e.g. "/definitions/abc" not "/workflows/definitions/abc").
#
# NOTE: the engine does NOT expose a /whoami endpoint. Identity is carried
# by the bearer token — decode the JWT payload or query the Nullplatform
# auth API if you need user details.
#
# Environment:
#   NP_WORKFLOW_URL        (required) base URL of the workflow engine
#   NP_WORKFLOW_BASE_PATH  (optional) REST prefix on that host. Default: /api
#   NP_TOKEN / NP_API_KEY  resolved by np-api/fetch_np_api_url.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NP_API_SCRIPT="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"

usage() {
    cat >&2 <<EOF
Usage: workflow-api.sh <METHOD> <path> [body]

  METHOD: GET, POST, PUT, PATCH, DELETE
  path:   request path WITHOUT the base prefix (e.g. /plugins, not /workflows/plugins)
  body:   optional JSON string for POST/PUT/PATCH

Environment:
  NP_WORKFLOW_URL        base URL of the workflow engine (required)
  NP_WORKFLOW_BASE_PATH  REST prefix on that host (default: /api)
  NP_TOKEN               bearer token (preferred)
  NP_API_KEY             alternative — np-api exchanges + caches in ~/.claude/
EOF
}

if [ $# -lt 2 ]; then
    usage
    exit 2
fi

METHOD="$1"
REQ_PATH="$2"
BODY="${3:-}"

# The engine is mounted publicly behind the NP control plane at
# api.nullplatform.com/workflows — same default as np-api. Override
# NP_WORKFLOW_URL only for self-hosted / non-production deployments.
NP_WORKFLOW_URL="${NP_WORKFLOW_URL:-https://api.nullplatform.com}"

if [ ! -x "$NP_API_SCRIPT" ]; then
    echo "[workflow-api] ERROR: cannot find np-api at $NP_API_SCRIPT" >&2
    echo "  np-workflow requires np-api to be installed alongside it." >&2
    echo "  Install: /plugin install np-workflow-craft@nullplatform" >&2
    exit 1
fi

# Normalise the user-supplied resource path: ensure leading /
case "$REQ_PATH" in
    /*) ;;
    *)  REQ_PATH="/$REQ_PATH" ;;
esac

# Delegate to fetch_np_api_url.sh with the workflow host + base path. The
# endpoint we pass is the bare RESOURCE path (no /api prefix) — fetch_np_api_url.sh
# uses NP_API_BASE_PATH to prepend the engine's REST prefix before calling out,
# and crucially the ALLOWED_MODIFY allowlist matches on this same bare path so
# patterns like "workflows/*" line up regardless of where the engine is mounted.
export NP_API_BASE_URL="${NP_WORKFLOW_URL%/}"
export NP_API_BASE_PATH="${NP_WORKFLOW_BASE_PATH:-/workflows}"

case "$METHOD" in
    GET|HEAD)
        exec "$NP_API_SCRIPT" --method "$METHOD" "$REQ_PATH"
        ;;
    POST|PUT|PATCH)
        # fetch_np_api_url.sh requires --data for non-DELETE writes; pass empty
        # body as '{}' so callers don't have to.
        exec "$NP_API_SCRIPT" --method "$METHOD" --data "${BODY:-{\}}" "$REQ_PATH"
        ;;
    DELETE)
        if [ -n "$BODY" ]; then
            exec "$NP_API_SCRIPT" --method DELETE --data "$BODY" "$REQ_PATH"
        else
            exec "$NP_API_SCRIPT" --method DELETE "$REQ_PATH"
        fi
        ;;
    *)
        echo "[workflow-api] ERROR: unsupported method: $METHOD" >&2
        usage
        exit 2
        ;;
esac
