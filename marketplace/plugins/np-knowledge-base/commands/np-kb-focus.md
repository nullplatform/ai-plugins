---
name: np-kb-focus
description: Re-analyse one application or the whole organization in the knowledge base with an intent (focus mode) after a context change — a new tool, lore, contract facet or question — asking for what is missing and running catalog-ia-focus or catalog-refocus on the engine.
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
argument-hint: [intent, or "kind=<tool|lore|facet|contract|question> refs=<a,b> apps=<id,id|all>"]
---

# Knowledge base: re-analyse with an intent

Load the focus guide and follow it:

@${CLAUDE_PLUGIN_ROOT}/skills/np-kb-extend/docs/focus.md

## Flow

1. Parse the argument. If `intent`, `kind`, `refs` or the target (one application id, a list, or `all`) is missing, ask for the missing ones with **one** `AskUserQuestion` batch (kind as options `tool | lore | facet | contract | question`; depth as options `default by kind (Recommended) | light | standard | deep`; write as `dry run (Recommended) | write to the catalog`).
2. One application → run `catalog-ia-focus` (`wf_C4c0OxHp6yth`); a list or `all` → run `catalog-refocus` (`wf_xkhqycojQ-bd`) with `applications` (empty = every app with a book) and `max_parallelism` 3. Use `/np-workflow run <id> --input k=v …` (→ Ver `/np-workflow`), always sending every input, empty when it does not apply.
3. Report from the outputs: `scope.rationale`, `tracks.grouping`, `agent_facets.entries`, `verification.findings_verified`, `book_patch.replaces / appends` (or `book_patch.error`), `recommendation`. If it is `deep-dive`, say the wrapper dispatched the full analysis.
