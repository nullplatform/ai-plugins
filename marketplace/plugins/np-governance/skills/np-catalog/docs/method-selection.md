# Read-method costs and diagnostics

**The method matrix, the `rank → confirm → hydrate` join, and negation blindness live
inline in SKILL.md** — choosing wrong there produces no error, so that guidance cannot
sit behind a file you might not open. This file carries only what a routine query does
not need: what each instrument *costs*, and the diagnostic reads for when a number looks
wrong.

## The five instruments, and what each one costs

| Instrument | Answers | Call | Cost of one call |
|---|---|---|---|
| **Facets** | *how many, in what proportion* | `?facets=field1,field2&limit=1` | One request, no rows transferred |
| **Filter + page** | *give me the exact field values* | `?risk=high&sort=…&limit=100&offset=…` | One request per 100 records; `include=` avoids pulling full documents |
| **Semantic** | *what happened, what does this say* | `POST /search` + `sort:"relevance"`, `query` = the full information need | One request, ranked candidates + passages |
| **Fulltext** | *which records mention this term* | `?query=term` on a `fulltext` field | One request, substring/attribute match |
| **Traverse** | *what is connected to this* | `POST /traverse` | One request, topology only (no data) |

Facets and filters read **declared scalars**. Semantic and fulltext read **prose**.
Traverse reads **edges**. A question spanning prose and scalars spans methods.

The asymmetry worth internalising: an aggregation transfers no rows, so it stays nearly
free, while paging transfers the population. Where both could answer a question, the
aggregation is not merely cheaper — it is the one that stays cheap as the tenant grows.

The cost column is per **call**, not a budget: every instrument except paging is cheap
enough to call repeatedly, and semantic ranking in particular is *meant* to be iterated —
reformulate the query and re-ask when the first ranking looks off.

## Diagnostics — for when a number looks wrong

These are not steps in a normal query. Reach for them when a count contradicts something
you already know, or when you are about to act on the number.

### Verifying a grouping key

When a spec carries **both** a relation and a denormalized label for the same thing (a
foreign key plus a human-readable name for the same target), they can disagree, and
neither is automatically the better key:

- `traverse` follows real edges — it misses records whose foreign key is **null**.
- the denormalized label survives a failed resolution — but it silently merges two
  entities that share a name.

Traverse one anchor and compare the node count against a filter on the label. Agreement
is cheap reassurance; disagreement localises an ingest bug — a **storage** defect
surfaced by a **retrieval** check. Keep it bounded: a sparse `include=` read of just the
two keys answers this without pulling documents.

### Checking whether a derived field is populated

A field written only when true is indistinguishable from one never evaluated:
`?flag=false` and `?flag:is_null=true` return the same set. Probe with
`?flag=false&flag:is_null=false` — if that returns zero, the negative case was never
written, and no filter on that field means what it appears to mean.

### Reading a capped answer

Large filtered sets fall back to a global pass and set `truncated: true`. A count taken
from such a response is a floor, not a total — narrow the filter or page, and say which
you did.
