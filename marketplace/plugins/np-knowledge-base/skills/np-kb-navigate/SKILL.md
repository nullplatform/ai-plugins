---
name: np-kb-navigate
description: Answer questions from the organizational knowledge base (the nullplatform catalog built by the KB pipeline) through the nullplatform MCP (`np_kb_read`, `np_kb_propose`) or the `np-catalog` MCP server — "what is X", "who uses X", "what breaks if X goes down", "how does X work", "which docs describe X", "which apps does this doc page affect", "how do I connect to X", "what findings does X have" — and how to behave when catalog_search returns empty, a node looks bare, a count contradicts another source, or a fact must be cited with its provenance.
---

# np-kb-navigate

Skill to **read** the organizational knowledge base: the components, facets, docs, edges,
lore and findings the KB pipeline writes into the nullplatform catalog for an organization.

## Critical Rules

1. **Every statement carries its source**: the `file:line` anchor the catalog cites, or the ref (`<component>~<facet>` / `~<doc>`) it came from. No anchor, no claim.
2. **"It is not in the catalog" is a valid answer** — say it explicitly. Literal source code is absent by design: deliver the cataloged summary plus the repo anchor.
3. **Every impact with its edge**: "A depends on / calls / breaks with B" needs the edge (from, `edge_type`, to, `via`). Without an edge it is a hypothesis and you say so.
4. **Graph beats lore when they clash**: lore says how something SHOULD be named; edges say what exists. Report what exists and flag the difference.
5. **Do not fill in what the catalog leaves open**: routes, payloads and mechanisms a tool did not return do not exist for the answer.
6. **After a write, read by deterministic id** (`get_*`), never through search or listings: the read index lags.
7. **Pick the surface you have.** If the tools list shows `np_kb_read`, you are on the nullplatform MCP: use its ops (→ `docs/np-mcp.md`, which has each op's params) and read the next table through the "`np_kb_read`" column. Otherwise use the **`np-catalog` MCP server** (→ `docs/surfaces.md`). Never raw `curl` against the catalog API; for the control plane → Ver `/np-api`.

8. **Go to the depth the question needs, and say the depth used.** "What breaks if X goes down" is
   not answered at depth 1: follow consumers until the chain ends or the intermediaries stop it,
   and state "depth N" in the answer.
9. **Never fold listed items into "etc."** List every item, or page through them, and say
   "N of TOTAL shown" if you stop.
10. **Before answering "unresolved", read what the result points to.** Read the book and the
    facets the component lists (`configuration`, `backing-services`, `documentation`) for the
    host, value or instance. Unresolved means not in any of them.
11. **For documentation, list every document the documentation facet names**: the repo's
    own README and other docs, and the wiki pages.
12. **When asked what configuration an app needs, separate the keys it needs to start**
    (no default, read at boot) from the optional ones, and say which are defined on the
    platform.
13. **A list of consumers or dependents always carries its coverage**: how many applications
    the catalog has analysed out of the platform's total. An app missing from the list may
    simply not be analysed.

## Question → path matrix

The `np_kb_read` column is the same path on the nullplatform MCP. A dash means the op does not exist there; use the listed alternative.

| Question | Path (`np-catalog`) | `np_kb_read` |
|---|---|---|
| What is X? | `get_component {ref}`. Bare page (core/infra usually are)? The knowledge lives in the consumers → `who_consumes {target}` → `get_facet` / `get_doc` of the 2-3 main ones | `get` → `graph` → `get include:["doc:book"]` |
| Who uses X / what breaks if it goes down? | `who_consumes` (direct, with evidence) + `blast_radius {node, direction: "inbound", depth: 2}` (transitive) | `graph` + `graph depth:2` |
| Exploratory / "where does it say…?" | `catalog_search {query}`; snippets carry the exact `ref` to hydrate | `search` |
| How do I approach this change or bug? | `plan_work {goal}` — norms + context + graph in one call | — : `search` → `get include:["norms"]` → `graph` |
| Which rules apply to X? | `get_norms {component}` (org → account → namespace → app chain resolved) | `get include:["norms"]` |
| Which investigation instructions apply to X? | `get_instructions {ref}` (lore `nature: instruction`, curator/product only) | `get` (`instructions_applicable`) |
| Org overview | `get_hierarchy` / `org_index` | `list view:"hierarchy"` / `list view:"apis"` |
| Who consumes X and with which operation? | `who_consumes {target}`: every edge carries `via` (`GET /user/{id}`, `publish <queue>`). No `via` = "operation not recorded", never inferred | `graph` |
| How do I connect to X? | `get_doc {component, doc: "book"}` → section "How to connect to this app"; older books: `get_facet endpoint-authz` + `runs-on-scope` in `get_component` | `get include:["doc:book"]` |
| Which findings does X have? | `list_findings {component}` — every finding carries `categoria` (`catalog-findings`, `doc-drift`, or a category the org declared) | `items type:"findings" ref:X` |
| Which documentation pages describe X? | `get_facet {component: X, facet: "documentation"}` (per page: `path`, `url`, `sections`, `describes`, `provenance`) or `get_component X` → `edges_out` of type `documented-by` | `get include:["facet:documentation"]` |
| Which apps does this documentation page affect? | the page is a node `doc:<path>`: `who_consumes {target: "doc:<path>"}` → apps with `documented-by` and the cited sections in `via`; `blast_radius` includes it | `graph ref:"doc:<path>"` |
| What does the doc say that the code does not do? | `list_findings {component}` filtered by `categoria: doc-drift`: two anchors each, the file and `docs:<path>#<section>` | `items type:"findings"`, then filter by `categoria` |

Docs to open, in order: `overview` → `book` (source of truth) → `runbook` (on-call) → `risks` / `architecture` / `operations`.

## Reference

- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-navigate/docs/model.md — the catalog model in 15 lines: components, facets, docs, edges, lore, provenance ladder, partitions, ids
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-navigate/docs/np-mcp.md — the nullplatform MCP's `np_kb_read` and `np_kb_propose`: every op with the params it needs, the ranges, what it returns, and the question → op matrix
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-navigate/docs/surfaces.md — the `np-catalog` MCP server (how to connect it, its read and write tools), the hosted `catalog-query` workflow, credentials
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-navigate/docs/external-sources.md — documentation pages as nodes, `doc-drift` findings, "if I touch this file which docs do I review", with real outputs
- @${CLAUDE_PLUGIN_ROOT}/skills/np-kb-navigate/docs/answering-rules.md — the nine rules the KB benchmark scores against (invention counts worse than absence)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `catalog_search` returns nothing | embeddings miss; absence is not proven | check with `get_facet` / `get_doc` on a component you know mentions it before concluding |
| `get_component` page is empty for a core/infra | knowledge lives in the consumers | `who_consumes` → read the consumers' facets |
| `get_component doc:<path>` shows `edges_in: []` | slug with `/` (mangled to `~`) | use `who_consumes {target: "doc:<path>"}` |
| Two sections of a book carry different dates | one came from a **focus** re-analysis (section patch); `recent-changes` records it | expected; the rest of the book was untouched by that run |
| A count in prose disagrees with the edges | written at different times (`IA:deep` doc vs `joined` edges) | report both with source and provenance; `joined` / `observed` edges are the live data |
| `np_kb_read` answers `"<op> needs <param>"` or lists `ignored` params | the op's params differ from what was sent | read the op's row in `docs/np-mcp.md`; the error names the missing param |
| No `np_kb_read` in the nullplatform MCP | the toolset is off for this organization, or the session has no organization | use the `np-catalog` server, or ask the admin to enable it |
| 401 on every read with `NP_TOKEN` | personal token expired (1 h) | `unset NP_TOKEN`; `NP_API_KEY` covers every read and never expires |
| The same name is a channel, a vendor and a database | homonyms | confirm `kind` and context before asserting identity |
