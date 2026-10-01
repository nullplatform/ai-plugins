# Migrating a scope/service from the old model to packages

**Old model**: the agent clones git repos (`AGENT_REPO` /
`--command-executor-git-command-repos`), actions exec the shared entrypoint
from `nullplatform/scopes` on the agent's own filesystem, code arrives by
`git pull`.

**New model**: the package is an OCI image (worker-bridge base or SDK runtime),
pinned by digest in a package revision; the agent spawns it as a worker and
streams actions over gRPC. No git on the agent, immutable versions, per-package
isolation.

## Migration checklist

1. **Containerize** — add a Dockerfile on `worker-bridge` (see
   worker-bridge.md). Workflows/scripts usually move UNCHANGED: the entrypoint
   dispatch and `np service workflow exec` work identically inside the worker.
   Add every tool the workflows call (tofu, aws-cli, kubectl, gomplate…) to the
   image — there is no host to borrow from anymore.
2. **CI** — adopt the shared chain (`release-publish-oci.yml@main`; per-repo
   wiring: `AWS_ROLE_ARN_ECR_PUSH`, `ARTIFACT_NP_API_KEY`, `NP_ARTIFACT_NRN`)
   or a repo-specific workflow with `np artifact login` when OIDC subjects are
   a problem (newer repos emit immutable `repo:org@ID/repo@ID:` subjects that
   classic trust policies reject).
3. **Register the package** — either `np package publish` (SDK-style repos) or
   the tofu modules' `package` block (see tofu-modules.md): one revision whose
   BOM pins the spec + actions + links + the image artifact by digest.
4. **Channel** — the notification channel moves to command type
   **`package-exec`** with sources **`service` + `telemetry`** (so the worker
   also serves `log:read` / `instance:data`). The channel's package name and
   entrypoint MUST match the image (`NP_PACKAGE_NAME`,
   `NP_SCOPE_ENTRYPOINT`) and MUST be unique per package — a channel copied
   from another package with its old name creates the shared-worker-key hazard
   (see architecture.md).
5. **Agent config** — add the image's registry to `worker.allowedRegistries`
   (or pin exactly: `worker.pins` with the digest — trusted, never reaped).
   Remove the now-unneeded `AGENT_REPO` git wiring once nothing uses it.
6. **Cut over one scope first** — create/route a test scope, watch the agent
   log for the worker spawn (`kubectl get deploy -n <ns>` shows
   `np-worker-<instance>-<package>-<version>`), run create/delete, THEN move
   the fleet.

## Verifying a migration (like we actually do it)

- Pull the published image and look inside before trusting it:
  `docker run --rm --entrypoint sh <image@digest> -c 'ls /app/pkg; env | grep NP_'`
  — confirm the content matches the repo and the NP_* envs point at the right
  paths. (This caught an Azure-flavored build masquerading as an S3 one.)
- Confirm the artifact registered on the platform, not just that CI is green:
  `np artifact list --visible-to "<nrn>" --type oci_image` and check the digest
  equals what the release table says.
- After the first action, read the worker log END-TO-END: the workflow path it
  executed (`/app/pkg/<pkg>/...`) tells you which package's code really ran.
- Same action id appearing twice with different workflow paths = the shared
  worker-key hazard; fix the channel package names, not the agent.
