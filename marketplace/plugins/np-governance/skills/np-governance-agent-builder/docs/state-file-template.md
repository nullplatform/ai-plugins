# State File

The state file lives at `.claude/state/agent-<slug>.md` in the user's project. It is the **single source of truth** of the wizard and survives context compaction. Claude creates it at wizard start with the `Write` tool and updates it after every batch with `Edit`.

## Naming

`agent-<slug>.md` where `<slug>` is the kebab-case agent name (without the `np-governance-agent-` prefix).

Example: for an agent named `vuln-scanner`, the state file is `.claude/state/agent-vuln-scanner.md`.

## Initial state (write verbatim at wizard start)

When the wizard starts for a new agent, Claude uses the `Write` tool to create the state file with this exact content, substituting `<<SLUG>>` with the agent slug and `<<TIMESTAMP>>` with the current ISO8601 timestamp (`date -u +"%Y-%m-%dT%H:%M:%SZ"`):

```markdown
# Agent wizard state: <<SLUG>>

**Created at**: <<TIMESTAMP>>
**Current phase**: identity

This file is managed by `np-governance-agent-builder`. The wizard updates it
after each batch of `AskUserQuestion`. It is the source of truth that
survives context compaction.

## Identity

- Agent slug: <<SLUG>>
- Agent type: <pending>
- Problem: <pending>
- Domain: <pending>

## Category

- Strategy: <pending>
- Slug: <pending>
- Name: <pending>
- Description: <pending>
- Color: <pending>
- Icon: <pending>
- Unit name: <pending>
- Unit symbol: <pending>
- Config flags: <pending>

## Idempotency & metadata

- Primary metadata key: <pending>
- Other metadata keys: <pending>
- User metadata keys (scalars only): <pending>
- Include user_metadata_config: <pending>

## Execution (executor / both only)

- Owner tag: <pending>
- Action types: <pending>
- Retry policy: <pending>
- Respects hold/abort comments: <pending>

## Frequency & scope

- Frequency: <pending>
- Default NRN: <pending>
- Auto-register category on first run: <pending>
- Created-by tag: agent:<<SLUG>>

## Generated artifacts

(populated by Claude after writing the agent files; expected target:
`.claude/skills/np-governance-agent-<<SLUG>>/`)

## Validation

(populated by validate_generated.sh)
```

After each batch of `AskUserQuestion`, use `Edit` to replace the `<pending>` placeholders with the user's answers and advance `**Current phase**:` through these values: `identity → category → idempotency → execution → frequency → generation → validation → complete`.

## Phase progression

| Phase | What it means |
|-------|---------------|
| `identity` | Wizard just started, Batch 1 pending |
| `category` | Batch 1 done, Batch 2 pending |
| `idempotency` | Batch 2 done, Batch 3 pending |
| `execution` | Batch 3 done, Batch 4 pending (skip if type is detector/reconciler only) |
| `frequency` | Batch 4 done (or skipped), Batch 5 pending |
| `generation` | All batches done, writing agent files |
| `validation` | Files written, running validate_generated.sh |
| `complete` | All checks passed, agent ready to use |

## Resume detection

When the wizard starts, use `Glob(".claude/state/agent-*.md")` to find existing state files. For each match:

1. `Read` the file and parse `**Current phase**:` from the header
2. If `phase == complete`, ignore (it's a previously generated agent)
3. If `phase != complete`, ask the user via `AskUserQuestion`:
   - "Resume from `<phase>`"
   - "Restart from scratch"
   - "Cancel"

If the user picks Resume, read all filled-in sections and re-enter the wizard at the batch matching the current phase.

## Fully populated example (for reference)

Here is what a complete state file looks like after a successful wizard for a `vuln-scanner` agent:

```markdown
# Agent wizard state: vuln-scanner

**Created at**: 2026-04-08T17:00:00Z
**Current phase**: complete

## Identity

- Agent slug: vuln-scanner
- Agent type: both
- Problem: Detect open CVEs in deployed services and create PRs that bump to fixed versions
- Domain: Security

## Category

- Strategy: create-new
- Slug: security-vulnerability
- Name: Security Vulnerability
- Description: Open CVEs in deployed services
- Color: #DC2626
- Icon: shield
- Unit name: Risk Score
- Unit symbol: R
- Config flags: requires_verification, requires_approval_to_reject

## Idempotency & metadata

- Primary metadata key: cve_id
- Other metadata keys: cvss_score, severity, affected_package, current_version, fixed_version
- User metadata keys (scalars only): target_branch, auto_merge, reviewer
- Include user_metadata_config: yes

## Execution (executor / both only)

- Owner tag: executor:pr-creator
- Action types: dependency_upgrade, config_change
- Retry policy: max 3 attempts
- Respects hold/abort comments: yes

## Frequency & scope

- Frequency: cron (daily)
- Default NRN: organization=1
- Auto-register category on first run: yes
- Created-by tag: agent:vuln-scanner

## Generated artifacts

- Skill path: .claude/skills/np-governance-agent-vuln-scanner/
- Files created:
  - [x] SKILL.md
  - [x] docs/overview.md
  - [x] docs/detect.md
  - [x] docs/execute.md
  - [x] scripts/_lib.sh
  - [x] scripts/setup_category.sh
  - [x] scripts/detect.sh
  - [x] scripts/execute.sh
  - [x] scripts/run_once.sh

## Validation

- [x] SKILL.md has valid frontmatter (name + description)
- [x] All scripts have shebang and are executable
- [x] shellcheck passes
- [x] scripts/_lib.sh exists
- [x] Skill is under .claude/skills/
- [x] No curl direct invocation
- [x] user_metadata only contains scalars
- [x] detect.sh calls reconcile_action_items.sh
```
