# External sources in the catalog: documentation pages as nodes

An organization can plug external sources into its knowledge base (→ Ver `/np-kb-extend`). The
canonical example is a public documentation site: pages become `doc:<path>` nodes (kind
`document`, `description` = public URL), every app gets a `documentation` facet (one entry per
page), an edge `<app> documented-by doc:<path>` with the cited sections in `via`, and every
code ↔ documentation contradiction is a finding of category `doc-drift`.

## Which systems does this page document?

The page is a node; `who_consumes` on it:

```
who_consumes {target: "doc:docs/notifications/channels.md"}
→ [{ from_node: "notifications-api", edge_type: "documented-by", provenance: "IA",
     evidence: "domain/channel.js:8-166, services/notifications_service.js:225-315, …",
     via: "docs:docs/notifications/channels.md#channels · …#agent · …#configuration-fields" }]
blast_radius {node: "doc:docs/notifications/channels.md", direction: "inbound", depth: 2}
→ affected: notifications-api, public-api-gateway, web-backend-for-frontend, …
```

Answer with the edge: "notifications-api is documented by that page in the sections channels,
agent and configuration-fields (evidence domain/channel.js:8-166)". At the second hop it is no
longer documentation: it is the app's consumption graph; say so.

## What does the doc say that the code does not do?

```
list_findings {component: "notifications-api", status: "open"}   → filter categoria == "doc-drift"
→ { titulo: "…", prioridad: "medium",
    evidencia: "domain/channel.js:159-166, docs:docs/notifications/manage-channels.md#delete-a-channel" }
```

Quote both anchors verbatim. A `doc-drift` with a single anchor is a missing-page finding ("no
public page identified"), not a contradiction.

## If I touch this file, which documentation do I review?

```
get_facet {component: "notifications-api", facet: "documentation"}
→ entries[0]: { path: "docs/notifications/channels.md", url: "https://…/channels",
     describes: ["domain/channel.js:8-166", "services/notifications_service.js:225-315"],
     sections: ["docs:…#channels", "docs:…#agent"], provenance: "IA:verified" }
```

Look for the file in the `describes` of each entry. After a deploy the delta already did it: the
"Affected documentation" section of `recent-changes` and the `docs:<app>` question in
`list_questions` list page → touched files. Per-entry provenance matters: `IA` with unverified
anchors means the page was recorded without a verified fact over those files; say so when the
question is about confidence.
