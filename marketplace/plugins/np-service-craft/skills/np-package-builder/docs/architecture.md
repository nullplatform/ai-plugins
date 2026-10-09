# How the control plane runs packages: agent + workers

The only long-lived thing installed in a cluster is the **agent**
(`controlplane-agent`). It has no separate controller: it spawns **workers**
itself and streams actions to them over gRPC.

```
control plane (specs / packages / artifacts / channels / parameters)
        │  package-exec notifications (channel selector matches agent TAGS)
        ▼
agent ── resolves worker ── validates image ── ensures worker ── gRPC :50051 ──▶ worker
                                                                 (one Deployment+Service
                                                                  per package, k8s backend;
                                                                  host container, docker backend)
```

## The action flow, precisely

1. A `package-exec` notification arrives on a channel whose **selector tags**
   match the agent's `TAGS` (e.g. `cluster:runtime,package:my-scope`).
2. The agent resolves WHICH worker runs it. Package slug precedence:
   **the command's explicit `package` field** (set by the channel) →
   `notification.package.slug` → `service.specification.slug` →
   `NP_WORKER_PACKAGE`. Version: command field → `package.version` →
   `package.revision.version`.
3. Image resolution: an operator **pin** for (package, version) in
   `NP_WORKERS` → `NP_WORKER_IMAGE` (single-worker global pin — dangerous on
   multi-package agents, see Hazards) → dynamically from the action payload's
   `oci_image` artifact.
4. **Validation**: a dynamically-resolved image must match an
   `NP_ALLOWED_REGISTRIES` glob (deny-by-default; `*` matches `/` too; empty
   list = every dynamic package-exec refused). Pins are trusted and bypass the
   allow-list.
5. The worker is created if missing or **reused** if warm. Worker identity =
   `(package, version)`.
6. The action streams over gRPC; stdout/stderr and results flow back. Channels
   register with `service` + `telemetry` sources, so the same worker also
   serves `log:read` / `instance:data`.

## Worker lifecycle facts that matter

- **Adoption**: workers carry an `agent-instance` label; a restarted agent
  re-adopts running workers instead of orphaning or duplicating them. Workers
  deliberately survive agent restarts and rolling updates.
- **Convergence**: every action re-applies the desired worker Deployment; a
  `spec-hash` annotation gates updates. New image/env for the same
  (package, version) → the Deployment is updated and Kubernetes rolls the pod.
- **Secret rotation rolls workers**: `env-hash` / `tls-hash` pod-template
  annotations tie the pod to its secret env — rotating `NP_API_KEY` rolls
  worker pods.
- **Idle reaper** (`NP_WORKER_IDLE_TTL`, Go duration): a worker is removed only
  when idle ≥ TTL, 0 in-flight, dynamic (pins are NEVER reaped), past one TTL
  of grace since creation, and not labelled `nullplatform.com/keep-alive`.
  Empty = disabled.
- **Per-worker env from the agent**: `NP_WORKER_ENV` (comma-separated
  `KEY=VALUE` in the agent secret) is injected into every worker — how e.g. a
  GitHub App identity reaches workers without living in any repo. `NP_API_KEY`
  and cluster CA trust are injected automatically.

## Hazards (all observed in production)

- **Never share a channel package name between specs.** Two specs whose
  channels both say `package: x` share ONE worker key: each action re-converges
  the Deployment to ITS image, the images flip-flop, and an action can execute
  on the other package's code (the Service selects old+new pods mid-rollout).
  One package name per package, always.
- **`NP_WORKER_IMAGE` is a global pin**: on an agent serving several packages
  it sends every unpinned package to that one image. Prefer per-package `pins`.
- A worker's dial target is a stable Service DNS name — cached gRPC connections
  survive image rolls, so during a rollout a dispatch can still land on the old
  pod. If an action seems to have run "old code", check agent logs for
  `worker "...": spec changed (hash ...)` flips.

## Helm chart (`helm-charts/charts/agent`, `nullplatform-agent`)

Minimal install:

```yaml
configuration:
  create: true
  values:
    NP_API_KEY: "<agent api key>"
    TAGS: "cluster:runtime"
worker:
  backend: kubernetes            # or docker (host containers)
  allowedRegistries:
    - "public.ecr.aws/nullplatform/*"
  idleTTL: "20m"
```

Key `worker.*` values:

| Value | What it does |
|---|---|
| `allowedRegistries` | the deny-by-default allow-list (`NP_ALLOWED_REGISTRIES`) |
| `patches` | THE way to shape workers (`NP_WORKER_PATCHES`): per-target (`package`/`version` glob; empty = every worker) standard k8s patches — `merge:` (strategic) or `json:` (RFC-6902) on the worker Pod. Docker backend honors the `worker` container subset |
| `pins` | exact trusted workers (`NP_WORKERS`): package+version+image (+per-pin serviceAccount/resources/env/namespace). Pin by digest for immutability |
| `namespace` | worker namespace; empty = the agent's own |
| `idleTTL` | idle reaper |
| `security: mtls` | agent mints a per-process CA; only the agent can call workers. Default `insecure` |
| `networkPolicy.create` | only-the-agent-reaches-workers policy (needs enforcing CNI) |
| `rbac.create` | namespace-scoped Role for worker management when the agent's RBAC is scoped down |

Consumer side of custom registries: the registry must be in
`allowedRegistries`, and private registries need an image-pull secret in the
workers' namespace (`worker.defaults.imagePullSecrets` / a patch).

## Artifacts (what the image resolution consumes)

An artifact = identity (`registry` + `repository` for oci_image; `url` for
git_repository) + revisions (each unique meta blob: `digest`, optional `tag`,
`reference`). `tag` participates in revision minting — re-registering an old
digest WITH a new tag mints a NEW revision. `annotations` are non-identity
(curated `changelog` markdown ≤64KB rendered as release notes in the console,
free-form reverse-DNS keys, whole blob ≤256KB) and replace WHOLE on
re-registration (last write wins — CIs send the complete set every run).
`visible_to` supports trailing wildcards and global `organization=*`;
consumers list with `?visible_to=` (owner `?nrn=` can never see globals).

### git_repository ("git tree"): a pointer, NEVER a payload

The platform stores only `{ url, reference }` — never repository content. At
execution, the command carries `sources: [{repository, reference}]`; the
agent's gitmanager resolves the reference (tags → branches → commit),
materialises a versioned worktree at `{basePath}/{repository}@{reference}`,
and `rewriteCmdline` substitutes every path-token occurrence of the repository
in the channel's cmdline with `{repository}@{reference}` (idempotent,
boundary-aware — `org/foo` never rewrites inside `org/foo-bar`). So
`/root/.np/org/repo/scope/entrypoint` executes as
`/root/.np/org/repo@v1.4.0/scope/entrypoint`.

Rules that follow:
- **Never put secrets in a git-referenced repo.** Every agent that runs it
  fetches the full content with its own git credentials; secrets belong in
  platform parameters (env / `--include-secrets`) or the agent's
  `NP_WORKER_ENV`.
- Artifact `visible_to` governs who may *reference* it — repo ACLs are a
  separate git-side concern; agents without git access fail at clone.
- Branch references are mutable upstream; only tags/SHAs deliver the
  immutability the artifact model promises.
