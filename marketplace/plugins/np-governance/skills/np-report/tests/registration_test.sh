#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # → marketplace/plugins/np-developer
S="$ROOT/settings.json"; P="$ROOT/.claude-plugin/plugin.json"
fails=0
j() { python3 -c "import json,sys;print(json.load(open('$1'))$2)" 2>/dev/null; }

allow="$(j "$S" "['permissions']['allow']")"
echo "$allow" | grep -q "Skill(np-report)" || { echo "FAIL: Skill(np-report) not allowlisted"; fails=$((fails+1)); }
# Version is bumped on every build; assert internal consistency (plugin.json == marketplace catalog)
# and a valid semver, rather than a brittle hardcoded number.
MP="$ROOT/../../../.claude-plugin/marketplace.json"
pv="$(j "$P" "['version']")"
mv="$(python3 -c "import json;print([p['version'] for p in json.load(open('$MP'))['plugins'] if p['name']=='np-developer'][0])" 2>/dev/null)"
echo "$pv" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "FAIL: plugin.json version not semver: '$pv'"; fails=$((fails+1)); }
[ -n "$pv" ] && [ "$pv" = "$mv" ] || { echo "FAIL: plugin.json version ($pv) != marketplace.json np-developer ($mv)"; fails=$((fails+1)); }
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
