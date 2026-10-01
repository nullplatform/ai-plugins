# Curation runbooks

## Merging duplicate nodes (e.g. `core:az7` vs `core:autoriza7`)

1. Pick the canonical one by evidence: more inbound edges AND more textual mentions in third-party docs/facets (minimizes repointing and keeps prose current).
2. `repoint_edge` every edge of the duplicate towards the canonical node (keeps from and type).
3. Mark the duplicate as a dead alias: a facet `status` with "DUPLICATE of <canonical> — do not hang edges here" plus the identity evidence.
4. `create_suggestion` for the final removal (there is no node-delete tool, on purpose) and for updating textual mentions of the old slug in later passes.

## Enriching a bare node (referenced core/infra)

A core's knowledge lives in its consumers' facets; whoever lands on the node sees nothing.

1. `who_consumes {target}` → read the consumers' facets and docs.
2. `create_node` (upsert by slug) with a substantive `description`.
3. A summary facet on the node citing the consumers' anchors + **what is NOT in the catalog** (absence is information). Honest provenance: derived from someone else's analysis = `IA`; verified by you against the sources = `IA:verified`.

## Focus patches on curated books

A **focus** re-analysis (→ Ver `/np-kb-extend`) patches the book **by section**: a heading equal
to an existing one replaces that section, any other heading is appended. When the book is
`human:curated` the sink does not touch it: it files a suggestion (`patch: true`) carrying the
sections. The facets, edges and findings of that run were written regardless.

- Review: `list_suggestions` → the suggestion carries the sections and the intent of the run.
- Accept: apply the sections yourself as curator with `upsert_doc {component, doc: "book", content}` (merge them into the current book), or let the `on-suggestion-approved` workflow do it with the right provenance.
- Reject: close the suggestion with the reason; nothing else changes.

## Suggestions (human-in-the-loop cycle)

`create_suggestion {target_ref, body}` opens one; the cycle is open → analyzing → incorporated |
rejected | partial. `list_suggestions` shows the open ones. The proposer never applies their own
suggestion on curated ground: the `on-suggestion-approved` workflow applies what was accepted
with the right provenance.
