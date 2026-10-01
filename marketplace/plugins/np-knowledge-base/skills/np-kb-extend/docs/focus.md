# Re-analysis with an intent (focus mode)

Plugging a source in, registering a lore, adding a facet to the contract or opening a question
changes the **context**, not the code. A deep-dive re-derives everything; the delta only reacts
to a diff. **Focus** re-analyses an app because the context changed, with the catalog as base:
the scope is computed mechanically before spending a token (nothing is dropped, only ordered),
a few light tracks run, verification uses the same bar, the book is patched **by section**, and
a partial bundle is written (never retracts).

## Inputs (`catalog-ia-focus` `wf_C4c0OxHp6yth`)

| Input | Meaning |
|---|---|
| `application_id` | the app |
| `intent` | what to look for and why, **English**; the agent receives it as its own `<intent>` block with the same authority as the curator's instructions |
| `focus_kind` + `focus_refs` (or `focus_json` `{kind, refs, depth?}`) | what changed: `kind` ∈ `tool | lore | facet | contract | question`; `refs` = tool names, lore keys, facet names or question ids |
| `depth` | `light | standard | deep`; default by kind: `tool` / `lore` / `question` → `light`, `facet` / `contract` → `standard`; `deep` = the node recommends a deep-dive and the wrapper dispatches `full` |
| `write` | `"true"` writes through the sink; `"false"` (default) produces outputs only |
| `np_api_key` | empty = `secrets.NP_API_KEY` of `/catalog` |
| `tools_json`, `contract_json`, `steps_json` | empty = the org config entries |
| `output_language` | `English` |

Scope by kind: `tool` with `resolves.scheme` → the facets whose entries can cite that scheme
plus the book claims about the source, every subsystem gets a light pass; `lore` / `question`
→ the book claims sharing terms with the text, their subsystems first; `facet` / `contract` →
produce those facets. `light` groups the subsystems into at most 3 tracks (one track per
subsystem cost three times more for the same result).

## The three common cases

```bash
# a new tool with `resolves` (a documentation site): map the app to its pages
/np-workflow run wf_C4c0OxHp6yth \
  --input application_id=<id> --input write=false \
  --input focus_kind=tool --input focus_refs=docs_search,docs_page \
  --input intent="Map this application to its pages in the documentation site using docs_search and docs_page. Produce the documentation facet and doc-drift findings where the documentation contradicts the code. Do not re-derive the book; only add or refresh the documentation section."

# a new lore key: re-judge the claims it touches, look for evidence, record violations as findings
/np-workflow run wf_C4c0OxHp6yth --input application_id=<id> --input write=true \
  --input focus_kind=lore --input focus_refs=payments-idempotency \
  --input intent="The org adopted the norm payments-idempotency; check whether this application follows it and record violations as findings."

# a new facet in the contract: produce it, nothing else
/np-workflow run wf_C4c0OxHp6yth --input application_id=<id> --input write=true \
  --input focus_kind=facet --input focus_refs=slo-targets --input depth=standard \
  --input intent="Produce the facet slo-targets declared in the contract from the code and the runbooks."
```

Always send the remaining inputs too (`depth`, `np_api_key`, `tools_json`, `contract_json`,
`steps_json`, `output_language`, `engine_url`), empty when they do not apply.

## Over many apps: `catalog-refocus` (`wf_xkhqycojQ-bd`)

Same `intent`, `focus_kind`, `focus_refs`, `depth`, `write`, plus `applications` (comma list of
application ids; empty = every app with a book) and `max_parallelism` (3). It fans out
`catalog-ia-focus` and aggregates per-app summaries (facets, findings, patched sections,
failures).

## What it writes with `write=true`

Facets merged by key; new edges and findings (category from the contract); the patched book
sections; `recent-changes` appended ("Re-analysis (focus) of <slug>"). A section whose heading
equals an existing one **replaces** it; any other heading is **appended**; a `human:curated` book
is never patched (the sink files a suggestion carrying the patch, → Ver `/np-kb-curate`). The
writer takes the **facet entries as a source**: a documentation focus produces no facts, only
entries, and that is enough for a section.

## What it costs (measured, one app, models routed through Bedrock, 2026-09-16)

| | Full deep-dive | Focus (documentation intent) |
|---|---|---|
| Duration | 10–15 min | ≈ 3 min |
| Agent tokens | 6–8 M | 1.1–1.3 M |
| Docs-tool calls | 60–90 | 33 |
| Touches | everything | the `documentation` facet, 5 `doc-drift` findings, one book section replaced |

Over 42 apps at `max_parallelism` 3: under an hour and ~50 M tokens, against ~8 h and ~300 M
as deep-dives.
