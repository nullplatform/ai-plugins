# API Keys

Credenciales para acceso programático a la API de Nullplatform.

## @endpoint /api-key/{id}

Obtiene detalles de una API key específica.

### Parámetros
- `id` (path, required): ID numérico de la API key

### Respuesta
- `id`: ID numérico
- `name`: Nombre descriptivo de la key
- `api_key`: Token (parcialmente oculto, ej: `np_...xxxx`)
- `grants`: Array de permisos asignados
  - `nrn`: NRN del contexto donde aplica el permiso
  - `role_slug`: Identificador del rol asignado
- `tags`: Array de tags key-value
  - `key`: Nombre del tag
  - `value`: Valor del tag
- `created_at`: Timestamp de creación

### Roles Conocidos
| Role Slug | Descripción |
|-----------|-------------|
| `controlplane:agent` | Comunicación con el control plane |
| `ops` | Ejecutar operaciones y comandos |
| `developer` | Acceso de desarrollo |
| `secrets-reader` | Leer secrets y parámetros |
| `secops` | Operaciones de seguridad |

### Navegación
- **→ roles**: `grants[].role_slug` indica permisos asignados
- **← notification_channel**: El canal de tipo `agent` referencia una API key

### Ejemplo
```bash
np-api fetch-api "/api-key/1896628918"
```

### Respuesta de Ejemplo
```json
{
  "id": 1896628918,
  "name": "SCOPE_DEFINITION_AGENT_ASSOCIATION",
  "api_key": "np_...8a4f",
  "grants": [
    {
      "nrn": "organization=1875247450:account=1514930957",
      "role_slug": "controlplane:agent"
    },
    {
      "nrn": "organization=1875247450:account=1514930957",
      "role_slug": "ops"
    }
  ],
  "tags": [
    {"key": "managed-by", "value": "IaC"}
  ],
  "created_at": "2025-01-25T10:30:00Z"
}
```

### Notas
- El valor secreto completo solo se muestra al crear la key
- Keys creadas por Terraform tienen tag `managed-by: IaC`
- Para notification channels, la API key necesita al menos `controlplane:agent` + `ops`

---

## @endpoint /api-key

Lista API keys con filtros.

### Parámetros
- `nrn` (query, optional): Filtra por NRN (URL-encoded)
- `name` (query, optional): Filtra por nombre
- `limit` (query, optional): Máximo de resultados (default: 30)
- `offset` (query, optional): Para paginación

### Respuesta
```json
{
  "paging": {
    "total": 5,
    "offset": 0,
    "limit": 30
  },
  "results": [
    {
      "id": 1896628918,
      "name": "SCOPE_DEFINITION_AGENT_ASSOCIATION",
      "grants": [...],
      "tags": [...],
      "created_at": "..."
    }
  ]
}
```

### Navegación
- **→ detalle**: `results[].id` → `/api-key/{id}`

### Ejemplos
```bash
# Listar todas las API keys de una organización
np-api fetch-api "/api-key?nrn=organization%3D1875247450"

# Buscar por nombre específico
np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# Con paginación
np-api fetch-api "/api-key?nrn=organization%3D1875247450&limit=10&offset=0"
```

### Notas
- El NRN debe estar URL-encoded (`=` → `%3D`, `:` → `%3A`)
- Sin filtros retorna las keys accesibles para el usuario actual
- Respuesta paginada con `paging` y `results`

---

## Casos de Uso Comunes

### Diagnosticar Permisos de un Notification Channel

Cuando un scope falla con "You're not authorized":

```bash
# 1. Obtener el channel del scope
np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"

# 2. Buscar la API key por nombre (visible en el canal)
np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# 3. Ver los grants de la API key
np-api fetch-api "/api-key/{api_key_id}"

# 4. Verificar que tiene: controlplane:agent + ops
```

### Comparar API Keys

Para verificar diferencias entre la API key de un canal y la del agente:

```bash
# API key del canal (creada por Terraform)
np-api fetch-api "/api-key/1896628918"

# API key del agente (más permisos)
np-api fetch-api "/api-key/1724072588"
```

La del agente típicamente tiene más roles que la del canal.
