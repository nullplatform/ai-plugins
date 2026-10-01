# Distilling org-level lore candidates

Org-level lore candidates come from **deterministic aggregation** over the analysed data
(counts of naming tokens, base images, hostnames, dependencies across the org's apps) — not
from AI judgement.

- Every candidate carries its **count as evidence** ("prefix `kco-` = 116 apps, 86/93 verified against the graph").
- **Separate proven from inferred**: acronyms and tokens without a proven meaning go to a "to confirm" section; they are never asserted.
- **Never promote alone**: the candidate is confirmed with the org owner and only then enters via `set_norm`. The AI proposes; the human approves. When the ground is already curated: suggestion → verification → curator approves → projection.
- Once registered, a focus with `kind: lore` over the affected apps records the violations as findings (→ Ver `/np-kb-extend`).
