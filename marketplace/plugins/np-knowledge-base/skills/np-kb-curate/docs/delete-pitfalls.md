# Delete and write pitfalls (learned the hard way)

- **Two id conventions coexist**: `<slug>~<name>` and `<slug>~<name>~p0` (partitioned content). A DELETE against the wrong form returns **a 404 that looks like success**. GET both forms before; GET afterwards to confirm it is gone.
- **The API key has no delete grant** and no spec access: cleanups need a personal `NP_TOKEN` (1 h).
- **Deleting a component does not cascade**: child docs and facets survive with a null FK, recoverable but invisible. List what hangs from it BEFORE deleting.
- **Re-add after retract**: the edge only revives with an explicit `config_status` on the re-add; without it the tombstone wins.
- **Fields not declared in the spec are dropped SILENTLY** (200 without saving). After the first write of a new field, check with GET. Spec changes are → Ver `/np-catalog`.
- **Long content is partitioned** into `~pN` instances (32k chars per semantic field). Deleting one partition leaves a truncated document; the read tools reassemble whatever exists.
- **Pagination is unstable under concurrent writes**: an integrity sweep while the pipeline writes yields false missing items. Confirm every suspect with a direct GET.
- **Ids with `/` are mangled to `~`** in storage; a URL with `%2F` 404s. The MCP tools accept the readable form and mangle for you.
