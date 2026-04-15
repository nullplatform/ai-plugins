---
name: np-governance-create-action-item-agent
description: Start a guided wizard to generate a new Governance Action Item agent (detector, executor, or both) inside the user's project at .claude/skills/np-governance-agent-<name>/. Asks about category, metadata identifiers, idempotency keys, and execution patterns; writes the skill files; validates the result.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
argument-hint: [agent-name]
---

# Create Governance Action Item Agent

You are about to start the wizard to generate a new governance agent **in the user's project** (not in this repo). Load the meta-skill and follow its instructions exactly.

@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/SKILL.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/wizard-flow.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/state-file-template.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/generation-recipes.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/post-generation-checks.md

## Where the agent goes

The generated agent lives in **the user's project**, at `.claude/skills/np-governance-agent-<name>/`. The cwd when this command runs is the user's project root, so all `Write` calls and the state file path are relative to cwd. **Never** modify our `bundles.json` or `permissions/permissions.json` — those are build artifacts of the `np-governance` plugin itself.

## Pre-flight

Run these checks **in order** before starting the wizard:

1. **Detect in-progress wizards**: `Glob(".claude/state/agent-*.md")`. If found, read each one to identify the phase, then ask the user (via `AskUserQuestion`) whether to **resume** an existing wizard or **start fresh**.
2. **Verify the np-governance plugin is installed**: confirm that `${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/model.md` exists. If not, abort and tell the user that the `np-governance` plugin must be installed first.
3. **Verify auth is configured**: run `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh`. If it fails, ask the user to configure `NP_API_KEY` or `NP_TOKEN` and abort.

## Usage

- `/np-governance-create-action-item-agent` — Full wizard from scratch (asks for agent name in batch 1)
- `/np-governance-create-action-item-agent <name>` — Resume the wizard for `<name>` if state exists, otherwise start a new one with that slug

## Instructions

Parse `$ARGUMENTS` to determine the agent slug:

1. **No arguments** → ask the user for the agent slug as part of Batch 1 (Identity).
2. **`<name>` provided** → validate it matches `^[a-z][a-z0-9-]*$` (repromt if not). Then `Glob` `.claude/state/agent-<name>.md`: if it exists, `Read` it and resume from the `**Current phase**:` value. If not, `Glob` `.claude/skills/np-governance-agent-<name>/` to check for collision; if no collision, use `Write` to create `.claude/state/agent-<name>.md` with the Initial state block from `docs/state-file-template.md` (substituting `<<SLUG>>` and `<<TIMESTAMP>>`), then begin Batch 1.

Then execute the wizard flow defined in `docs/wizard-flow.md`:

1. **Batch 1 — Identity** (4 questions: name, type, problem, domain) — `AskUserQuestion`
2. **Batch 2 — Category** (4 questions: strategy, slug, unit symbol, config flags) — `AskUserQuestion`
3. **Batch 3 — Idempotency & metadata** (4 questions: primary metadata key, other keys, user_metadata, user_metadata_config) — `AskUserQuestion`
4. **Batch 4 — Execution** (only if executor or both: 4 questions) — `AskUserQuestion`
5. **Batch 5 — Frequency & scope** (4 questions: frequency, NRN, auto-register, created_by tag) — `AskUserQuestion`

After **each batch**, update `.claude/state/agent-<name>.md` so the wizard survives compaction.

When all batches are complete:

1. Show the user a summary of the state file and confirm with `AskUserQuestion` ("Yes, generate now" / "Edit batch X" / "Cancel").
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/generation-recipes.md` and use the `Write` tool to create each file under `.claude/skills/np-governance-agent-<name>/`. Substitute the `<<...>>` placeholders with values from the state file. Adapt content where useful — for example, expand `Action types: foo,bar` into real `case foo)` / `case bar)` branches in `execute.sh` instead of leaving a `# TODO` comment. **Do not forget `scripts/_lib.sh`** — every other script sources it for runtime discovery of `np-governance-action-items`.
3. `chmod +x .claude/skills/np-governance-agent-<name>/scripts/*.sh`
4. Run `${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/scripts/validate_generated.sh .claude/skills/np-governance-agent-<name> --state-file .claude/state/agent-<name>.md` to validate the result.
5. If validation passes, the state file is automatically marked `phase: complete`. Report a summary to the user with:
   - Path of the generated skill (`.claude/skills/np-governance-agent-<name>/`)
   - List of customization TODOs (`detect.sh` SCAN section, `execute.sh` ACTION HANDLERS)
   - How to test: `./.claude/skills/np-governance-agent-<name>/scripts/run_once.sh "<NRN>"`
   - Reminder: the `np-governance` plugin must be installed (or `NP_GOVERNANCE_AI_SCRIPTS` exported) for the agent to find its dependencies at runtime via `_lib.sh`.
6. If validation fails, leave the state file in `phase: validation` and offer the user options (auto-fix, open files, rollback, leave as-is) per `docs/post-generation-checks.md`.

## Critical Rules

- **Never** use `curl` directly. The generated scripts must call into `np-governance-action-items/scripts/*` (which delegate to `np-api`).
- **Never** dump all questions as plain text — always use `AskUserQuestion`, max 4 questions per call.
- **Always** update the state file after every batch.
- **Never** modify `bundles.json` or `permissions/permissions.json` of this repo — the agent lives in the user's project, not in our plugin.
- **Force idempotency**: Batch 3 question 1 (primary metadata key) is mandatory. The wizard cannot proceed without it.
- **Always include `_lib.sh`** in the generated skill — without it, none of the other scripts can find their dependencies at runtime.
- Confirm with the user before generating files (after Batch 5, show a summary of state and ask for confirmation).
