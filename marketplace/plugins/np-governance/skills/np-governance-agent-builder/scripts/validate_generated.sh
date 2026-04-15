#!/bin/bash
#
# validate_generated.sh - Sanity-check a generated agent skill
#
# Usage:
#   validate_generated.sh <path-to-skill-dir> [--state-file <path>]
#
# Runs the 12 checks documented in docs/post-generation-checks.md.
# Exits 0 if all pass (warnings allowed), 1 if any error.

set -e

SKILL_DIR=""
STATE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --state-file) STATE_FILE="$2"; shift 2 ;;
        *)
            if [ -z "$SKILL_DIR" ]; then
                SKILL_DIR="$1"
                shift
            else
                echo "Unknown option: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "$SKILL_DIR" ]; then
    echo "Usage: validate_generated.sh <skill-dir> [--state-file <path>]" >&2
    exit 1
fi

if [ ! -d "$SKILL_DIR" ]; then
    echo "Error: skill directory not found: $SKILL_DIR" >&2
    exit 1
fi

SKILL_NAME=$(basename "$SKILL_DIR")
ERRORS=()
WARNINGS=()

# --- Check 1-2: SKILL.md frontmatter ---
SKILL_MD="${SKILL_DIR}/SKILL.md"
if [ ! -f "$SKILL_MD" ]; then
    ERRORS+=("SKILL.md missing")
else
    if ! grep -q "^name: ${SKILL_NAME}$" "$SKILL_MD"; then
        ERRORS+=("SKILL.md frontmatter missing or wrong 'name:' (expected: ${SKILL_NAME})")
    fi
    if ! grep -q "^description:" "$SKILL_MD"; then
        ERRORS+=("SKILL.md frontmatter missing 'description:'")
    fi
fi

# --- Check 3-4: shebangs and executable bit on all scripts ---
if [ -d "${SKILL_DIR}/scripts" ]; then
    for sh in "${SKILL_DIR}"/scripts/*.sh; do
        [ -e "$sh" ] || continue
        # Accept any shebang that ends in "bash" (e.g. #!/bin/bash, #!/usr/bin/env bash, #!/usr/local/bin/bash)
        if ! head -1 "$sh" | grep -qE '^#!.*[/ ]bash[[:space:]]*$'; then
            ERRORS+=("Missing or wrong shebang: $sh")
        fi
        if [ ! -x "$sh" ]; then
            chmod +x "$sh"
            WARNINGS+=("Made executable: $sh")
        fi
    done
fi

# --- Check 5: shellcheck (warning if not installed) ---
if command -v shellcheck >/dev/null 2>&1; then
    for sh in "${SKILL_DIR}"/scripts/*.sh; do
        [ -e "$sh" ] || continue
        if ! shellcheck -x "$sh" >/dev/null 2>&1; then
            WARNINGS+=("shellcheck reported issues: $sh")
        fi
    done
else
    WARNINGS+=("shellcheck not installed; skipping syntax checks")
fi

# --- Check 6: skill is installed at the expected project-local path ---
# Generated agents live at .claude/skills/np-governance-agent-<name>/, not in our repo.
EXPECTED_PARENT=".claude/skills"
SKILL_PARENT=$(dirname "$SKILL_DIR")
if [ "$(basename "$SKILL_PARENT")" != "skills" ] || [ "$(basename "$(dirname "$SKILL_PARENT")")" != ".claude" ]; then
    WARNINGS+=("Skill is not under .claude/skills/ — generated agents normally live there in the user's project (got: $SKILL_DIR)")
fi

# --- Check 7: discovery helper (_lib.sh) is present ---
LIB_SH="${SKILL_DIR}/scripts/_lib.sh"
if [ -d "${SKILL_DIR}/scripts" ] && [ ! -f "$LIB_SH" ]; then
    WARNINGS+=("scripts/_lib.sh missing — generated agents need it to discover np-governance-action-items at runtime")
fi

# --- Check 8: no direct curl ---
if [ -d "${SKILL_DIR}/scripts" ]; then
    if grep -rnE '^[[:space:]]*curl[[:space:]]' "${SKILL_DIR}/scripts/" 2>/dev/null; then
        ERRORS+=("Direct curl invocation found in scripts/ — must delegate to np-api")
    fi
fi

# --- Check 9: user_metadata only contains scalars (in templates) ---
# Best-effort grep: complain if templates show user_metadata containing { or [
if [ -d "${SKILL_DIR}/scripts" ]; then
    while IFS= read -r line; do
        WARNINGS+=("user_metadata may contain non-scalar value: $line")
    done < <(grep -rnE 'user[_-]metadata.*[\{\[]' "${SKILL_DIR}/scripts/" 2>/dev/null || true)
fi

# --- Check 10: detect.sh idempotency call ---
DETECT_SH="${SKILL_DIR}/scripts/detect.sh"
if [ -f "$DETECT_SH" ]; then
    if grep -q "create_action_item.sh" "$DETECT_SH"; then
        if ! grep -qE "search_action_items_by_metadata.sh|reconcile_action_items.sh" "$DETECT_SH"; then
            WARNINGS+=("detect.sh creates action items without calling search_action_items_by_metadata.sh or reconcile_action_items.sh first")
        fi
    fi
fi

# --- Check 11-12: state file presence and phase update ---
if [ -n "$STATE_FILE" ]; then
    if [ ! -f "$STATE_FILE" ]; then
        ERRORS+=("State file not found: $STATE_FILE")
    fi
fi

# --- Print summary ---
echo
echo "=== Validation report for: $SKILL_NAME ==="
if [ "${#WARNINGS[@]}" -gt 0 ]; then
    printf 'WARN: %s\n' "${WARNINGS[@]}"
fi

if [ "${#ERRORS[@]}" -eq 0 ]; then
    echo "OK: all validations passed (${#WARNINGS[@]} warnings)"

    # Update state file phase to "complete" if provided and exists
    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        sed -i.bak -e "s|^\*\*Current phase\*\*:.*|**Current phase**: complete|" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi

    exit 0
else
    printf 'ERROR: %s\n' "${ERRORS[@]}" >&2
    echo "FAILED: ${#ERRORS[@]} errors, ${#WARNINGS[@]} warnings" >&2
    exit 1
fi
