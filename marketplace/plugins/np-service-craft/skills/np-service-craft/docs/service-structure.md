# Service File Structure

A packaged service repo puts the `Dockerfile` at the **root** and the service in a directory
named after its slug — not nested under `services/`. Verified against
`nullplatform/services-s-3`, `nullplatform/services-blob-storage` and
`nullplatform/services-postgresql-k-8-s`.

```
<repo-root>/
+-- Dockerfile                          # Builds the worker image (→ /np-package-builder)
+-- .dockerignore / README.md / …        # optional; varies per repo
+-- <service-slug>/
    +-- specs/
    |   +-- service-spec.json.tpl       # Service definition: schema for UI, selectors, export config
    |   +-- links/
    |       +-- connect.json.tpl        # Link definition: access levels, credentials
    +-- deployment/
    |   +-- main.tf                     # Terraform resources that create the cloud resource
    |   +-- variables.tf                # Variables from build_context (service_name, params, etc)
    |   +-- outputs.tf                  # Outputs returned to NP (connection_string, endpoint, etc)
    |   +-- providers.tf                # Provider configuration (aws, azurerm, etc)
    +-- permissions/
    |   +-- main.tf                     # IAM/RBAC resources created when an app links
    |   +-- locals.tf                   # Access level -> permissions mapping
    |   +-- variables.tf                # With app_role_name default "" for local testing
    +-- workflows/<provider>/
    |   +-- create.yaml                 # Steps: build_context -> do_tofu apply [-> write_service_outputs]
    |   +-- delete.yaml                 # Steps: build_context -> do_tofu destroy
    |   +-- update.yaml                 # Steps: build_context -> do_tofu apply [-> write_service_outputs]
    |   +-- link.yaml                   # Steps: build_context -> build_permissions_context -> do_tofu [-> write_link_outputs]
    |   +-- link-update.yaml            # Steps: build_context -> build_permissions_context -> do_tofu apply [-> write_link_outputs]
    |   +-- unlink.yaml                 # Steps: build_context -> build_permissions_context -> do_tofu destroy
    |   +-- read.yaml                   # (optional) Read current state
    +-- scripts/<provider>/
    |   +-- build_context               # Parses CONTEXT (JSON) + VALUES (file path) -> env vars
    |   +-- do_tofu                     # Generic: copies module, runs tofu init + apply/destroy
    |   +-- build_permissions_context   # (if links) Separate context for permissions module
    |   +-- write_service_outputs       # (if export fields) Writes tofu outputs to service attributes
    |   +-- write_link_outputs          # (if link credentials) Writes tofu outputs to link attributes
    +-- entrypoint/
    |   +-- entrypoint                  # Main router: bridges NP_API_KEY, dispatches to service/link
    |   +-- service                     # Maps action type to workflow, calls np service workflow exec
    |   +-- link                        # Maps create->link, update->link-update, delete->unlink
    +-- values.yaml                     # Static config: region, profiles, resource names (not in UI)
```

## The image is the unit of delivery

Everything the service needs at run time — `entrypoint/`, `scripts/`, `workflows/`,
`deployment/`, `permissions/`, `values.yaml` and the tooling they call — is baked into the
image by `COPY . /app/pkg`. The agent no longer clones a repo, so anything left out is not
there when the worker starts.

`specs/` is the exception, and not in the way you would expect: the spec files are **not**
read from the image. `service_definition` fetches them over HTTPS from the repository on
every `apply`, which is why `repository_org`, `repository_name` and `repository_branch` stay
required even in packaged mode.

