# Builds, Releases y Assets

Pipeline de código: Build → Asset → Release → Deployment

## @endpoint /build/{id}

Obtiene detalles de un build.

### Parámetros
- `id` (path, required): ID del build

### Respuesta
- `id`: ID numérico
- `status`: pending | running | success | failed | canceled
- `application_id`: ID de la aplicación
- `repository_url`: URL del repositorio Git
- `commit_hash`: SHA del commit
- `branch`: Nombre del branch
- `tag`: Tag de Git (null si no es tag build)
- `created_at`, `started_at`, `finished_at`: Timestamps
- `build_log_url`: URL de logs (puede ser null)
- `error_message`: Mensaje de error (solo si failed)
- `assets[]`: Artefactos generados
  - `id`: ID del asset
  - `type`: container
  - `uri`: URI del container image (ECR)
- `metadata`: Propiedades adicionales (solo en GET individual)

### Navegación
- **→ application**: `application_id` → `/application/{application_id}`
- **→ asset**: `assets[].id` → `/asset/{asset_id}`
- **← application**: `/build?application_id={application_id}`

### Ejemplo
```bash
np-api fetch-api "/build/1524929544"
```

### Notas
- Builds failed no crean assets
- `tag` solo se popula en builds triggereados por tags
- `metadata` solo disponible en GET individual, NO en listas

---

## @endpoint /build

Lista builds de una aplicación.

### Parámetros
- `application_id` (query, required): ID de la aplicación
- `status` (query): Filtra por status
- `limit` (query): Máximo de resultados

### Respuesta
```json
{
  "paging": {...},
  "results": [...]
}
```

### Ejemplo
```bash
np-api fetch-api "/build?application_id=489238271&limit=50"
np-api fetch-api "/build?application_id=489238271&status=failed&limit=50"
```

---

## @endpoint /release/{id}

Obtiene detalles de un release.

### Parámetros
- `id` (path, required): ID del release

### Respuesta
- `id`: ID numérico
- `application_id`: ID de la aplicación
- `build_id`: ID del build asociado
- `status`: active
- `version`: Versión del release
- `specification`:
  - `replicas`: Número de réplicas
  - `resources`: memory, cpu
  - `environment_variables`: Variables de entorno

### Navegación
- **→ application**: `application_id` → `/application/{application_id}`
- **→ build**: `build_id` → `/build/{build_id}`
- **← application**: `/release?application_id={application_id}`
- **← deployment**: `deployment.release_id`

### Ejemplo
```bash
np-api fetch-api "/release/258479089"
```

---

## @endpoint /release

Lista releases de una aplicación.

### Parámetros
- `application_id` (query, required): ID de la aplicación
- `limit` (query): Máximo de resultados

### Ejemplo
```bash
np-api fetch-api "/release?application_id=489238271&limit=50"
```

---

## @endpoint /asset/{id}

Obtiene detalles de un asset (container image).

### Parámetros
- `id` (path, required): ID del asset

### Respuesta
- `id`: ID numérico
- `type`: container
- `uri`: URI completo del container (ECR URL)
- `build_id`: ID del build que lo creó
- `size`: Tamaño en bytes
- `digest`: Hash del container

### Navegación
- **→ build**: `build_id` → `/build/{build_id}`

### Ejemplo
```bash
np-api fetch-api "/asset/668494956"
```

---

## @endpoint /asset

Lista assets de un build.

### Parámetros
- `build_id` (query): Filtra por build

### Ejemplo
```bash
np-api fetch-api "/asset?build_id=1524929544"
```
