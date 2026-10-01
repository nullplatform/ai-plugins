#!/bin/bash
#
# catalog-api.sh - Thin adapter over np-api's fetch_np_api_url.sh that points
# at the nullplatform catalog (public API) instead of the NP control plane.
#
# Auth (NP_TOKEN / NP_API_KEY exchange + cache) is delegated entirely to
# np-api. This script's only responsibility is to translate the simple
# <METHOD> <path> [body] interface to fetch_np_api_url.sh's --method/--data flags.
#
# The allowlist that gates mutating methods lives in np-api/fetch_np_api_url.sh's
# ALLOWED_MODIFY array — the catalog paths (specifications, instances/*,
# actions/*, ...) are explicitly enumerated there. Adding a new mutating
# endpoint to the catalog requires updating that list too.
#
# Usage:
#   catalog-api.sh GET    /specifications
#   catalog-api.sh POST   /specifications '{"name":"Service","schema":{...}}'
#   catalog-api.sh PATCH  /instances/service/abc '{"status":"active"}'
#   catalog-api.sh DELETE /instances/service/abc
#
# Query strings are passed as part of the path:
#   catalog-api.sh GET '/instances/service?status=active&facets=status&limit=50'
#
# Environment:
#   NP_TOKEN / NP_API_KEY     resolved by np-api/fetch_np_api_url.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NP_API_SCRIPT="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"

usage() {
    cat >&2 <<EOF
Usage: catalog-api.sh <METHOD> <path> [body]

  METHOD: GET, POST, PATCH, DELETE
  path:   request path, query string included (e.g. '/instances/service?limit=50')
  body:   optional JSON string for POST/PATCH

Environment:
  NP_TOKEN                  bearer token (preferred)
  NP_API_KEY                alternative — np-api exchanges + caches in ~/.claude/
EOF
}

if [ $# -lt 2 ]; then
    usage
    exit 2
fi

METHOD="$1"
REQ_PATH="$2"
BODY="${3:-}"

if [ ! -x "$NP_API_SCRIPT" ]; then
    echo "[catalog-api] ERROR: cannot find np-api at $NP_API_SCRIPT" >&2
    echo "  np-catalog requires np-api to be installed alongside it." >&2
    echo "  Install: /plugin install np-catalog@nullplatform" >&2
    exit 1
fi

# Normalise the user-supplied resource path: ensure leading /
case "$REQ_PATH" in
    /*) ;;
    *)  REQ_PATH="/$REQ_PATH" ;;
esac

# Delegate to fetch_np_api_url.sh on its default public base URL. The catalog
# lives under /catalog there, so the prefix is added to the request path and
# the ALLOWED_MODIFY allowlist matches the full public spelling
# (e.g. "catalog/specifications/*", "catalog/instances/*").
REQ_PATH="/catalog${REQ_PATH}"

case "$METHOD" in
    GET|HEAD)
        exec "$NP_API_SCRIPT" --method "$METHOD" "$REQ_PATH"
        ;;
    POST|PATCH)
        # fetch_np_api_url.sh requires --data for non-DELETE writes; pass empty
        # body as '{}' so callers don't have to.
        exec "$NP_API_SCRIPT" --method "$METHOD" --data "${BODY:-{\}}" "$REQ_PATH"
        ;;
    DELETE)
        # Catalog DELETEs are body-less on purpose: the API rejects a DELETE
        # that carries a JSON content type with an empty body.
        exec "$NP_API_SCRIPT" --method DELETE "$REQ_PATH"
        ;;
    *)
        echo "[catalog-api] ERROR: unsupported method: $METHOD" >&2
        usage
        exit 2
        ;;
esac
