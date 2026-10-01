# Rules when answering (what the KB benchmark scores)

1. **Every statement with its source**: the `file:line` anchor the catalog cites, or the ref (`<component>~<facet>` / `~<doc>`) it came from.
2. **"It is not in the catalog" is a valid and valuable answer** — say it explicitly, do not pad. Literal code (the full table, the constants) is absent by design: deliver the cataloged summary + the repo anchor.
3. **Empty `catalog_search` ≠ absent data** (embeddings): before concluding absence, check with `get_facet` / `get_doc` on a component you know mentions it.
4. **After writing, read by deterministic id** (`get_*`), never through search or listings: the read index lags.
5. **Homonyms**: the same name can be a routing channel, a vendor and a database. Confirm `kind` and context before asserting identity.
6. **Every impact with its edge**: name the edge that proves it (from, `edge_type`, to, `via`). Without an edge there is no impact, there is a hypothesis, and you say so.
7. **Graph beats lore when they clash**: lore says how something SHOULD be named (`idp:cognito`); edges say what exists. Report what exists and flag the difference as a contradiction; picking the lore silently counted as invention in the benchmark.
8. **Do not fill in what the catalog leaves open**: routes, payloads and mechanisms the tool did not return do not exist for the answer. A precise "not there" beats a plausible guess (invention scores worse than absence).
9. **Prose and edges can diverge** (an `IA:deep` doc says "18 consumers", the `joined` edges show ~89: written at different times). On a count conflict, report both with source and provenance; `joined` / `observed` edges are the live data.
