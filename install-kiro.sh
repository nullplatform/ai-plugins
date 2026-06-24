#!/usr/bin/env bash
# install-kiro.sh — Install nullplatform ai-plugins as Kiro skills
#
# Usage:
#   ./install-kiro.sh [plugin-name ...]        # install specific plugins (local)
#   ./install-kiro.sh --global [plugin-name …] # install globally (~/.kiro)
#   ./install-kiro.sh --update [--global]      # pull latest from git and reinstall
#   ./install-kiro.sh --list                   # list available plugins
#   ./install-kiro.sh                          # interactive selection
#
# The script installs skills into .kiro/skills/ (or ~/.kiro/skills/ with --global)
# and creates/updates the nullplatform agent config.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="$REPO_ROOT/marketplace/plugins"

# Parse flags before other args
GLOBAL=false
UPDATE=false
args=()
for arg in "$@"; do
  case "$arg" in
    --global) GLOBAL=true ;;
    --update) UPDATE=true ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"

if $GLOBAL; then
  KIRO_DIR="${KIRO_INSTALL_DIR:-$HOME/.kiro}"
else
  KIRO_DIR="${KIRO_INSTALL_DIR:-.kiro}"
fi

# ── update mode ──────────────────────────────────────────────────────────────
if $UPDATE; then
  echo "→ Pulling latest from origin..."
  git -C "$REPO_ROOT" pull --ff-only
  echo ""
  # Re-detect which plugins were previously installed
  installed=()
  if [[ -d "$KIRO_DIR/skills" ]]; then
    for dir in "$MARKETPLACE"/*/; do
      plugin=$(basename "$dir")
      # Consider it installed if any of its skill dirs exist
      for skill_dir in "$dir/skills"/*/; do
        skill=$(basename "$skill_dir")
        if [[ -d "$KIRO_DIR/skills/$skill" ]]; then
          installed+=("$plugin")
          break
        fi
      done
    done
    # Deduplicate
    mapfile -t installed < <(printf '%s\n' "${installed[@]}" | sort -u)
  fi
  if [[ ${#installed[@]} -eq 0 ]]; then
    echo "No previously installed plugins detected. Run install-kiro.sh to install."
    exit 0
  fi
  echo "Re-installing: ${installed[*]}"
  echo ""
  exec "$0" $(${GLOBAL} && echo "--global") "${installed[@]}"
fi
SKILLS_DIR="$KIRO_DIR/skills"
AGENTS_DIR="$KIRO_DIR/agents"
AGENT_FILE="$AGENTS_DIR/nullplatform.json"

# ── helpers ──────────────────────────────────────────────────────────────────

list_plugins() {
  for dir in "$MARKETPLACE"/*/; do
    plugin=$(basename "$dir")
    desc=$(jq -r '.description // ""' "$dir/.claude-plugin/plugin.json" 2>/dev/null || echo "")
    printf "  %-30s %s\n" "$plugin" "$desc"
  done
}

# Collect all scripts allowed by a plugin's settings.json, resolving the real paths
collect_scripts() {
  local plugin_dir="$1"
  local settings="$plugin_dir/settings.json"
  [[ -f "$settings" ]] || return 0

  jq -r '.permissions.allow[]' "$settings" 2>/dev/null \
    | grep '^Bash(' \
    | sed 's/^Bash(\(.*\))$/\1/' \
    | sed 's|:.*$||' \
    | sed 's|^\./\.claude/skills/|'"$SKILLS_DIR"'/|'
}

# Build the shell allowedCommands list from all installed scripts
build_allowed_commands() {
  local -a cmds=()
  while IFS= read -r script; do
    [[ -n "$script" ]] && cmds+=("$script")
  done
  # Also allow the np CLI
  cmds+=("^np ")
  printf '%s\n' "${cmds[@]}"
}

install_plugin() {
  local plugin="$1"
  local plugin_dir="$MARKETPLACE/$plugin"

  if [[ ! -d "$plugin_dir" ]]; then
    echo "ERROR: plugin '$plugin' not found in $MARKETPLACE" >&2
    return 1
  fi

  echo "→ Installing $plugin..."

  # Copy skills directory
  local src_skills="$plugin_dir/skills"
  if [[ -d "$src_skills" ]]; then
    mkdir -p "$SKILLS_DIR"
    cp -r "$src_skills"/. "$SKILLS_DIR/"
    # Make all scripts executable
    find "$SKILLS_DIR" -name "*.sh" -exec chmod +x {} \;

    # Resolve the absolute path to SKILLS_DIR for substitution
    local abs_skills
    abs_skills="$(cd "$SKILLS_DIR" && pwd)"

    # Replace ${CLAUDE_PLUGIN_ROOT}/skills/ with the real path in all text files
    find "$SKILLS_DIR" \( -name "*.md" -o -name "*.sh" \) | while IFS= read -r f; do
      sed -i.bak \
        -e "s|\${CLAUDE_PLUGIN_ROOT}/skills/|${abs_skills}/|g" \
        -e "s|\${CLAUDE_PLUGIN_ROOT:-}/skills/|${abs_skills}/|g" \
        -e "s|\${CLAUDE_PLUGIN_ROOT:-\([^}]*\)}/skills/|${abs_skills}/|g" \
        "$f" && rm -f "$f.bak"
    done
  fi

  echo "  ✓ Skills copied to $SKILLS_DIR/"
}

# ── main ─────────────────────────────────────────────────────────────────────

# Parse args
if [[ "${1:-}" == "--list" ]]; then
  echo "Available plugins:"
  list_plugins
  exit 0
fi

selected_plugins=()

if [[ $# -gt 0 ]]; then
  selected_plugins=("$@")
else
  # Interactive selection
  echo "Available plugins:"
  list_plugins
  echo ""
  echo "Enter plugin names to install (space-separated), or press Enter for all:"
  read -r input
  if [[ -z "$input" ]]; then
    for dir in "$MARKETPLACE"/*/; do
      selected_plugins+=("$(basename "$dir")")
    done
  else
    read -ra selected_plugins <<< "$input"
  fi
fi

if [[ ${#selected_plugins[@]} -eq 0 ]]; then
  echo "No plugins selected. Exiting."
  exit 0
fi

echo ""
echo "Installing ${#selected_plugins[@]} plugin(s) into $KIRO_DIR/..."
echo ""

# Install each plugin
for plugin in "${selected_plugins[@]}"; do
  install_plugin "$plugin"
done

# ── Generate/update .kiro/agents/nullplatform.json ───────────────────────────

mkdir -p "$AGENTS_DIR"

# Collect skill:// resources — one per SKILL.md found
skill_resources=()
while IFS= read -r skill_md; do
  rel="${skill_md#"$KIRO_DIR/"}"
  skill_resources+=("skill://$rel")
done < <(find "$SKILLS_DIR" -name "SKILL.md" | sort)

# Collect allowed shell commands from all installed plugins
allowed_scripts=()
for plugin in "${selected_plugins[@]}"; do
  while IFS= read -r script; do
    [[ -n "$script" ]] && allowed_scripts+=("^$script")
  done < <(collect_scripts "$MARKETPLACE/$plugin")
done
# Add np CLI and deduplicate
allowed_scripts+=("^np ")
mapfile -t allowed_scripts < <(printf '%s\n' "${allowed_scripts[@]}" | sort -u)

# Build JSON arrays
resources_json=$(printf '%s\n' "${skill_resources[@]}" | jq -R . | jq -s .)
allowed_commands_json=$(printf '%s\n' "${allowed_scripts[@]}" | jq -R . | jq -s .)

# Merge into agent config (preserve existing fields if file exists)
if [[ -f "$AGENT_FILE" ]]; then
  existing=$(cat "$AGENT_FILE")
else
  existing='{}'
fi

jq \
  --argjson resources "$resources_json" \
  --argjson allowedCmds "$allowed_commands_json" \
  '. + {
    "name": "nullplatform",
    "description": "Nullplatform AI plugins — skills for operating nullplatform",
    "tools": ["read", "write", "shell", "grep", "glob"],
    "toolsSettings": {
      "shell": {
        "allowedCommands": $allowedCmds,
        "autoAllowReadonly": true
      }
    },
    "resources": $resources
  }' <<< "$existing" > "$AGENT_FILE"

echo ""
echo "✓ Agent config written to $AGENT_FILE"
echo ""
echo "Skills installed:"
find "$SKILLS_DIR" -name "SKILL.md" | sort | while read -r f; do
  name=$(grep '^name:' "$f" | head -1 | sed 's/name: *//')
  echo "  - $name (${f#"$SKILLS_DIR/"})"
done
echo ""
echo "To use: open Kiro in this directory and switch to the 'nullplatform' agent."
echo "  /agent nullplatform"
