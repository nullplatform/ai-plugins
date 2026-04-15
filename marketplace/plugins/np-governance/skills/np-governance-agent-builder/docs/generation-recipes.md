# Generation Recipes

This file is the **recipe Claude follows directly** to create a new agent skill in the **user's project**, after the wizard finishes. There is no template-rendering script — Claude reads this file, picks the right recipe based on `Agent type` from the state file, and writes each artifact with the `Write` tool, substituting the placeholders with concrete values.

Adapt content where it makes sense — for example, when `Action types` is `dependency_upgrade,config_change`, expand the `case` block in `execute.sh` into real branches (`dependency_upgrade) ... ;;` `config_change) ... ;;`) instead of leaving a `# TODO` comment.

## Where the agent goes

Generated agents live in the **user's project**, NOT in this repo:

```
<user-project>/
└── .claude/
    ├── state/
    │   └── agent-<<AGENT_NAME>>.md          # state file (written by Claude at wizard start)
    └── skills/
        └── np-governance-agent-<<AGENT_NAME>>/   # ← target dir
            ├── SKILL.md
            ├── docs/
            └── scripts/
```

All `Write` tool calls use **relative paths from cwd**: `.claude/skills/np-governance-agent-<<AGENT_NAME>>/...`. The user invokes the wizard from their project root, so cwd is the project root.

The generated skill is a **project-local skill**, not part of any plugin. We do NOT modify our `bundles.json` or `permissions/permissions.json` — those are build artifacts of the `np-governance` plugin itself.

## The discovery problem (why `_lib.sh` exists)

The generated agent's scripts need to call into `np-governance-action-items/scripts/*` (e.g., `ensure_category.sh`, `reconcile_action_items.sh`). Those live inside the installed `np-governance` plugin. But the generated skill is **project-local**, so `${CLAUDE_PLUGIN_ROOT}` is not set when its scripts run.

Solution: every generated agent ships with a small `scripts/_lib.sh` helper that discovers the plugin's path at runtime, regardless of how the script is invoked (Claude, cron, manual `bash`). All other scripts source it.

## Placeholder convention

When you see `<<TOKEN>>` below, replace it with the value from the state file:

| Token | State file field |
|-------|------------------|
| `<<AGENT_NAME>>` | Identity → Agent slug |
| `<<AGENT_TYPE>>` | Identity → Agent type |
| `<<PROBLEM>>` | Identity → Problem |
| `<<DOMAIN>>` | Identity → Domain |
| `<<CREATED_BY>>` | Frequency → Created-by tag (default `agent:<<AGENT_NAME>>`) |
| `<<OWNER>>` | Execution → Owner tag |
| `<<CATEGORY_SLUG>>` | Category → Slug |
| `<<CATEGORY_NAME>>` | Category → Name |
| `<<CATEGORY_DESCRIPTION>>` | Category → Description |
| `<<CATEGORY_COLOR>>` | Category → Color |
| `<<CATEGORY_ICON>>` | Category → Icon |
| `<<UNIT_NAME>>` | Category → Unit name |
| `<<UNIT_SYMBOL>>` | Category → Unit symbol |
| `<<METADATA_KEY>>` | Idempotency → Primary metadata key |
| `<<ACTION_TYPES>>` | Execution → Action types (CSV — expand into individual `case` branches) |
| `<<NRN_DEFAULT>>` | Frequency → Default NRN |
| `<<TIMESTAMP>>` | current ISO8601 (`date -u +"%Y-%m-%dT%H:%M:%SZ"`) |

## Files to create per agent type

| File | detector | executor | both |
|------|:--------:|:--------:|:----:|
| `SKILL.md` | ✓ | ✓ | ✓ |
| `docs/overview.md` | ✓ | ✓ | ✓ |
| `docs/detect.md` | ✓ |   | ✓ |
| `docs/execute.md` |   | ✓ | ✓ |
| `scripts/_lib.sh` | ✓ | ✓ | ✓ |
| `scripts/setup_category.sh` | ✓ |   | ✓ |
| `scripts/detect.sh` | ✓ |   | ✓ |
| `scripts/execute.sh` |   | ✓ | ✓ |
| `scripts/run_once.sh` | ✓ | ✓ | ✓ |

After writing all scripts: `chmod +x .claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/*.sh`

---

## Template: SKILL.md (type=both)

For type `detector`, drop the executor sections (Owner, Action types, execute.sh row, poll/hold/execute steps in "How it works"). For type `executor`, drop the category/detect sections and the setup_category.sh / detect.sh rows.

```markdown
---
name: np-governance-agent-<<AGENT_NAME>>
description: Governance action item agent for <<DOMAIN>>. <<PROBLEM>>. Use when the user wants to scan for, create, or remediate action items in this domain.
allowed-tools: Bash(./.claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/*.sh)
---

# <<AGENT_NAME>>

**Type**: <<AGENT_TYPE>>
**Domain**: <<DOMAIN>>
**Created by**: <<CREATED_BY>>
**Owner (executor)**: <<OWNER>>

## Purpose

<<PROBLEM>>

## How it works

1. **Setup category** (idempotent): ensures `<<CATEGORY_SLUG>>` exists.
2. **Detect**: scans for problems and outputs a JSON list keyed by `<<METADATA_KEY>>`.
3. **Reconcile**: creates new action items, closes obsolete ones (respects deferred / pending).
4. **Poll**: finds approved suggestions owned by `<<OWNER>>`.
5. **Hold check**: scans human comments for hold/abort instructions.
6. **Execute**: dispatches by `metadata.action_type` (one of: <<ACTION_TYPES>>).
7. **Report**: marks suggestions applied or failed.

## Critical Rules

- **Idempotency**: NEVER call `create_action_item.sh` directly. Always go through
  `reconcile_action_items.sh` or `search_action_items_by_metadata.sh` first.
  The unique key is `metadata.<<METADATA_KEY>>`.
- **No direct curl**: all API calls must go through `np-api/scripts/fetch_np_api_url.sh`.
- **user_metadata only contains scalars** (string, number, boolean, null).
- Respect hold/abort instructions before executing.

## Scripts

| Script | Purpose |
|--------|---------|
| `setup_category.sh` | Create or update the `<<CATEGORY_SLUG>>` category (idempotent). |
| `detect.sh` | Scan, build problems list, reconcile action items. |
| `execute.sh` | Poll approved suggestions and apply them. |
| `run_once.sh` | Convenience: run setup_category + detect + execute. |

## Quick start

```bash
./.claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/run_once.sh
./.claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/run_once.sh "organization=42"
```

## Requirements

This agent depends on the `np-governance` plugin being installed (it provides `np-governance-action-items` and `np-api`, which the scripts call into via `_lib.sh` discovery). If you see `cannot locate np-governance-action-items scripts`, install the plugin or set `NP_GOVERNANCE_AI_SCRIPTS=/absolute/path/to/np-governance-action-items/scripts`.
```

---

## Template: docs/overview.md

```markdown
# Agent: <<AGENT_NAME>>

**Type**: <<AGENT_TYPE>>
**Domain**: <<DOMAIN>>
**Created by**: <<CREATED_BY>>
**Generated at**: <<TIMESTAMP>>

## Purpose

<<PROBLEM>>

## Idempotency

This agent uses `<<METADATA_KEY>>` as the primary metadata key to identify
unique problems. Before creating an action item, it searches for existing items
matching this key.

## Category

- Slug: <<CATEGORY_SLUG>>
- Name: <<CATEGORY_NAME>>
- Unit: <<UNIT_NAME>> (<<UNIT_SYMBOL>>)

## Customization

Edit `scripts/detect.sh` (and/or `scripts/execute.sh`) with your domain-specific logic.
```

---

## Template: docs/detect.md (only for detector / both)

```markdown
# Detection logic

The detector for `<<AGENT_NAME>>` is in `scripts/detect.sh`. It scans for problems,
maps each one to a metadata object containing `<<METADATA_KEY>>` as the unique
identifier, and calls `reconcile_action_items.sh` to sync state.

## Where to customize

Look for the comment `# TODO: replace with real scan` in `detect.sh` and replace
it with your actual scanning logic. The output must be a JSON array where each
element has at least:

\`\`\`json
{
  "title": "human readable title",
  "priority": "high|medium|low",
  "metadata": {
    "<<METADATA_KEY>>": "<unique-value>"
  }
}
\`\`\`
```

---

## Template: docs/execute.md (only for executor / both)

```markdown
# Execution logic

The executor for `<<AGENT_NAME>>` is in `scripts/execute.sh`. It polls for
approved suggestions owned by `<<OWNER>>`, checks for hold/abort instructions
in human comments, and dispatches by `metadata.action_type`.

## Action types handled

<<ACTION_TYPES>>

## Where to customize

Look for the `ACTION HANDLERS` section in `execute.sh` and add a case for each
action type your executor knows how to handle. Each case should set `RESULT_OK`
and `RESULT_MSG`.
```

---

## Template: scripts/_lib.sh (always)

This is the discovery helper sourced by every other script in the generated agent. It locates the `np-governance-action-items/scripts` directory regardless of whether `${CLAUDE_PLUGIN_ROOT}` is set.

```bash
#!/bin/bash
#
# _lib.sh - Common helpers for <<AGENT_NAME>>.
#
# Generated by np-governance-agent-builder.
# Sourced by setup_category.sh, detect.sh, execute.sh.
#
# Locates np-governance-action-items/scripts at runtime so the generated
# agent works whether invoked by Claude (with $CLAUDE_PLUGIN_ROOT set) or
# from cron / CI / a plain shell.

# find_gov_scripts: prints the path to np-governance-action-items/scripts
# Search order:
#   1. $NP_GOVERNANCE_AI_SCRIPTS  (explicit override)
#   2. $CLAUDE_PLUGIN_ROOT/skills/np-governance-action-items/scripts
#   3. $HOME/.claude/plugins/**/np-governance-action-items/scripts
#   4. find $HOME/.claude (one-time fallback)
find_gov_scripts() {
    local d
    if [ -n "${NP_GOVERNANCE_AI_SCRIPTS:-}" ] && [ -x "${NP_GOVERNANCE_AI_SCRIPTS}/ensure_category.sh" ]; then
        echo "${NP_GOVERNANCE_AI_SCRIPTS}"
        return 0
    fi
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/ensure_category.sh" ]; then
        echo "${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts"
        return 0
    fi
    for d in \
        "${HOME}/.claude/plugins/np-governance/skills/np-governance-action-items/scripts" \
        "${HOME}/.claude/plugins/marketplace/np-governance/skills/np-governance-action-items/scripts" \
        "${HOME}/.claude/plugins/nullplatform/np-governance/skills/np-governance-action-items/scripts"
    do
        if [ -x "${d}/ensure_category.sh" ]; then
            echo "${d}"
            return 0
        fi
    done
    # Fallback: scan ~/.claude (slow but exhaustive)
    local found
    found=$(find "${HOME}/.claude" -type d -name 'np-governance-action-items' 2>/dev/null | head -1)
    if [ -n "${found}" ] && [ -x "${found}/scripts/ensure_category.sh" ]; then
        echo "${found}/scripts"
        return 0
    fi
    cat <<EOF >&2
Error: cannot locate np-governance-action-items scripts.

This agent depends on the np-governance plugin. Either:
  1. Install it: /plugin install np-governance@nullplatform
  2. Or set the explicit path:
       export NP_GOVERNANCE_AI_SCRIPTS=/absolute/path/to/np-governance-action-items/scripts
EOF
    return 1
}

GOV_SCRIPTS="$(find_gov_scripts)" || exit 1
export GOV_SCRIPTS
```

---

## Template: scripts/setup_category.sh (detector / both)

```bash
#!/bin/bash
# Generated for <<AGENT_NAME>>
# Idempotent: safe to run on every agent start.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

NRN="${1:-<<NRN_DEFAULT>>}"

"${GOV_SCRIPTS}/ensure_category.sh" \
  --nrn "$NRN" \
  --slug "<<CATEGORY_SLUG>>" \
  --name "<<CATEGORY_NAME>>" \
  --description "<<CATEGORY_DESCRIPTION>>" \
  --color "<<CATEGORY_COLOR>>" \
  --icon "<<CATEGORY_ICON>>" \
  --unit-name "<<UNIT_NAME>>" \
  --unit-symbol "<<UNIT_SYMBOL>>"
```

---

## Template: scripts/detect.sh (detector / both)

```bash
#!/bin/bash
# Generated detector for <<AGENT_NAME>>
# Domain: <<DOMAIN>>
# Generated at: <<TIMESTAMP>>
#
# Customize the SCAN section with your detection logic.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

NRN="${1:-<<NRN_DEFAULT>>}"

# 1. Ensure category exists (idempotent)
"${SCRIPT_DIR}/setup_category.sh" "$NRN" >/dev/null

# 2. SCAN — replace with your detection logic.
#    Output must be a JSON array of objects with at least:
#    { "title": "...", "priority": "high|medium|low",
#      "metadata": { "<<METADATA_KEY>>": "<unique-value>" } }
PROBLEMS_FILE="$(mktemp -t <<AGENT_NAME>>-problems.XXXXXX.json)"
trap 'rm -f "$PROBLEMS_FILE"' EXIT

# TODO: replace with real scan
echo "[]" > "$PROBLEMS_FILE"

# 3. Reconcile (creates new, closes obsolete; respects deferred & pending_*)
"${GOV_SCRIPTS}/reconcile_action_items.sh" \
  --nrn "$NRN" \
  --created-by "<<CREATED_BY>>" \
  --category-slug "<<CATEGORY_SLUG>>" \
  --metadata-key "<<METADATA_KEY>>" \
  --problems-file "$PROBLEMS_FILE"
```

---

## Template: scripts/execute.sh (executor / both)

When `<<ACTION_TYPES>>` is e.g. `dependency_upgrade,config_change`, expand the `case` block into one branch per type, instead of leaving the `# TODO` comment.

```bash
#!/bin/bash
# Generated executor for <<AGENT_NAME>>
# Owner: <<OWNER>>
# Generated at: <<TIMESTAMP>>
#
# Polls approved suggestions owned by <<OWNER>>, checks for hold, dispatches
# by metadata.action_type, and reports success/failure.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/_lib.sh"

NRN="${1:-<<NRN_DEFAULT>>}"
OWNER="<<OWNER>>"

# 1. Find approved suggestions for this owner
APPROVED=$("${GOV_SCRIPTS}/poll_approved_suggestions.sh" \
    --owner "$OWNER" --nrn "$NRN" --include-failed)

# 2. Iterate
echo "$APPROVED" | jq -c '.[]' | while read -r entry; do
    AI_ID=$(echo "$entry" | jq -r '.action_item.id')
    S_ID=$(echo "$entry" | jq -r '.suggestion.id')
    ACTION_TYPE=$(echo "$entry" | jq -r '.suggestion.metadata.action_type // "unknown"')

    # 2a. Check hold from human comments
    HOLD=$("${GOV_SCRIPTS}/check_action_item_hold.sh" --id "$AI_ID")
    if [ "$(echo "$HOLD" | jq -r '.should_proceed')" = "false" ]; then
        echo "Skipping $AI_ID: $(echo "$HOLD" | jq -r '.hold_reason')" >&2
        continue
    fi

    # 2b. Comment: execution started
    "${GOV_SCRIPTS}/add_comment.sh" \
        --id "$AI_ID" \
        --author "$OWNER" \
        --content "Execution started by <<AGENT_NAME>>. Processing suggestion ${S_ID} (action_type=${ACTION_TYPE})."

    # 2c. ACTION HANDLERS — one branch per action type
    RESULT_OK="false"
    RESULT_MSG="not handled"
    case "$ACTION_TYPE" in
        # Generate one branch per item in <<ACTION_TYPES>>:
        # example_action)
        #     # do work; set RESULT_OK / RESULT_MSG
        #     RESULT_OK="true"
        #     RESULT_MSG="example action applied"
        #     ;;
        *)
            "${GOV_SCRIPTS}/mark_suggestion_failed.sh" \
                --action-item-id "$AI_ID" \
                --suggestion-id "$S_ID" \
                --execution-result "$(jq -nc --arg m "Unknown action_type: $ACTION_TYPE" '{success:false,message:$m}')"
            continue
            ;;
    esac

    # 2d. Report result
    if [ "$RESULT_OK" = "true" ]; then
        "${GOV_SCRIPTS}/mark_suggestion_applied.sh" \
            --action-item-id "$AI_ID" \
            --suggestion-id "$S_ID" \
            --execution-result "$(jq -nc --arg m "$RESULT_MSG" '{success:true,message:$m}')"
    else
        "${GOV_SCRIPTS}/mark_suggestion_failed.sh" \
            --action-item-id "$AI_ID" \
            --suggestion-id "$S_ID" \
            --execution-result "$(jq -nc --arg m "$RESULT_MSG" '{success:false,message:$m}')"
    fi
done
```

---

## Template: scripts/run_once.sh (always)

```bash
#!/bin/bash
# Generated entry point for <<AGENT_NAME>>
set -e
NRN="${1:-<<NRN_DEFAULT>>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -x "${SCRIPT_DIR}/detect.sh" ]; then
    echo "[<<AGENT_NAME>>] running detect.sh for nrn=${NRN}"
    "${SCRIPT_DIR}/detect.sh" "$NRN"
fi

if [ -x "${SCRIPT_DIR}/execute.sh" ]; then
    echo "[<<AGENT_NAME>>] running execute.sh for nrn=${NRN}"
    "${SCRIPT_DIR}/execute.sh" "$NRN"
fi

echo "[<<AGENT_NAME>>] cycle complete"
```

---

## After writing files

1. `chmod +x .claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/*.sh`
2. Update the state file: append generated paths under `## Generated artifacts`, set `**Current phase**: validation`.
3. Run `validate_generated.sh .claude/skills/np-governance-agent-<<AGENT_NAME>> --state-file .claude/state/agent-<<AGENT_NAME>>.md`
4. If validation passes, the state file is auto-marked `phase: complete`. Report a summary to the user with:
   - Path of the generated skill
   - Where to put real scan / action handler logic
   - How to test: `.claude/skills/np-governance-agent-<<AGENT_NAME>>/scripts/run_once.sh "<NRN>"`
   - Reminder that the np-governance plugin must be installed (or `NP_GOVERNANCE_AI_SCRIPTS` exported) for the agent to find its dependencies at runtime.
