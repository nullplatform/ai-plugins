# Plugging an external source into the knowledge base

Four pieces, all org configuration; no code in the pipeline changes.

## 1. The tool: a read-only engine workflow

Any engine workflow with top-level `inputs:` / `outputs:` (→ Ver `/np-workflow`): the agent
calls it by `name` and the bridge executes it as a child execution. Rules: `read_only: true`
is mandatory; secrets live in the tool YAML as `${{ secrets.X }}` set with `/np-workflow config set
<NAME> --path=/catalog --secret`; a tool that reads pages of a source declares `resolves:
{scheme, ref_input}` so the verifier can re-read the anchors the agent cites (`docs:<path>#<anchor>`,
`wiki:<page>`, `cmdb:<id>`).

Publish and test it alone first: `/np-workflow publish <tool>.yaml` then
`/np-workflow run <wf_id> --input query="…"`.

## 2. The declaration: `vars.CATALOG_TOOLS`

A JSON array at the `/catalog` folder (`/np-workflow config set CATALOG_TOOLS --path=/catalog`,
value on stdin), one object per tool:

```json
{ "name": "docs_search", "workflowId": "wf_…", "alias": "latest", "read_only": true,
  "timeoutMs": 120000, "description": "what it does, inputs, what it returns; used by the agent" }
```

`resolves: {"scheme": "docs", "ref_input": "path"}` on the tool that reads one item by reference.
`fixed_inputs` may carry scope (a space, a tenant), never credentials (a key that looks like a
secret rejects the whole declaration).

## 3. The contract: `vars.CATALOG_CONTRACT`

```json
{ "facets": [{ "name": "documentation", "title": "…", "key": "path", "producers": ["agent"],
               "entry_schema": { "type": "object", "required": ["path", "url", "describes"], "properties": { … } },
               "node": { "kind": "document", "prefix": "doc:", "edge": "documented-by",
                         "title_field": "title", "url_field": "url", "via_field": "sections" } }],
  "finding_categories": ["doc-drift"] }
```

- `entry_schema` (JSON Schema) validates every entry the agent emits; `key` is the identity used to merge entries across runs.
- `node` makes every entry a graph node (`<prefix><key>`, kind) with an edge `<app> <edge> <node>`; `via_field` fills the edge's `via`. That is how documentation pages become `doc:<path>` nodes answerable with `who_consumes`.
- `finding_categories` closes the categories; an undeclared one falls back to `catalog-findings` with a warning.

## 4. The instruction: lore `nature: instruction`

Written as a curator (→ Ver `/np-kb-lore`): numbered steps naming the tool by its declared
`name`, the facet and the category exactly as the contract declares them, the comparison
criteria and what to do when nothing is found. Verify with `get_instructions {ref: "<app>"}`.

## 5. Run

- Existing books: a **focus** with `kind: tool` (→ `docs/focus.md`), five times cheaper than a deep-dive; over the org with `catalog-refocus`.
- Apps without a book: `catalog-ia-codex` (`wf_BzjGzVJxM6RS`) with `write=true`.
- Cheapest end-to-end test: `catalog-ia-delta` with `write=false` and `deep_dive_ratio=0.9` — uses the tools and the contract, writes a report, touches nothing.

## 6. Check the catalog

`get_facet {component, facet}`, `who_consumes {target: "<prefix><key>"}`, `list_findings
{component}` filtered by `categoria`, `list_questions {component}`.
