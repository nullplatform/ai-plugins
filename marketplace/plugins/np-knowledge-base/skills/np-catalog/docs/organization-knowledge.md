# Modeling an organization's data for retrieval

How to shape a catalog so people can ask questions of it — "what does this service do",
"where do I start to change X", "what breaks if I remove Y".

The catalog gives you three different instruments. Most bad knowledge bases come from
using one where another belongs:

| Instrument | Answers | Declared as |
|-----------|---------|-------------|
| **Relations** | *what is connected to what* — bound a question to a neighborhood, trace blast radius | `belongs_to` / `has_one` / `has_many` / `many_to_many` |
| **Semantic fields** | *what does this mean* — rank prose against a question | `index: ["semantic"]` — see `semantic-retrieval.md` |
| **Indexed scalars** | *which subset* — exact, cheap, countable | `index: ["filter","facet","sort","fulltext"]` |

Design every field into exactly one of those jobs. A field doing two jobs does both
badly.

## 1. Model the real things, with the ids they already have

One instance per thing that exists in the source system, keyed by **that system's id**:

```jsonc
"id": { "type": "string", "primaryKey": true, "autoGenerate": false, "alias": "application_id" }
```

External identity makes re-ingest an idempotent upsert — run the connector twice and
you update rows instead of duplicating them, because the id is derived from the source,
not from insertion order.

Two rules that are easy to break and expensive to unpick:

- **Never invent an instance for something that does not exist upstream.** If a repository
  has no registered application, it is a repository — not an application with blank
  fields. Placeholder rows (`""` ids, `"unassigned"` parents) poison every filter, facet
  and count built on them afterwards.
- **One thing, one node.** If two sources describe the same service, they must resolve to
  the same id, or the graph forks and traversal returns half the neighborhood.

## 2. Shape the graph so a question can be bounded

The hierarchy you already have is what lets a question be scoped: `account → namespace
→ application` means "how does auth work **in this app**" can be answered without
ranking the whole organization.

- **Put the FK on the many side.** `application belongs_to repository`, because one
  repository can back several applications — a monorepo. Getting this backwards forces
  `many_to_many` and loses the cheap inline filter.
- **Declare both directions when both must be walked.** A `belongs_to` on the child does
  not give the parent a `has_many`; traversal is per-declaration.
- **Let cardinality carry the rule.** `has_one` is a singleton slot (an application has
  one README); `has_many` is parts (a document has many sections). The shape documents
  the constraint so you do not have to.
- **Cross-cutting things get their own instance and a `many_to_many`.** A concept like
  "soft delete" is referenced from many documents across many repositories. Give it a
  top-level instance and link it with `many_to_many`, so the question reaches every
  implementation instead of whichever document happened to define it first. Anchoring
  such a node under one parent with `belongs_to` is the mistake — it traps a shared
  idea inside one repository's neighborhood.

Aim for a graph where two hops from any entry point reach everything needed to answer a
question about it — its docs, its dependencies, its owner. Deeper than that and
traversal budgets start truncating; shallower and scoped questions miss context.

## 3. Put prose in semantic fields, facts in indexed ones

Semantic fields are for **prose a human would read to answer a question**. Names, ids,
statuses, dates, versions and enums are facts: index them `filter`/`facet` so they
narrow the candidate set exactly and cheaply, and let ranking work on the prose.

**One instance = one answerable unit.** Retrieval returns each instance's *best* passage, so
a single instance holding an entire manual competes for exactly one slot against a short
precise answer — and anything past the 32768-character field cap is not stored at all.
Split long documents at heading boundaries into child instances:

```
document (title, kind, url)
  └── has_many section (heading_path, ordinal, body ← semantic)
```

Each section then competes on its own merits and cites its own heading trail.

**Write chunk-friendly prose.** Passages travel without their document: keep headings
meaningful, keep sections self-contained, and put the subject in the section rather than
relying on the title three levels up.

## 4. Record provenance, so ranking and filters can use it

Give every knowledge instance a `kind` indexed `filter`/`facet` — `readme`, `summary`,
`adr`, `runbook`, `commit-log`, `symbol`. It costs one field and buys:

- filtering a question to the sources that can answer it
- telling a current ADR from a superseded one
- reporting coverage: which applications have no documentation at all

Status and recency belong here too (`status`, `updated_at`), for the same reason: a
superseded document should be excludable without reading it.

## 5. Derive artifacts; do not dump sources

For code especially, ingest **distillates**, not the raw material:

| Artifact | Content | Answers |
|----------|---------|---------|
| `summary` | 200–400 words: what it does, its surface, its vocabulary | "what does this service do" |
| `symbols` | identifiers, error strings, index names — one lean instance each | "where is `idx_orders_unique` defined" |
| `reference` | the docs people already wrote | everything else |

Raw source files answer questions worse than a short generated summary and cost far more
to index.

**Keep exact-match instances lean.** A symbol instance carrying several paragraphs of
surrounding prose competes with — and displaces — the document those paragraphs came
from. Measured on a real corpus: trimming symbol context from ~1700 to ~270 characters
moved the top hit for two questions off the symbol and onto the document that actually
explained the answer. Give a symbol its identifier and a line of context, no more.

## 6. Model for the questions, in both regimes

Two axes decide what a spec must declare. Get either wrong and the question becomes
unanswerable *after* ingest, when re-writing every instance is the only fix.

**Quantitative vs qualitative.** *How many / what proportion* is answered by indexed
scalars and facets; *what happened / what does this say* is answered by ranking over
semantic fields. **A property you will ever want to count, filter or facet needs its own
indexed scalar** — prose cannot be counted, and ranking registers topic rather than
polarity, so a record saying *"**no** schema changes"* ranks alongside one that has them.
Whatever your domain's version of that property is, store it as a typed field at ingest;
planning to infer it from the prose later means the number is simply unobtainable
without re-writing every instance.

**Discovery vs scoped.** *Discovery* ranks the whole tenant (*"which service handles
refunds?"*). *Scoped* bounds first, then ranks (*"how does retry work here?"*) —
more accurate and cheaper, because it ranks one neighborhood. Scoping needs a **graph**,
which is a modeling decision made at spec time: no relation, no bound.

Both regimes are `sort=relevance` on `/search`; the difference is whether you scope.
See `semantic-retrieval.md` for the request shapes and `method-selection.md` for
choosing and combining methods.

## 7. Make derived fields observable

Any field your ingest **computes** rather than copies — a classification, a score, a
detector's boolean, a "first time we saw this" flag — decays differently from a field
you were given. A missing field is visible the moment someone looks. A field that is
confidently wrong looks exactly like a field that is right, and every count built on it
inherits the error.

- **Index derived fields `filter` + `facet`.** One facet call then doubles as a health
  check, showing fill rate and distribution together without transferring rows. Cheap
  enough to run on a schedule.
- **Prefer nullable to a default.** "We determined no" and "we could not determine" are
  different claims; collapsing them into `false` makes a detector that never fires
  indistinguishable from a population that genuinely has nothing to report.
- **Cross-check derived fields against each other.** Two fields describing overlapping
  facts should agree; where their counts contradict, at least one is broken. Facets
  surface that for free, and it is the cheapest bug detector available — a detector
  firing on a handful of records while a related flag claims the opposite about most of
  them is a defect, not a finding.
- **Keep a rationale field** (`fulltext`) beside any scored or classified field. The
  score says *what*, the rationale is the only evidence for *why*, and without it the
  classification can only be trusted, never audited.

## 8. Denormalize deliberately, and reconcile

Where a record carries **both** a relation to an entity and a plain label naming it, that
is not redundancy to eliminate — the two fail in opposite directions, and keeping both is
what lets you detect the failure:

- the **relation** is exact and traversable, but is absent wherever ingest could not
  resolve the target, and those records silently vanish from every graph walk
- the **label** survives a failed resolution, but silently merges entities that share a
  name

Store both, and reconcile as routine: traverse from one anchor and compare the node count
against a filter on the label. Agreement is cheap reassurance; disagreement localises an
ingest bug immediately. Grouping on either key alone means dropping records or merging
them, with nothing to indicate which happened.

## Anti-patterns

| Anti-pattern | What it costs |
|---|---|
| Everything in one spec with a `parent` field | No graph. Nothing can be bounded, so every question ranks the whole tenant |
| Prose indexed `fulltext` instead of `semantic` | Silent zero results under `sort=relevance` — no error to debug |
| One instance per file, whole file in one field | Content past the cap is dropped, and long documents crowd out precise answers |
| Placeholder instances for absent things | Filters, facets and counts are wrong from then on |
| Raw source code ingested wholesale | Large index, worse answers than a short summary |
| Exact-match instances carrying long prose | They displace the documents that actually explain the answer |
| No `kind`/`status` on knowledge instances | Cannot separate current from superseded, or measure documentation coverage |
| A property that will be counted stored only in prose | Ranking cannot count and cannot see negation — the number is unobtainable after ingest without re-writing every instance |
| Derived boolean written as `false` when undetermined | An under-firing detector is indistinguishable from a clean population |
| Derived fields not indexed `facet` | No cheap health check; fill rate and drift stay invisible until a reader notices |
| A classified field with no rationale field beside it | The classification cannot be audited, only trusted |
| Denormalized label without its relation (or vice versa) | Graph walks silently drop null-FK records; label grouping silently merges name collisions |

## A worked shape

An organization's code knowledge, using every instrument for its own job:

```
account
  └── has_many namespace
        └── has_many application ──belongs_to──> repository
                                                    │
                                    has_many artifact (kind: summary|readme|reference|commits)
                                                    ├── has_many section  (body ← semantic)
                                                    └── has_many symbol   (lean, exact-match)

concept  (term, definition ← semantic) ──many_to_many──> artifact
```

- hierarchy bounds questions to an application or a namespace
- `artifact.kind` filters and weights by provenance
- `section.body` carries the prose that gets ranked
- `symbol` serves exact identifier lookups without competing with prose
- `concept` is top-level and linked many-to-many, so "how does soft delete work"
  reaches every implementation rather than being trapped in whichever document
  happened to define it first
