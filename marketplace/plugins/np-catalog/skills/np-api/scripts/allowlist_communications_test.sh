#!/bin/bash
# Verifies the Communications write paths are allowlisted and that neighbours stay refused.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${SCRIPT_DIR}/fetch_np_api_url.sh"

# Load ALLOWED_MODIFY and is_modify_allowed without running the script.
eval "$(sed -n '/^ALLOWED_MODIFY=(/,/^)/p' "$F")"
eval "$(sed -n '/^is_modify_allowed() {/,/^}/p' "$F")"

fail=0
expect() {
    local want="$1" path="$2"
    if is_modify_allowed "$path"; then got=allowed; else got=refused; fi
    if [ "$got" != "$want" ]; then echo "FAIL: $path is $got, want $want"; fail=1; fi
}

expect allowed "communications/inbox_rule"
expect allowed "communications/inbox_rule/validate"
expect allowed "communications/inbox_rule/emission"
expect allowed "communications/inbox_rule/acme.security_finding/emission"
expect allowed "communications/inbox_rule/deployment.failed/organization_state"
expect allowed "communications/inbox_rule/deployment.failed/customization"
expect allowed "communications/inbox_rule/acme.security_finding/permanent"
expect allowed "communications/notification"
expect allowed "communications/notification/close"
expect allowed "communications/notification/00000036-0000-4000-8000-000000000000"
expect allowed "communications/render"
expect allowed "communications/delivery_destination/00000037-0000-4000-8000-000000000000/test"

# Neither the caller's own inbox nor delivery destination writes are exposed.
expect refused "communications/inbox_setting"
expect refused "communications/inbox/read_all"
expect refused "communications/delivery_destination"
expect refused "communications/delivery_destination/00000037-0000-4000-8000-000000000000"
expect refused "communications/render/extra"

[ "$fail" -eq 0 ] && echo "PASS: communications write paths allowlisted"
exit "$fail"
