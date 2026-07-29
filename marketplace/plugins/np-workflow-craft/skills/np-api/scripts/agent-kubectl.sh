#!/bin/bash
#
# Run read-only `kubectl get` or `kubectl logs` on the customer's cluster via
# the Nullplatform agent (agent-side wrappers at nullplatform/scopes/k8s/).
#
# Usage:
#   agent-kubectl.sh <get|logs> [--nrn <nrn>] [--selector key=value]... -- <kubectl-args...>
#
# Arguments:
#   <verb>           get | logs
#   --nrn            NRN for agent search. Default: organization=4
#   --selector k=v   Selector pair(s) to match the agent. Default: cluster=runtime
#                    Repeat to add more pairs (they merge into one selector object).
#   --               Separator. Everything after is passed through as kubectl args.
#
# Examples:
#   agent-kubectl.sh get -- pods -n nullplatform
#   agent-kubectl.sh get --selector service=sync-ad -- pods -n nullplatform
#   agent-kubectl.sh logs --selector cluster=runtime -- my-pod --tail 200 --previous
#
# Output: raw JSON from POST /controlplane/agent_command (same shape as the
# existing deploy-agent-dump.sh / scope-agent-dump.sh helpers). Read
# .executions[].results.stdOut for the kubectl output.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") <get|logs> [--nrn <nrn>] [--selector key=value]... -- <kubectl-args...>

Runs 'kubectl get' or 'kubectl logs' on the customer's cluster via the
Nullplatform agent. Read-only; passes through kubectl arguments verbatim.

Arguments:
  <verb>           get | logs
  --nrn            NRN for agent search. Default: organization=4
  --selector k=v   Selector pair(s). Default: cluster=runtime. Repeat to merge.
  --               Separator. Everything after is passed as kubectl args.

Examples:
  $(basename "$0") get -- pods -n nullplatform
  $(basename "$0") get --selector service=sync-ad -- pods -n nullplatform
  $(basename "$0") logs --selector cluster=runtime -- my-pod --tail 200 --previous
EOF
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

VERB="$1"
shift

case "$VERB" in
    get|logs) ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: first argument must be 'get' or 'logs' (got: '$VERB')" >&2; usage; exit 1 ;;
esac

NRN="organization=4"
SELECTOR_PAIRS=()
KUBECTL_ARGS=()
SAW_SEPARATOR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nrn)
            [[ $# -ge 2 ]] || { echo "Error: --nrn requires a value" >&2; exit 1; }
            NRN="$2"
            shift 2
            ;;
        --selector)
            [[ $# -ge 2 ]] || { echo "Error: --selector requires a value" >&2; exit 1; }
            if [[ "$2" != *=* ]]; then
                echo "Error: --selector expects key=value (got: '$2')" >&2
                exit 1
            fi
            SELECTOR_PAIRS+=("$2")
            shift 2
            ;;
        --)
            SAW_SEPARATOR=true
            shift
            KUBECTL_ARGS=("$@")
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unexpected argument '$1' before '--' separator" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "$SAW_SEPARATOR" != "true" ]] || [[ ${#KUBECTL_ARGS[@]} -eq 0 ]]; then
    echo "Error: missing kubectl args. Put them after '--'." >&2
    usage
    exit 1
fi

# Default selector if none supplied.
if [[ ${#SELECTOR_PAIRS[@]} -eq 0 ]]; then
    SELECTOR_PAIRS=("cluster=runtime")
fi

# Build selector JSON object via jq.
SELECTOR_JSON=$(printf '%s\n' "${SELECTOR_PAIRS[@]}" | jq -Rn '
    [inputs | capture("^(?<k>[^=]+)=(?<v>.*)$")]
    | map({(.k): .v})
    | add // {}
')

# Build arguments JSON array.
ARGS_JSON=$(printf '%s\n' "${KUBECTL_ARGS[@]}" | jq -Rn '[inputs]')

# Assemble the request body.
REQUEST_BODY=$(jq -n \
    --arg nrn "$NRN" \
    --argjson selector "$SELECTOR_JSON" \
    --arg cmdline "nullplatform/scopes/k8s/kubectl_${VERB}" \
    --argjson arguments "$ARGS_JSON" \
    '{
        nrn: $nrn,
        selector: $selector,
        command: {
            type: "exec",
            data: {
                cmdline: $cmdline,
                arguments: $arguments
            }
        }
    }')

# Delegate to fetch_np_api_url.sh (handles auth + curl).
"$SCRIPT_DIR/fetch_np_api_url.sh" --method POST --data "$REQUEST_BODY" "/controlplane/agent_command"
