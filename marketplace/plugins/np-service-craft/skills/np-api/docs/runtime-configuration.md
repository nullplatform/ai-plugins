# Runtime Configuration

Runtime configurations allow provisioning reusable environments that decouple
infrastructure (DevOps) from application operation (Developers). They function as
"search facets for scopes": dimension attributes are defined and developers
select combinations when creating scopes.

**DEPRECATION NOTE**: This feature may be removed in the future. Nullplatform recommends
using platform settings and providers instead.

## Concept

- Scopes alone are sufficient for simple scenarios
- Runtime configurations address complex infrastructure (e.g., production in different cloud accounts)
- Require that dimensions and their values exist BEFORE creating the runtime configuration
- Values are stored internally as NRN API profiles

## @endpoint /runtime_configuration

Lists runtime configurations.

### Parameters
- `nrn` (query, required): URL-encoded NRN

### Response
Structure to be confirmed — the endpoint requires elevated permissions with developer tokens.
With standard API keys it returns `"You're not authorized to perform this operation."`.

### Example
```bash
# Requires elevated permissions (admin or platform team)
np-api fetch-api "/runtime_configuration?nrn=organization%3D<org>%3Aaccount%3D<acc>"
```

### Notes
- Without NRN returns `"NRN is required for this endpoint"`
- With developer NRN returns `"You're not authorized to perform this operation."`
- Probably contains runtime configurations injected into scopes/deployments
- Different from `parameters` which are explicit environment variables
- Requires investigation with an admin or platform team token to fully document
- **Potentially deprecated** — consider using providers and platform settings

## Relationship with scopes

Runtime configurations are assigned to scopes via:
- `POST /scope/{id}/runtime_configuration` — Assign a runtime config to a scope
- `DELETE /scope/{id}/runtime_configuration/{id}` — Remove a runtime config from a scope

These operations are documented in the official documentation but require elevated permissions.

## Relationship with dimensions

Runtime configurations depend on the dimensions system:
1. Create dimensions and their values first (`/dimension`)
2. Create the runtime configuration referencing those dimensions
3. Scopes that match the dimensions inherit the configuration
