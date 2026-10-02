# The knowledge base in the nullplatform MCP: `np_kb_read` and `np_kb_propose`

The hosted nullplatform MCP can serve the knowledge base as two tools. They are there
only when the deployment turned the toolset on for your organization. Both run with **your
session**: they read what your token can read, and `np_kb_propose` files under your identity.
Neither can change a fact in the catalog.

## Connecting

The hosted server is `https://mcp.nullplatform.com/mcp`. **An API key goes in the
`X-API-Key` header**; `Authorization: Bearer` is only for a nullplatform token (a JWT). The
gateway in front of the hosted server rejects an API key sent as a Bearer token with
`401 Invalid token` before it reaches the server.

```bash
claude mcp add --transport http nullplatform https://mcp.nullplatform.com/mcp \
  --header "X-API-Key: <your nullplatform API key>"
```

The organization comes from the credential. If a tool reports an authentication problem,
call `np_auth_status`: it says which session the server holds and how to present one.

## Ops

The schemas are kept short on purpose, so this page holds the details: which params each
op needs and what it returns. If a call misses a param, the tool says which one
(`"graph needs ref"`). Params the op does not read come back under `ignored`, and the call
still runs.

## `np_kb_read` ops

| `op` | Needs | Optional | Returns |
|---|---|---|---|
| `search` | `query` | `limit` 1–30 (default 10), `offset` | hits with `owner`, `kind` (component/facet/doc/edge), `ref`, `score`, snippets. Read a hit with `get` |
| `list` | — | `view`: `components` (default), `hierarchy`, `lore`, `apis`, `libs`, `facet` (with `facet`, `where`, optional `fields`; see below); `kind`; `namespace` (a namespace or account name); `application_id`; `query`; `limit` 1–500 (default 50), `offset` | `components`: slug, name, kind, namespace, account, nrn. `hierarchy`: account → namespace → apps, the kind counts, the lore titles. `lore`: norms/knowledge/instructions (`kind` = `norm`/`knowledge`/`instruction`). `apis`/`libs`: each API or library with its consumers |
| `get` | `ref`: a slug, a name, an NRN, `application:<id>` or `lore:<key>` | `include`: `facet:<name>` (up to 5), `doc:<name>` (up to 3), `norms`, `deploy_checklist`, `retired`, `lore`; `limit` (edges per page, default 50, max 500), `offset` | `component`: identity, NRN, platform app, facets and docs index, **live** `edges_out` / `edges_in` with evidence, `via` and provenance, `edges_retired_omitted` (how many retired edges were left out; `edges_retired` with `include: ["retired"]`), applicable knowledge and instructions as `{key, title, summary, page}` (full bodies with `include: ["lore"]`, or one at a time with `get {ref: "lore:<key>"}`). Then `facets.<name>`, `docs.<name>`, `norms` and `deploy_checklist` for whatever you included. Every answer carries `state` (see below); when there is no node, `found: false` |
| `graph` | `ref`: a node, e.g. a slug, `queue:<name>`, `lib:<name>` or `doc:<path>` | `direction`: `consumers` (default) or `dependencies`; `depth` 1–4 (default 1); `through_intermediaries` (default false); `include: ["retired"]`; `limit`, `offset` | **live edges only**. Depth 1 consumers: `consumers`. Deeper, or dependencies: `affected` (the node list) and `detail`. Both carry `intermediaries`, always `[{node, depth, behind, behind_truncated}]`. Every row, in both directions and at every depth, is `{depth, from, to, edge, via, evidence, provenance}`: `from` calls or depends on `to`. A consumer that is a gateway, proxy or bus carries `intermediary: true`. `retired_omitted` counts the retired edges left out |
| `items` | `type`: `findings`, `questions` or `suggestions` | `ref` (one component), `status`, `limit` (default 50), `offset` | `findings`: governance items with `category`, `severity`, `evidence` (anchors), `kind`, and `complete` (every application NRN read to its total). `questions`: open questions with options, evidence and priority. `suggestions`: filed proposals |

### Reading a response

`np_kb_read` answers `{op, coverage?, truncated?, ignored?, result}`, with the metadata **before** the result.
A long answer can be cut by the client, and what is partial must still show. On a paged op,
`truncated` is always there: `{}` means every list is complete.

### Retired edges: never mixed with live ones

An edge is live when it has a type and its `config_status` is not `refuted`. That is the
pipeline's own definition. Retraction, curator refutation and tombstones all set `refuted`
and append the reason to the evidence, as `RETRACTED (<code>): <why>` or `REFUTED: <why>`.
- `graph` and `get` return live edges only and count the rest (`retired_omitted`,
  `edges_retired_omitted`).
- The count is **per call**, over the edges that call read: `get` counts retired edges in
  and out of the node; depth-1 `graph` counts the retired edges into it; a deeper `graph`
  sums the retired edges met at every hop, so it grows with `depth` and can exceed the
  node's own. Never compare counts across calls, and never read one as "how many edges
  this node lost".
- Pass `include: ["retired"]` to see the retired ones, in their own list, each with
  `status`, `reason` and the original `evidence`. Use it for "was X ever a dependency" or
  "why is this edge gone", never to answer "who depends on X".

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
  `intermediaries: [{node, depth, behind, behind_truncated}]`, where `behind` is how many
  live callers (or routes) sit behind it. The shape is the same at every depth.
- Calls through a gateway that the pipeline resolved by path are already direct edges to
  the backend, so they are in the result.
- Pass `through_intermediaries: true` only when the question really is "everything behind
  that gateway", and say the result is then over-inclusive.

### Filtering by a facet field: `list` with `view: "facet"`

To find the nodes, or the entries inside a facet, whose facet field has a value, do not `get`
node after node: one call reads every instance of that facet and matches for you.
- `{op: "list", view: "facet", facet: "<name>", where: [{path, op, value}], fields?, kind?, namespace?, query?}`.
  Example: `{op: "list", view: "facet", facet: "inventory", where: [{path: "items[].state", op: "eq", value: "open"}], fields: ["name", "owner"]}`.
- `path` is dotted keys. `key[]` steps into an array: the elements of the array at the first `[]`
  are what is matched and returned, as `{node, at: "items[3]", element}`. Every clause must start
  at the same array, and clauses are ANDed on the same element. A path with no `[]` matches the
  facet as a whole and returns `values`.
- `op`: `eq`, `ne` (no value equals it), `exists`, `gt`, `gte`, `lt`, `lte` (numbers with numbers,
  strings with strings), `contains` (substring or array member). Every op except `exists` needs a `value`.
- `fields` returns only those paths of each match instead of the whole element.
- `kind`, `namespace` or `query` narrow the nodes first. They pay off on large facets; on a
  facet with few instances the unscoped call is cheaper.
- Read `result.scanned` before answering. It has `facet_rows` against `facet_rows_indexed` and
  `complete`. If `complete` is false, say the answer may be partial and quote the `note`.
  `parse_failures` names the nodes whose facet is not JSON, which were not matched. The read
  comes from the catalog index, so facets written moments ago may be missing.
- `limit` and `offset` page the matches, never the scan, so a page is never a partial truth.
- To see the field names and the shape of a facet before filtering on it, `get` one node with
  `include: ["facet:<name>"]`.

### `state` on `get`: absent is not the same as never analysed

Every `get` answer carries `state`:
- `analysed`: a node with facets or docs.
- `bare`: a node with no facets or docs, only named by edges.
- `not_analysed`: the platform has this application in the organization, but the catalog has
  no node, or only a bare one. `platform` carries its id, name, slug and status. Say "exists,
  not analysed yet", never "does not exist".
- `not_in_platform`: no node, and the platform has no application with that id in this organization.
- `not_in_catalog`: no node, and the platform was not asked. Either the ref was a name rather
  than an application id or NRN, or `platform_lookup: "unavailable"` says the platform could not
  answer. Ask with `application:<id>` to tell absent from not analysed.

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
