# Metadata specifications

Optional step of the wizard: adds metadata specifications to the `nullplatform/` layer —
application fields shown when creating and editing an application, and build results (coverage,
vulnerabilities) reported by CI.

Templates: `${CLAUDE_PLUGIN_ROOT}/skills/np-nullplatform-wizard/templates/metadata/`

- `catalog.json` — every available specification, keyed by metadata key.
- `metadata.tf` — one `nullplatform_metadata_specification` per entry of `nullplatform/metadata.json`.

## Question

`AskUserQuestion` allows at most 4 options per question, so this takes two calls:

1. **"Add metadata?"** — `Yes, choose which` / `No metadata`. On **No**, skip this step: no file
   is copied.
2. On **Yes**, one call with two questions:
   - **"Which application metadata?"** — `multiSelect: true`:

     | Option | Key in `catalog.json` | Fields |
     |--------|-----------------------|--------|
     | Owner | `owner` | `application_owner` (required), `contact_email` |
     | Business Unit | `business_unit` | `name` (required, one of a list) |
     | SLA | `sla` | `service_tier`, `availability_target`, `latency_p95_ms`, `error_budget_policy` |
     | Environment | `environment` | `name` (one of the environment values) |

   - **"Which build metadata?"** — `multiSelect: true`: `Coverage` / `Security` /
     `No build metadata`:

     | Option | Key in `catalog.json` | Fields |
     |--------|-----------------------|--------|
     | Coverage | `coverage` (entity `build`) | `code.coverage` (required, 0–100), `code.lines` |
     | Security | `security` (entity `build`) | `security.vulnerabilities.critical`, `.high` (both required) |

   If **Business Unit** is selected, ask for the client's business units (comma-separated): the
   catalog carries placeholder values (`Digital Services`, `Finance`, …).

   **Environment** is an application-level field (default `development`): it fits clients that
   model one application per environment. When an application has scopes in several environments
   — the usual model, where the environment dimension classifies scopes — leave it out.

## Generation

```bash
TPL="${CLAUDE_PLUGIN_ROOT}/skills/np-nullplatform-wizard/templates/metadata"
cp "$TPL/metadata.tf" nullplatform/
# Keep only the selected keys, e.g. owner + business_unit + sla + environment + coverage + security:
jq '{owner, business_unit, sla, environment, coverage, security}' "$TPL/catalog.json" > nullplatform/metadata.json
# A misspelled key yields null (e.g. "owners": null) and only fails at plan time: check it now
jq -e 'all(.[]; . != null)' nullplatform/metadata.json
```

Then adapt the enums in `nullplatform/metadata.json`:

| Key | Set `enum` to | Path |
|-----|---------------|------|
| `business_unit` | the business units the user gave | `.business_unit.schema.properties.name.enum` |
| `environment` | the values of the environment dimension chosen in this wizard (and `default` to one of them) | `.environment.schema.properties.name.enum` / `.default` |

```bash
jq --argjson v '["Retail", "Payments"]' '.business_unit.schema.properties.name.enum = $v' \
  nullplatform/metadata.json > nullplatform/metadata.json.new && mv nullplatform/metadata.json.new nullplatform/metadata.json
```

`metadata.tf` needs no edits: it reads `metadata.json` with `file()` and uses `var.nrn` (from
`common.tfvars`). An account-level NRN works; a namespace NRN is not required.

Validate as the rest of the layer (`tofu init -backend=false && tofu validate`). The plan adds one
`nullplatform_metadata_specification` per key in `metadata.json`.

## Build metadata: reported by CI

`coverage` and `security` live on the **build**, not on the application: nobody fills them in the
UI. The CI pipeline reports them for each build, once tests and scans ran (`NULLPLATFORM_API_KEY`
in the CI environment; the data is keyed by the metadata key):

```bash
np metadata create --entity build --id "$BUILD_ID" \
  --data '{"coverage": {"code": {"coverage": 85.5, "lines": 1200}}}'
np metadata create --entity build --id "$BUILD_ID" \
  --data '{"security": {"security": {"vulnerabilities": {"critical": 0, "high": 2}}}}'
```

The `security` schema has a root property also named `security`, hence the double nesting.
Pass the build with `--id`: the CLI's lookup flags (`--application-id` + `--commit-sha`) panicked on
`np` 2.10.1 (`interface conversion: interface {} is nil, not string`).

`np metadata create` only works the **first** time for a build: if the build already has that
metadata it fails with `400 Metadata for entity "build" with ID "<id>" and metadata "<key>" already
exists`, and the CLI has no update command. To change a value already reported (a re-run, a
correction), use the API. The body is the value **without** the metadata key:

```text
PATCH https://api.nullplatform.com/metadata/build/<BUILD_ID>/coverage
{"code": {"coverage": 91, "lines": 1250}}

PATCH https://api.nullplatform.com/metadata/build/<BUILD_ID>/security
{"security": {"vulnerabilities": {"critical": 0, "high": 2}}}
```

The schema is enforced on every write, `create` and `PATCH` alike (`coverage: 150` → `400 body/code/coverage must be <= 100`; a
missing `high` → `400 body/security/vulnerabilities must have required property 'high'`). The values
are read back at these paths, which is what a checklist `condition` uses to gate deploys:

| Key | Path |
|-----|------|
| `coverage` | `build.metadata.coverage.code.coverage` |
| `security` | `build.metadata.security.security.vulnerabilities.critical` / `.high` |

## How it behaves day to day

- Adding or removing a key in `metadata.json` creates or destroys only that specification.
- Editing a schema updates the specification in place. Re-running `tofu apply` with no changes is
  a no-op (the schema is normalized with `jsonencode`).
- A field in `required` (e.g. `owner.application_owner`) becomes mandatory when creating an
  application.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Invalid function argument` — `no file exists at "./metadata.json"` | `metadata.tf` copied without `metadata.json` | Generate `metadata.json`, or remove `metadata.tf` if the user chose no metadata |
| `Error in function call` — `while calling jsondecode(str)` | `metadata.json` is not valid JSON | `jq . nullplatform/metadata.json` shows where it breaks |
| `failed to create metadata specification: status code 400` — `Specification for entity "application" with metadata "<key>" already exists` | Another specification with the same `entity` + `metadata` key exists on that NRN | Import it: `tofu import 'nullplatform_metadata_specification.this["<key>"]' <id>`, or remove the existing one |
