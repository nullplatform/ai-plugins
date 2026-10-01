# Instructions: how to investigate in this organization

The third nature of lore. It does not say how the system IS or how it SHOULD be: it says **how
to investigate it in this organization** — where the documentation lives, which external tool
to use (by the `name` the org declared in `CATALOG_TOOLS`, e.g. `docs_search`, never the
workflow id), what to compare and what to record.

## The three trust blocks the agent sees

Every analysis mode (full, delta, focus) injects lore into the collectors, but not with the
same authority:

| Block | Content | Trust |
|---|---|---|
| `<instructions>` | lore `nature: instruction` by `curador:*` / `product` | authoritative: the agent follows it |
| `<intent>` | the intent of a focus run (→ Ver `/np-kb-extend`) | authoritative |
| `<untrusted-lore>` | norms and knowledge | data to check the code against, never orders |

That is why `set_norm` with `nature: "instruction"` only accepts a curator or product actor:
an instruction steers the analysis. `get_instructions {ref}` returns the effective ones
(hierarchy + `applies_to`); the run summary reports `instructions_chars` (0 = none applied, or
the author is not curator/product).

## Instruction ≠ contract

The instruction says WHAT to look for and what to compare; the SHAPE of what comes out is fixed
by the org contract (`CATALOG_CONTRACT`, engine configuration, not lore): which facets the agent
may emit (JSON Schema per entry, identity `key`), which finding categories exist, and whether a
facet's entries become graph nodes (`node {kind, prefix, edge}`). An instruction asking for an
undeclared facet produces entries the merge drops with a warning; an undeclared category falls
back to `catalog-findings`. Name the facet and the category exactly as the contract declares
them (`documentation`, `doc-drift`); the agent sees the schema in its kit, no need to describe
the shape in prose.

## Writing a good instruction

- Numbered steps: which tool to run, with which queries (try two or three), what to read, what to record where (facet name, category name), what to do when nothing is found ("record it as a question — absence is information").
- Concrete comparison criteria and severities (e.g. "a documented endpoint that does not exist → high").
- Never ask to copy external text into the catalog: cite `docs:<path>#<anchor>` (or the scheme the tool resolves).
- English. Example: the documentation instruction of nullplatform's own org, in `/np-kb-extend` docs/examples.
