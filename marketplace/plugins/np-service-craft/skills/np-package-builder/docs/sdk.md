# The plugin SDK (`@nullplatform/plugin`)

Current: **0.0.5** (npm tag `latest`). The SDK turns a TypeScript file into a
worker: it owns the gRPC server, action routing, lifecycle reporting, and
`--describe`. You write handlers; everything else is the SDK's.

## Reading an SDK package

```
src/
  index.ts          # defineScope({...}) — the package's whole surface
  actions/*.ts      # one handler per action: async (notification, emit) => result
```

`defineScope` (equivalently `defineService` for services) declares:

- `name`, `assetType` (carried through `--describe` since 0.0.5 — the manifest
  schema wins over any CLI default; this is what fixes the "everything is
  docker-image" bug),
- `actions: { "<slug>": { name, type, input, handler } }`,
- `agent: { selector, entrypoint }` (optional): how the platform routes to it.
  Defaults: `selector: { package: <name> }`, entrypoint
  `/app/packages/<name>/entrypoint`. **Selectors must be unique per package**
  — see architecture.md Hazards.

## The handler contract

```ts
export default async function (notification, emit) { ... return result }
```

`notification` is the action context (parameters, service, package + revision
with its pinned artifacts, tags, entity_nrn). `emit` streams progress lines —
they land in the platform log viewer, ANSI allowed.

## ctx surface (what handlers can use)

- `ctx.api` — authenticated generic core: `get(path, query)`,
  `request(method, path, body)`, `list` / `listAll` (auto-paginates
  `{paging, results}` envelopes). The generic core exists because the SDK will
  NOT always track the API: anything is reachable without an SDK release.
- `ctx.api.scopes / deployments / applications / namespaces / accounts /
  releases` — resource facades (`get`, `list`, `iterate`) built on the core.
- `ctx.entity` — the acting entity parsed from the NRN (memoized fetches that
  drop failed results rather than caching errors).
- `ctx.step(name, fn, { retries, timeoutMs })` — named steps; errors carry the
  step name.
- `ctx.log` / styled terminal output (NO_COLOR honored at call time).
- `ctx.settings` — resolution ladder: env → platform parameters → derived.
- `ctx.deployment.reportTraffic(...)` — **the ONLY deployment verb.**

## The orchestrator boundary (do not violate)

Deployment finalization and status patching happen at the platform level, in
an orchestrator that is NOT the SDK's responsibility. A package answers
service actions; it never finalizes deployments or patches entity statuses.
`reportTraffic` is the single deliberate exception. If a handler seems to need
to "mark the deployment done" — it doesn't; the platform does that when the
action result comes back.

## Auth

The SDK exchanges the worker's `NP_API_KEY` for a token
(`POST /token`), caches it until expiry. Workers get the key injected by the
agent automatically — never bake keys into images.

## Action-spec annotations (closed vocabulary)

Unlike artifact annotations (free-form), action-spec `annotations` accept ONLY
`runs_over` (deployment|scope|instance) and `show_on` (array of
scope|performance|manage|deployment). The API **silently strips any other key
with a 200** — `{"my":"thing"}` persists as `{}`. Don't burn time on it.
