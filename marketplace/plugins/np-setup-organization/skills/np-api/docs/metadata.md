# Metadata (Catalog)

Metadata y metadata specifications de entidades. Tambien conocido como **Catalog** en la
documentacion oficial (rebranding). El sistema de catalog permite adjuntar metadata estructurada
y reutilizable a entidades (applications, builds, namespaces).

Estos endpoints viven en el microservicio `metadata.nullplatform.io` y se acceden via la API
publica con el prefijo `/metadata/`.

**IMPORTANTE**: Todos los endpoints de este archivo requieren el prefijo `/metadata/` en la URL.
Ejemplo: para llegar a `metadata.nullplatform.io/metadata_specification` se usa
`np-api fetch-api "/metadata/metadata_specification?..."`.

---

## @endpoint /metadata/metadata_specification

Obtiene el schema formal de metadata para una entidad en un NRN especifico.
Devuelve los campos requeridos, tipos, enums y descripciones definidos por la organizacion.

### Parametros
- `entity` (query, required): Tipo de entidad (`application`, `build`, `namespace`, etc.)
- `nrn` (query, required): NRN del contexto (URL-encoded). Puede ser a nivel namespace, account u organization.
- `merge` (query, optional): `true` para mergear specifications heredadas de niveles superiores del NRN

### Respuesta
```json
{
  "paging": {"offset": 0, "limit": 30},
  "results": [
    {
      "id": "uuid",
      "entity": "application",
      "metadata": "application",
      "name": "Application",
      "nrn": "organization=X:account=Y:namespace=Z",
      "schema": {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "required": ["businessUnit", "pci", "slo", "applicationOwner"],
        "properties": {
          "businessUnit": {
            "type": "string",
            "description": "The business unit responsible for the service",
            "enum": ["Credits", "Payments", "OnBoarding", "KYC", "Money Market"]
          },
          "pci": {
            "type": "string",
            "description": "Whether the service is PCI compliant",
            "enum": ["Yes", "No"]
          }
        },
        "additionalProperties": false
      }
    }
  ]
}
```

### Navegacion
- **← desde application creation**: Se necesita para saber que metadata pedir al usuario al crear una app
- **← desde build metadata**: Se usa para validar metadata de builds

### Ejemplo
```bash
# Metadata specification para aplicaciones en un namespace
np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973&merge=true"
```

### Propiedades de Catalog en el schema

Las properties del JSON Schema pueden tener campos adicionales que controlan el comportamiento
en la UI (sistema Catalog):

| Campo | Descripcion | Ejemplo |
|-------|-------------|---------|
| `visibleOn` | Controla donde se muestra el campo en la UI | `["create", "read", "update", "list"]` |
| `tag` | Habilita el campo como tag/filtro en dashboards | `true` o `"custom_tag_name"` |
| `uiSchema` | Override del layout automatico del formulario | `{"ui:widget": "textarea"}` |
| `links` | Renderiza bloques de recursos dedicados | Ver docs oficiales |

**`visibleOn` valores:**
- `create`: visible al crear la entidad
- `read`: visible al ver la entidad
- `update`: visible al editar la entidad
- `list`: visible en listados/tablas

### Entidades soportadas
- `application`: metadata de aplicaciones
- `build`: metadata de builds (ej: test coverage, security scan results)
- `namespace`: metadata de namespaces

### Notas
- El `nrn` en el query param debe estar URL-encoded (`:` → `%3A`, `=` → `%3D`)
- Los campos del schema son **organizacion-especificos**: cada org define sus propios campos
- `merge=true` combina specifications de todos los niveles del NRN (org + account + namespace)
- El campo `schema` sigue el formato JSON Schema draft-07
- `required` indica campos obligatorios al crear la entidad
- `enum` en las properties define los valores validos (se muestran como dropdowns en el UI)
- Si `results` esta vacio, la organizacion no requiere metadata para esa entidad
- **Catalog vs Metadata**: "Catalog" es el nombre nuevo en la documentacion oficial; la API sigue usando `/metadata/` como prefijo
- Los campos con `tag: true` se indexan y permiten filtrado rapido en la UI
- `visibleOn` es clave para controlar que campos aparecen en cada contexto de la UI

---

## @endpoint /metadata/{entity}/{id}

Lee metadata de una entidad especifica.

### Parametros
- `entity` (path, required): Tipo de entidad (`application`, `build`, `namespace`)
- `id` (path, required): ID de la entidad

### Respuesta (GET)
```json
{
  "application": {
    "businessUnit": "Payments",
    "pci": "No",
    "slo": "High",
    "applicationOwner": "Jane Smith"
  },
  "additional_properties": {}
}
```

### Ejemplo
```bash
# Leer metadata de una aplicacion
np-api fetch-api "/metadata/application/489238271"

# Leer metadata de multiples entidades por ID
np-api fetch-api "/metadata/application?id=123,456,789"
```

### Notas
- La metadata de una aplicacion tambien se incluye en `GET /application/{id}` (campo `metadata`)
- Pero la lista `GET /application` NO incluye metadata - requiere fetch individual o usar este endpoint
