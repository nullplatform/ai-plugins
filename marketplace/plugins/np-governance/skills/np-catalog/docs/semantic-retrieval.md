# Semantic retrieval & traversal

Ask questions in natural language over prose you store on instances, and walk relations
to bound the answer.

Two capabilities, used together:

- **`index: ["semantic"]`** on a string field makes its prose retrievable by meaning
- **`sort=relevance`** on `/search` ranks instances by that prose and returns the
  matching passages
- **`POST /traverse`** walks relations to produce the neighborhood a ranking can be
  scoped to

Everything here is the request/response contract — what you send, what comes back, and
what to do when it misbehaves.

## Declaring a semantic field

```jsonc
{
  "properties": {
    "id":    { "type": "string", "primaryKey": true, "autoGenerate": false, "alias": "doc_key" },
    "title": { "type": "string", "index": ["fulltext", "filter"], "maxLength": 200 },
    "body":  { "type": "string",
               "index": ["semantic"],
               "contentMediaType": "text/markdown",
               "maxLength": 32768 }
  }
}
```

| Rule | Detail |
|------|--------|
| Type | valid **only** on `type: "string"` |
| `maxLength` | must be **≤ 32768**, or the spec is rejected: `semantic field '/body' declares maxLength N, above the per-field cap of 32768 characters` |
| Combining flags | `semantic` + `filter`/`sort`/`facet` on one field requires `maxLength` ≤ 4096. Keep long prose semantic-only |
| Fields per spec | 16 max |
| `contentMediaType` | picks the split strategy: `text/markdown` splits on headings and prefixes each passage with its heading trail, `text/plain` on paragraphs, `text/html` strips tags. Unknown values are accepted and ignored. It describes content — it does **not** enable retrieval; `index: ["semantic"]` alone does that |
| Clearing | `null`/`""` stores an empty document, not a deletion; it reads back as `''`. Forbid with `minLength: 1` |

> **`semantic` is not `fulltext`.** `fulltext` feeds the `query` filter over attributes.
> `semantic` is what `sort=relevance` ranks over. A prose field marked only `fulltext`
> is invisible to `sort=relevance` — **zero results, no error**. This is the single
> most common way to waste an afternoon here.

## Prose is indexed asynchronously

A write returns as soon as the instance is stored; the prose becomes searchable a few
seconds later. `GET` by id is immediately consistent — only relevance ranking lags.
Same contract as facets. If you write and immediately query, expect a miss; retry.

## Asking a question — `sort=relevance`

```bash
catalog-api.sh GET '/search?query=are+records+really+deleted&sort=relevance&limit=30'
```

(`query` and `q` are aliases; prefer the explicit `query`.)

`query` switches from a substring filter into a ranking query — and that changes how
you write it. **State the full information need: a natural-language question, or an
equally content-rich descriptive phrase.** The whole phrase is embedded, so it is the
content words that carry intent — "how does retry backoff work on failed deployments?"
and "retry backoff behavior for failed deployments" rank about equally well; politeness
filler adds nothing. What never works is a single word (`query=retry`): it throws the
semantic signal away and degrades toward keyword matching over chunks —
plausible-looking results, none of the ranking you came for. The search is **hybrid**
(a lexical branch runs beside the embedding), so using the domain's own terms in the
phrase helps rather than hurts. If a bare keyword is genuinely all you have, you wanted
the substring mode (drop `sort=relevance`) or a `fulltext` filter instead.

**Iterate.** One ranking call is cheap, and phrasing steers it — when the results look
off, re-ask the same need worded differently (or from the answer's perspective:
documents phrase things as statements) and judge the union. Two or three reformulations
are a normal retrieval pattern, not a workaround. Results are **instances**,
with the passages that matched attached:

```jsonc
{ "entity": "artifact",
  "score": 0.0328,
  "data": { "title": "…", "kind": "database" },
  "matches": [
    { "field": "/body",                              // alias pointer to the field
      "breadcrumb": "artifact/body > DATABASE.md > Pagination",
      "text": "Records are never physically removed. A DELETE sets deleted_at…",
      "kind": "reference",
      "score": 0.0328 }
  ] }
```

Read the answer straight off `matches[]` — no second fetch. Notes that affect how you
consume it:

- an instance ranks by its **best** passage, never the sum, so a long document does not
  outrank a short exact answer
- at most **3** passages come back per instance
- default `limit` is 30 and the contract is **recall-oriented** — a candidate set for a
  reader to judge, not a precision-tuned top-5
- filters and authorization apply **before** ranking, so facets stay correct and
  `?type=`/field filters compose normally with `sort=relevance`
- very large filtered sets fall back to a global pass and set **`truncated: true`** —
  treat that as "this answer may be incomplete", not a failure
- deep paging is refused past an offset the retrieval depth cannot fill

**`POST /search`** takes the identical query object as a JSON body and returns the
identical response. Use it when the query is too big for a URL — chiefly when scoping
to many ids.

```bash
catalog-api.sh POST /search '{"query":"how does soft delete work","sort":"relevance","limit":30}'
```

## Walking relations — `POST /traverse`

The request speaks the **external vocabulary** end to end: relations by their public
alias, specifications by slug or id, the anchor by its external instance id.

```bash
catalog-api.sh POST /traverse '{
  "from":  { "id": "billing-api", "specification_slug": "application" },
  "steps": [ { "relations": [ { "relation": "artifacts", "direction": "out" } ],
               "hops": { "min": 1, "max": 2 } } ],
  "limit": 200 }'
```

| Field | Meaning |
|-------|---------|
| `from.id` | external instance id — **required** |
| `from.specification_slug` \| `from.specification_id` | **exactly one** — external ids are only unique per specification |
| `steps[]` | 1–5 steps, processed in order; each expands the previous step's discoveries |
| `steps[].relations[]` | 1–16 atoms, an **alternation** — any matching atom counts at that hop. `relation` is the public alias (the declaration key also resolves), `direction` is `out`/`in`/`both` (default both), and `specification_slug`/`specification_id` filters which neighbour type the edge may reach |
| `steps[].hops` | `{min, max}`, default `{1,1}`. `min: 0` also passes the incoming frontier through unexpanded. **Σ of `max` across all steps ≤ 5** |
| `limit` | 1–500 global node budget |

Two cross-field rules JSON Schema cannot express are enforced by the service with
explicit 400s: exactly one `from` qualifier, and the depth budget Σ `hops.max` ≤ 5.

The response returns nodes and topology — **no instance data**:

```jsonc
{ "nodes": [ { "id": "billing-api::README.md",      // EXTERNAL id
               "specification_id": "…", "specification_slug": "artifact" } ],
  "edges": [ { "source": "billing-api", "relation": "artifacts",
               "target": "billing-api::README.md", "direction": "out" } ],
  "truncated": false }
```

`nodes[].id` is the **external** id (an internal uuid appears only when the external
identity is unrecoverable), so it feeds straight into `/search`'s `id` filter for
hydration. `edges[].relation` is the source specification's declared alias.

Nodes you cannot read are invisible — not returned, none of their edges, never
expanded through. Any budget hit reports `truncated: true`; a capped neighborhood
never masquerades as a complete one.

## Scoping a question to a neighborhood

The pattern the two endpoints exist for — "how does X work **in this app**":

1. find the entry instance (`GET /search?query=<name>&limit=1`, or read it by id)
2. `POST /traverse` from it to get the neighborhood
3. re-ask the question restricted to that neighborhood

Scoped ranking is also the fast path — it searches one neighborhood instead of the
whole tenant. Unscoped ranking is the discovery mode ("which service does X?").

```bash
# 1. the entry instance — a NAME lookup, so substring mode, not sort=relevance
#    (ranking a bare name semantically is the single-keyword mistake above)
catalog-api.sh GET '/search?query=billing-api&limit=1'

# 2. its neighborhood
catalog-api.sh POST /traverse '{
  "from":  { "id": "billing-api", "specification_slug": "application" },
  "steps": [ { "relations": [ { "relation": "artifacts" } ], "hops": { "min": 1, "max": 2 } } ],
  "limit": 500 }'

# 3. the question, restricted to it — nodes[].id are external ids, which is
#    exactly what the `id` filter takes
catalog-api.sh POST /search '{"query":"how does retry work here?","sort":"relevance",
                              "limit":30,"id":["<nodes[].id from step 2>"]}'
```

**Filters on `/search` are spec-slug-prefixed** (`service.status=active`), because it searches across types and a
bare field name would be ambiguous between specifications:

```bash
catalog-api.sh POST /search '{"query":"how does soft delete work","sort":"relevance",
                              "limit":30,"artifact.repo_slug":"billing-api"}'
```

## Common mistakes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `sort=relevance` returns nothing for text you know exists | the field is `fulltext`, not `semantic` | declare `index: ["semantic"]` and re-write the instance |
| Spec create 400 `above the per-field cap of 32768 characters` | `maxLength` too large on a semantic field | lower it, or split long prose across child instances |
| Spec create 400 about attribute flags | `semantic` combined with `filter`/`sort`/`facet` on a long field | keep prose semantic-only, or bound it at ≤ 4096 |
| A just-written document is not retrievable | indexing is asynchronous | wait a few seconds; `GET` by id is unaffected |
| `Field 'x' requires instance prefix for multi-instance search` | `/search` is cross-type, so filters name the specification that declares the field | use `specSlug.field` |
| `POST method is only allowed for endpoints matching…` | installed `np-api` predates these paths | update/reinstall `np-api` alongside `np-catalog` |
| Traverse 400 on `from` | `from` needs BOTH `slug` and `id` | `{"from":{"slug":"…","id":"…"}}` |
| Results look keyword-matched, ranking adds nothing | `query` is a single word — the embedded phrase carried no intent | state the full need (a question or a content-rich phrase), keep entity names in filters or `id` scopes, not in `query` |
| Paraphrases and other languages miss, exact words still hit | the deployment is answering **lexically** — its embedding provider is not configured, which degrades relevance instead of failing it | not fixable from the client; ask whoever operates the deployment to check its embedding configuration |
| Top hits **deny** the property you asked for | **negation blindness** — ranking registers topic, not polarity, so *"**No** auth, schema or infra changes"* ranks high for *"auth change"*. No error, no score penalty | rank to build the candidate set, then decide from an indexed scalar (`?<flag>=true`) or a rationale field read per record — never let rank answer a yes/no |
| Rank looks right, so the result set is reported as the answer | ranking is **recall-oriented** by contract — a candidate set for a reader to judge, not a filtered result | confirm each hit from `matches[].text` before counting it; see the `rank → confirm → hydrate` join in `method-selection.md` |

## Splitting long documents

Prose past 32768 characters does not fit one field, and one huge blob ranks worse than
its parts: retrieval returns the best passage per instance, so a single instance holding a
whole manual competes for one slot. Split at logical boundaries into child instances —
a `has_many` from the parent — and each section competes on its own merits and cites
its own heading trail. This is a modeling choice you make, not something the API does
for you.
