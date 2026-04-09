# Service File Structure

Every nullplatform service follows this directory layout:

```
services/<service-name>/
+-- specs/
|   +-- service-spec.json.tpl       # Service definition: schema for UI, selectors, export config
|   +-- links/
|       +-- connect.json.tpl        # Link definition: how apps connect (access levels, credentials)
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

## Directory Roles

| Directory | Purpose | Changes per service? |
|-----------|---------|---------------------|
| `specs/` | Define what users see in the UI | Yes - unique per service |
| `deployment/` | Create cloud resources | Yes - unique per service |
| `permissions/` | Grant access when linking | Yes - unique per service |
| `workflows/` | Orchestrate script execution | Mostly template, minor tweaks |
| `scripts/` | Parse context, run tofu, write outputs | Partially template |
| `entrypoint/` | Route notifications to handlers | Generic template |
| `values.yaml` | Environment-specific config | Yes - unique per deployment |
