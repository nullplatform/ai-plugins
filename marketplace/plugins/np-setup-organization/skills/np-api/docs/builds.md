# Builds, Releases, and Assets

Code pipeline: Build → Asset → Release → Deployment

## @endpoint /build/{id}

Gets details of a build.

### Parameters
- `id` (path, required): Build ID

### Response
- `id`: Numeric ID
- `status`: pending | running | success | failed | canceled
- `application_id`: Application ID
- `repository_url`: Git repository URL
- `commit_hash`: Commit SHA
- `branch`: Branch name
- `tag`: Git tag (null if not a tag build)
- `created_at`, `started_at`, `finished_at`: Timestamps
- `build_log_url`: Log URL (may be null)
- `error_message`: Error message (only if failed)
- `assets[]`: Generated artifacts
  - `id`: Asset ID
  - `type`: container
  - `uri`: Container image URI (ECR)
- `metadata`: Additional properties (only in individual GET)

### Navigation
- **→ application**: `application_id` → `/application/{application_id}`
- **→ asset**: `assets[].id` → `/asset/{asset_id}`
- **← application**: `/build?application_id={application_id}`

### Example
```bash
np-api fetch-api "/build/1524929544"
```

### Notes
- Failed builds don't create assets
- `tag` is only populated in tag-triggered builds
- `metadata` only available in individual GET, NOT in lists

---

## @endpoint /build

Lists builds of an application.

### Parameters
- `application_id` (query, required): Application ID
- `status` (query): Filter by status
- `limit` (query): Maximum results

### Response
```json
{
  "paging": {...},
  "results": [...]
}
```

### Example
```bash
np-api fetch-api "/build?application_id=489238271&limit=50"
np-api fetch-api "/build?application_id=489238271&status=failed&limit=50"
```

---

## @endpoint /release/{id}

Gets details of a release.

### Parameters
- `id` (path, required): Release ID

### Response
- `id`: Numeric ID
- `application_id`: Application ID
- `build_id`: Associated build ID
- `status`: active
- `version`: Release version
- `specification`:
  - `replicas`: Number of replicas
  - `resources`: memory, cpu
  - `environment_variables`: Environment variables

### Navigation
- **→ application**: `application_id` → `/application/{application_id}`
- **→ build**: `build_id` → `/build/{build_id}`
- **← application**: `/release?application_id={application_id}`
- **← deployment**: `deployment.release_id`

### Example
```bash
np-api fetch-api "/release/258479089"
```

---

## @endpoint /release

Lists releases of an application.

### Parameters
- `application_id` (query, required): Application ID
- `limit` (query): Maximum results

### Example
```bash
np-api fetch-api "/release?application_id=489238271&limit=50"
```

---

## @endpoint /asset/{id}

Gets details of an asset (container image).

### Parameters
- `id` (path, required): Asset ID

### Response
- `id`: Numeric ID
- `type`: container
- `uri`: Full container URI (ECR URL)
- `build_id`: ID of the build that created it
- `size`: Size in bytes
- `digest`: Container hash

### Navigation
- **→ build**: `build_id` → `/build/{build_id}`

### Example
```bash
np-api fetch-api "/asset/668494956"
```

---

## @endpoint /asset

Lists assets of a build.

### Parameters
- `build_id` (query): Filter by build

### Example
```bash
np-api fetch-api "/asset?build_id=1524929544"
```
