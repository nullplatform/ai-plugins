# Dimensions

Dimensions definen los ejes de variacion (environment, country, region, etc.) para clasificar
scopes, servicios, parametros, approvals y runtime configurations.

**IMPORTANTE**: Las dimensions se crean a un nivel de NRN especifico, NO necesariamente a nivel
de organizacion. Cascadean hacia abajo (los hijos heredan). No puede haber la misma dimension
en una relacion parent-child (si, en siblings).

Se usan al crear scopes, servicios, deployments y en policies de approvals.

## @endpoint /dimension

Lista dimensions disponibles en un NRN, incluyendo dimensions heredadas de niveles superiores.

### Parametros
- `nrn` (query, required): NRN con URL encoding. Acepta cualquier nivel de la jerarquia.
  - Escanea hacia arriba: devuelve dimensions del NRN especificado y todos sus padres
  - Soporta wildcards: `account=*` para escanear hijos

### Respuesta
```json
{
  "paging": {"total": 2, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 1599217067,
      "name": "Environment",
      "slug": "environment",
      "nrn": "organization=1255165411",
      "status": "active",
      "order": 1,
      "values": [
        {"id": 1977891659, "name": "Development", "slug": "development"},
        {"id": 209213675, "name": "Production", "slug": "production"},
        {"id": 217338261, "name": "Stress Test", "slug": "stress-test"}
      ],
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Campos clave
- `id`: ID numerico de la dimension
- `name`: Nombre visible (ej: "Environment", "Country")
- `slug`: Identificador URL-friendly. **Este es el key que se usa en el campo `dimensions` de scopes y servicios**
- `nrn`: NRN donde fue creada la dimension (puede ser org, account, namespace, etc.)
- `order`: Orden de prioridad/display
- `values[]`: Valores posibles para la dimension
  - `id`: ID numerico del valor
  - `name`: Nombre visible (ej: "AR", "Production")
  - `slug`: **Este es el value que se usa en el campo `dimensions`** (ej: "argentina", "production")
  - `nrn`: NRN del valor (puede ser un nivel mas bajo que la dimension misma)

### Relacion con otras entidades

El campo `dimensions` en scopes, servicios, links, approvals y runtime configurations usa los slugs:
```json
{
  "dimensions": {
    "environment": "production",
    "country": "argentina"
  }
}
```
Donde `"environment"` es el slug de la dimension y `"production"` es el slug del valor.

### NRN y herencia de dimensions

Las dimensions cascadean hacia abajo en la jerarquia de NRN:
- Una dimension creada en `organization=1` es visible en todos los accounts, namespaces y applications
- Una dimension creada en `organization=1:account=2` es visible solo en ese account y sus hijos

**Restriccion parent-child**: No puede existir la misma dimension (mismo slug) en un NRN parent Y un NRN child. Si puede existir en siblings (ej: dos accounts diferentes pueden tener dimensions con el mismo slug).

### Ejemplo
```bash
# Dimensions de la organizacion (nivel mas alto)
np-api fetch-api "/dimension?nrn=organization%3D1255165411"

# Dimensions visibles desde un account (incluye heredadas de org)
np-api fetch-api "/dimension?nrn=organization%3D1255165411%3Aaccount%3D95118862"

# Dimensions de todos los accounts (wildcard)
np-api fetch-api "/dimension?nrn=organization%3D1255165411%3Aaccount%3D*"

# Solo las dimensions activas con sus valores
np-api fetch-api "/dimension?nrn=organization%3D1255165411" | jq '[.results[] | {name: .slug, values: [.values[] | .slug]}]'
```

### Notas
- Las dimensions se crean a un nivel de NRN especifico, no necesariamente a nivel de org
- Los valores de dimension pueden tener NRN propio (a nivel mas bajo que la dimension)
- Al crear un scope, los valores de `dimensions` deben coincidir con slugs validos de este endpoint
- Al crear un servicio, las `dimensions` restringen en que scopes puede linkearse
- Se necesitan permisos `ops` para crear/modificar dimensions
- Precaucion al agregar muchas dimensions: aumenta la complejidad de la matriz de scopes

---

## @endpoint /dimension/{id}

Obtiene detalle de una dimension especifica (sin sus valores).

### Parametros
- `id` (path, required): ID numerico de la dimension

### Respuesta
```json
{
  "id": 1599217067,
  "name": "Environment",
  "nrn": "organization=1255165411",
  "slug": "environment",
  "status": "active",
  "order": 1,
  "created_at": "...",
  "updated_at": "..."
}
```

### Notas
- No incluye los valores de la dimension (usar `GET /dimension?nrn=...` para obtener valores incluidos)
- Util para verificar si una dimension especifica existe

---

## @endpoint /dimension/value

Lista dimension values filtrados por NRN.

### Parametros
- `nrn` (query, required): NRN con URL encoding. Soporta wildcards.

### Respuesta
```json
{
  "paging": {"total": 10, "offset": 0, "limit": 30},
  "results": [
    {
      "id": 587888267,
      "name": "AR",
      "slug": "argentina",
      "nrn": "organization=1255165411",
      "status": "active",
      "created_at": "...",
      "updated_at": "..."
    }
  ]
}
```

### Ejemplo
```bash
# Valores de dimension a nivel de organizacion
np-api fetch-api "/dimension/value?nrn=organization%3D1255165411"

# Valores con wildcard (todos los accounts)
np-api fetch-api "/dimension/value?nrn=organization%3D1255165411%3Aaccount%3D*"
```

### Notas
- Util cuando se necesitan solo los valores sin la dimension padre
- Los valores individuales pueden tener NRN propio a un nivel mas bajo que la dimension

---

## @endpoint /dimension/value/{id}

Obtiene detalle de un dimension value especifico.

### Parametros
- `id` (path, required): ID numerico del valor

### Respuesta
```json
{
  "id": 587888267,
  "name": "AR",
  "slug": "argentina",
  "nrn": "organization=1255165411",
  "status": "active",
  "created_at": "...",
  "updated_at": "..."
}
```

### Notas
- Util para verificar si un valor especifico existe
- El `slug` es lo que se usa como value en el campo `dimensions` de scopes/servicios
