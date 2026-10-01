# The knowledge base in the nullplatform MCP: `np_kb_read` and `np_kb_propose`

The hosted nullplatform MCP can serve the knowledge base as two tools. They are there
only when the deployment turned the toolset on for your organization. Both run with **your
session**: they read what your token can read, and `np_kb_propose` files under your identity.
Neither can change a fact in the catalog.

The schemas are kept short on purpose, so this page holds the details: which params each
op needs and what it returns. If a call misses a param, the tool says which one
(`"graph needs ref"`). Params the op does not read come back under `ignored`, and the call
still runs.

## `np_kb_read` ops

| `op` | Needs | Optional | Returns |
|---|---|---|---|
| `search` | `query` | `limit` 1–30 (default 10), `offset` | hits with `owner`, `kind` (component/facet/doc/edge), `ref`, `score`, snippets. Read a hit with `get` |
| `list` | — | `view`: `components` (default), `hierarchy`, `lore`, `apis`, `libs`; `kind`; `namespace` (a namespace or account name); `application_id`; `query`; `limit` 1–500 (default 50), `offset` | `components`: slug, name, kind, namespace, account, nrn. `hierarchy`: account → namespace → apps, the kind counts, the lore titles. `lore`: norms/knowledge/instructions (`kind` = `norm`/`knowledge`/`instruction`). `apis`/`libs`: each API or library with its consumers |
| `get` | `ref`: a slug, a name, an NRN, `application:<id>` or `lore:<key>` | `include`: `facet:<name>` (up to 5), `doc:<name>` (up to 3), `norms`, `deploy_checklist`; `limit` (edges per page, default 50, max 500), `offset` | `component`: identity, NRN, platform app, facets and docs index, `edges_out` / `edges_in` with evidence, `via` and provenance, `edges_refuted`, applicable knowledge and instructions. Then `facets.<name>`, `docs.<name>`, `norms` and `deploy_checklist` for whatever you included. When nothing matches, `found: false` |
| `graph` | `ref`: a node, e.g. a slug, `queue:<name>`, `lib:<name>` or `doc:<path>` | `direction`: `consumers` (default) or `dependencies`; `depth` 1–4 (default 1); `through_intermediaries` (default false); `limit`, `offset` | depth 1 consumers: each edge with `edge_type`, `evidence`, `via`, `provenance`; a consumer that is a gateway, proxy or bus carries `intermediary: true`. Deeper, or dependencies: `affected` (the node list), `detail` hop by hop (each with `via` and `evidence`), and `intermediaries` |
| `items` | `type`: `findings`, `questions` or `suggestions` | `ref` (one component), `status`, `limit` (default 50), `offset` | `findings`: governance items with `category`, `severity`, `evidence` (anchors), `kind`, and `complete` (every application NRN read to its total). `questions`: open questions with options, evidence and priority. `suggestions`: filed proposals |

### Pages: never reason over a cut list

Every list in a result comes in pages: edges of `get`, consumers and hops of `graph`, the
`list` and `items` lists, and `search` hits. While more remain, the response carries
`truncated: {<list>: {shown, total, next: {offset}}}`.
- Call again with `offset: <next.offset>`, or raise `limit` (max 500), until `truncated` is
  gone, before you count or enumerate.
- For "which X does Y call" questions, say "N of TOTAL shown" if you stop early.

`result.listing_capped: true` is different: it means the catalog's own listing hit its page
cap, so even the full list is not the total. Say so.

### Intermediaries: why a radius stops at a gateway

A gateway, proxy or bus in front of backends is an **intermediary**. The catalog marks one
with outgoing `proxies-to` edges, or with an org rule. Its callers depend on it for
everything it fronts, not on the node you asked about.
- `graph` lists it in `affected` but does not walk past it. It reports it in
  `intermediaries: [{node, depth, behind}]`, where `behind` is how many callers (or routes)
  sit behind it.
- Calls through a gateway that the pipeline resolved by path are already direct edges to
  the backend, so they are in the result.
- Pass `through_intermediaries: true` only when the question really is "everything behind
  that gateway", and say the result is then over-inclusive.

### Coverage: say how partial the answer can be

`search`, `list` (components) and `graph` answers carry
`coverage: {analysed_applications, platform_applications, ratio, results_from}`. The catalog
only knows the applications it has analysed. A consumer that was never analysed is
absent, not "not a consumer". When `ratio` is below 1 and the question is
"who depends on X" or "what breaks", give the answer **with** that caveat. Example: "17
consumers among the 648 of 3,652 applications analysed". A null count is listed in
`unavailable`: say you could not tell.

## `np_kb_propose` ops (only when enabled)

| `op` | Needs | Optional | Effect |
|---|---|---|---|
| `suggest` | `target_kind` (`component`, `facet`, `doc`, `edge` or `org`), `target_ref`, `text` (the change and its evidence, up to 4000 chars, no source code) | `changeset` (up to 20 operations for the reviewer) | files an open suggestion; a reviewer or the next analysis accepts or rejects it |
| `answer` | `question_id` (from `items type:questions`), `answer_kind` (one of the question's `options[].kind`) | `answer_value`, `text`, `evidence` | records a proposed answer. The question stays open until a curator confirms it |

Confirm with the user before filing either one. Before suggesting, check with `items
type:suggestions ref:<component>` that nobody filed the same thing already.

## Question → op

| Question | Calls |
|---|---|
| What is X? | `get {ref: X}`. If the page is bare (core and infra pages often are), the knowledge lives in the consumers: `graph {ref: X}`, then `get` two or three of them with `include: ["doc:book"]` |
| Who uses X? What breaks if X goes down? | `graph {ref: X}` for the direct edges with evidence, then `graph {ref: X, depth: 2}` for the transitive ones. Copy the paths hop by hop, exactly as returned. Name the `intermediaries` met (with how many callers sit behind each), page until `truncated` is gone, and state the `coverage` |
| What does X depend on? | `graph {ref: X, direction: "dependencies", depth: 2}` |
| Where does it say…? (exploratory) | `search {query}`, then `get` the `ref` of the best hits |
| Which rules apply to X? Can it deploy? | `get {ref: X, include: ["norms", "deploy_checklist"]}` |
| How do I connect to X? | `get {ref: X, include: ["doc:book"]}`, section "How to connect to this app". Older books: `include: ["facet:endpoint-authz"]` |
| What is known to be wrong in X? | `items {type: "findings", ref: X, status: "open"}` |
| What is the organization being asked? | `items {type: "questions"}` (sorted by priority) |
| Which docs describe X? Which apps does a doc page affect? | `get {ref: X, include: ["facet:documentation"]}`; for a page, `graph {ref: "doc:<path>"}` |
| Where am I? What exists? | `list {view: "hierarchy"}`, then `list {namespace: <name>, kind: "app"}` |
| Which app is platform application 123? | `list {application_id: "123"}` or `get {ref: "application:123"}` |
| Who consumes each API or library in the org? | `list {view: "apis"}` / `list {view: "libs"}` |
