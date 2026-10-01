# Real example: nullplatform's own organization and its public documentation

The org plugged its documentation site (docs.nullplatform.com) into the knowledge base:

- `catalog-tools.json` — the `vars.CATALOG_TOOLS` declaration: `docs_search` (free-text search over the docsite, returns pages with repo path, URL, title, excerpt) and `docs_page` (reads one page by repo path, split into sections with anchors; `resolves: {scheme: docs, ref_input: path}` so the verifier re-reads `docs:<path>#<anchor>` anchors).
- `catalog-contract.json` — the `vars.CATALOG_CONTRACT`: one facet `documentation` (key `path`, entry schema with `path`, `url`, `title`, `describes` = code anchors, `sections`), whose entries become `doc:<path>` nodes with a `documented-by` edge and the sections in `via`; one finding category `doc-drift`.
- `instruction-docs-in-docsite.md` — the instruction (lore `nature: instruction`, curator) telling the agent to find the pages with two or three queries, record the mapping as the `documentation` facet, compare each page with the code and file every difference as `doc-drift` with two anchors, and ask a question when no page exists.

Outcome on one application with a focus of kind `tool` (≈ 3 min): 9 pages mapped, 5 `doc-drift`
findings, the "Related documentation" section of the book replaced; `who_consumes {target:
"doc:docs/notifications/channels.md"}` now answers which apps a page affects.
