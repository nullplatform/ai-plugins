# Applications

Aplicaciones son contenedores de código desplegable que definen runtime, build, health checks y recursos.

## @endpoint /application/{id}

Obtiene detalles de una aplicación.

### Parámetros
- `id` (path, required): ID de la aplicación

### Respuesta
- `id`: ID numérico
- `name`: Nombre único dentro del namespace
- `type`: service | function | job | static
- `status`: active | inactive | archived
- `nrn`: Identificador jerárquico (organization=X:account=Y:namespace=Z:application=W)
- `specification.runtime`: language, version
- `specification.build`: command, output_path
- `specification.health_check`: path, port, initial_delay_seconds, period_seconds, timeout_seconds, failure_threshold
- `specification.resources`: memory, cpu
- `metadata`: Propiedades adicionales (solo en GET individual, NO en listas)

### Navegación
- **→ namespace**: del NRN extraer namespace_id → `/namespace/{namespace_id}`
- **→ scopes**: `/scope?application_id={id}`
- **→ builds**: `/build?application_id={id}`
- **→ services**: via `linkable_to` en services

### Ejemplo
```bash
np-api fetch-api "/application/489238271"
```

### Notas
- `specification.health_check` es crítico para troubleshooting de deployments
- `initial_delay_seconds` muy bajo causa probe failures en apps Java (necesitan 60-120s)
- `metadata` solo disponible en GET individual, NO en listas - no se puede filtrar por metadata

---

## @endpoint /application

Lista aplicaciones con filtros.

### Parámetros
- `namespace_id` (query): Filtra por namespace
- `status` (query): Filtra por status (active, inactive, archived)
- `limit` (query): Máximo de resultados (default 30)
- `offset` (query): Para paginación

### Respuesta
```json
{
  "paging": {"total": 69, "offset": 0, "limit": 30},
  "results": [
    {"id": 123, "name": "my-app", "type": "service", "status": "active"}
  ]
}
```

### Navegación
- **→ application details**: `/application/{id}` para cada resultado

### Ejemplo
```bash
np-api fetch-api "/application?namespace_id={namespace_id}&limit=100"

# Solo aplicaciones activas
np-api fetch-api "/application?namespace_id={namespace_id}&status=active"
```

### Notas
- Respuesta paginada con `paging` y `results`
- NO incluye campo `metadata` - requiere fetch individual por ID
- Usar `status=active` para excluir aplicaciones inactivas o archivadas

---

## @endpoint /template

Lista templates de tecnologia disponibles para crear aplicaciones.

### Parametros
- `target_nrn` (query, recommended): NRN del namespace para filtrar templates aplicables
- `global_templates` (query): `true` para incluir templates globales de Nullplatform ademas de las de la org
- `limit` (query): Maximo de resultados (default 30, usar 200 para obtener todos)

### Respuesta
```json
{
  "paging": {},
  "results": [
    {
      "id": 1220542475,
      "name": "NodeJS + Fastify",
      "status": "active",
      "url": "https://github.com/nullplatform/technology-templates-nodejs-container",
      "organization": null,
      "account": null,
      "tags": ["javascript", "fastify", "backend"],
      "rules": {},
      "components": [{"type": "language", "id": "javascript", "version": "es6"}]
    }
  ]
}
```

### Navegacion
- **← desde application**: `template_id` en la aplicacion → `/template/{id}` (no documentado, usar lista)

### Ejemplo
```bash
# Templates para un namespace especifico (incluye globales)
np-api fetch-api "/template?limit=200&target_nrn=organization=X:account=Y:namespace=Z&global_templates=true"
```

### Notas
- Templates con `organization: null` son globales de Nullplatform
- Templates con `organization` y `account` son especificas de la org/cuenta
- Filtrar `status: "active"` antes de mostrar al usuario
- El campo `rules` puede contener reglas de validacion de nombre y path de repositorio
- `components` describe la tecnologia (language, framework, runtime)
