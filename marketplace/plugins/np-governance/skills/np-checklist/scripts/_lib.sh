#!/bin/bash
#
# _lib.sh - Shared helpers for np-checklist scripts
#
# Provides:
#   - NP_API:                       path to np-api fetch_np_api_url.sh
#   - approval_path <endpoint>:     prefixes /approval gateway path
#   - urlencode <string>:           percent-encodes for query params
#   - require_arg <name> <value>:   errors if value is empty
#   - call_api <method> <path> [<data>]:  invokes np-api with proper flags
#   - load_definition_file <path>:  loads a YAML or JSON file and emits JSON
#
# All calls go through api.nullplatform.com/approval/* via np-api. If a
# /approval/* endpoint returns 404, the gateway route has not been deployed
# yet — escalate to the team, do NOT point at internal hosts.

set -e

# Path to np-api wrapper. Use ${CLAUDE_PLUGIN_ROOT} if available, else relative.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    NP_API="${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NP_API="${SCRIPT_DIR}/../../np-api/scripts/fetch_np_api_url.sh"
fi

if [ ! -x "$NP_API" ]; then
    echo "Error: np-api fetch script not found at $NP_API" >&2
    echo "Make sure the np-api skill is installed alongside np-checklist." >&2
    exit 1
fi

# Gateway prefix. Hardcoded — all calls go through api.nullplatform.com/approval/*.
APPROVAL_PREFIX="/approval"

approval_path() {
    echo "${APPROVAL_PREFIX}/$1"
}

urlencode() {
    local s="$1"
    local out=""
    local i c
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$out"
}

require_arg() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "Error: --${name} is required" >&2
        exit 1
    fi
}

call_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [ "$method" = "GET" ] || [ "$method" = "HEAD" ]; then
        "$NP_API" "$endpoint"
    else
        if [ -n "$data" ]; then
            "$NP_API" --method "$method" --data "$data" "$endpoint"
        else
            "$NP_API" --method "$method" "$endpoint"
        fi
    fi
}

# Read a YAML or JSON file and emit JSON. Uses python if YAML, else cat.
# Required to accept --definition-file in YAML form for human authoring.
load_definition_file() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Error: file not found: $path" >&2
        exit 1
    fi
    case "$path" in
        *.json)
            cat "$path"
            ;;
        *.yaml|*.yml)
            if ! command -v python3 >/dev/null 2>&1; then
                echo "Error: python3 is required to read YAML files" >&2
                exit 1
            fi
            python3 -c "
import sys, json
try:
    import yaml
except ImportError:
    sys.stderr.write('Error: pyyaml is required. Install with: pip3 install pyyaml\n')
    sys.exit(1)
with open(sys.argv[1]) as f:
    print(json.dumps(yaml.safe_load(f)))
" "$path"
            ;;
        *)
            # Try JSON parse; fallback to YAML
            if jq empty "$path" 2>/dev/null; then
                cat "$path"
            else
                load_definition_file "${path}.yaml" 2>/dev/null || {
                    echo "Error: cannot determine file format for $path (use .json/.yaml/.yml)" >&2
                    exit 1
                }
            fi
            ;;
    esac
}
