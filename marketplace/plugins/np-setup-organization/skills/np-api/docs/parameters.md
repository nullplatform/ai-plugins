# Parameters, Values y Versions

Variables de entorno y configuración jerárquica. Los parámetros tienen una estructura de dos niveles:
- **Parameter**: Definición (nombre, tipo, secret, NRN)
- **Parameter Values**: Valores concretos por dimensión (ej: un valor para production, otro para development)
- **Parameter Versions**: Historial de cambios del parámetro

## @endpoint /parameter

Lista parámetros por NRN.

### Parámetros

- `nrn` (query, required): NRN jerárquico

### NRN Formats

```
organization={org_id}:account={acc_id}:namespace={ns_id}:application={app_id}
organization={org_id}:account={acc_id}:namespace={ns_id}:application={app_id}:scope={scope_id}
```

### Respuesta

```json
{
  "paging": {"offset": 0, "limit": 30, "total": 5},
  "results": [
    {
      "id": 671080587,
      "name": "CONSULTING_PRICES_DB_HOSTNAME",
      "nrn": "organization=...:account=...:namespace=...:application=...",
      "type": "environment",
      "encoding": "plaintext",
      "variable": "CONSULTING_PRICES_DB_HOSTNAME",
      "secret": false,
      "read_only": true,
      "version_id": 1791955022,
      "values": [
        {
          "id": "683303163",
          "nrn": "organization=...:account=...:namespace=...:application=...",
          "value": "172.20.144.91",
          "created_at": "2026-02-12T14:44:02.872Z",
          "dimensions": {"environment": "production"},
          "external": null
        }
      ]
    }
  ]
}
```

### Campos del parameter

- `id`: ID numérico
- `name`: Nombre del parámetro (UPPER_SNAKE_CASE)
- `nrn`: NRN del nivel donde se definió (application o scope)
- `type`: `environment` (variable de entorno) | `linked_service` (generado por service link)
- `encoding`: `plaintext`
- `variable`: Nombre de la env var inyectada al container (generalmente igual a `name`)
- `secret`: boolean - si el valor se enmascara en UI y logs
- `read_only`: boolean - `true` para parámetros generados por service links
- `version_id`: ID de la versión actual del parámetro
- `values[]`: Array de valores por dimensión (ver estructura abajo)

### Campos de cada value

- `id`: ID del value (string)
- `nrn`: NRN donde aplica el valor
- `value`: Valor concreto (string). `null` si `secret: true`
- `dimensions`: Object con las dimensiones donde aplica (ej: `{"environment": "production"}`)
- `created_at`: Timestamp de creación
- `external`: Referencia externa (null si no aplica)

### Notas

- Un parámetro puede tener múltiples values para distintas dimensiones (ej: un valor para production, otro para development)
- Al consultar con NRN de scope, retorna los parámetros resueltos para ese scope (application + scope-level)
- Los parámetros `secret: true` devuelven `value: null` en lectura
- Los parámetros `read_only: true` fueron generados por service links y no se pueden modificar
- El `type` real en la API es `environment`, no `variable`

### Ejemplo

```bash
# Parámetros de aplicación
np-api fetch-api "/parameter?nrn=organization=1255165411:account=95118862:namespace=463208973:application=2052735708"

# Parámetros resueltos para un scope específico
np-api fetch-api "/parameter?nrn=organization=1255165411:account=95118862:namespace=463208973:application=2052735708:scope=675195311"
```

---

## @endpoint /parameter/{id}

Obtiene un parámetro individual por ID.

### Parámetros

- `id` (path, required): ID del parámetro

### Respuesta

Misma estructura que cada elemento de `/parameter`, incluyendo `values[]`.

### Navegación

- **→ values**: Embebidos en la respuesta como `values[]`
- **→ versions**: `/parameter/{id}/version`
- **← application**: `/parameter?nrn={application_nrn}`

### Ejemplo

```bash
np-api fetch-api "/parameter/671080587"
```

---

## @endpoint /parameter/{id}/version

Lista todas las versiones disponibles de un parámetro.

### Parámetros

- `id` (path, required): ID del parámetro

### Respuesta

```json
{
  "results": [
    {
      "id": 1791955022,
      "created_at": "2026-02-12T14:44:02.813Z",
      "user_id": 629868107
    }
  ]
}
```

### Campos

- `id`: ID de la versión
- `created_at`: Timestamp de creación
- `user_id`: ID del usuario que creó la versión

### Navegación

- **→ user**: `user_id` → `/user/{user_id}`

### Ejemplo

```bash
np-api fetch-api "/parameter/671080587/version"
```

---

## @endpoint /parameter/{parameterId}/value/{sourceValueId}/compare/{targetValueId}

Compara dos values de un mismo parámetro.

### Parámetros

- `parameterId` (path, required): ID del parámetro
- `sourceValueId` (path, required): ID del primer value
- `targetValueId` (path, required): ID del segundo value

### Ejemplo

```bash
np-api fetch-api "/parameter/671080587/value/683303163/compare/683303164"
```

### Notas

- Útil para comparar valores entre dimensiones (ej: production vs development)

---

## @endpoint /nrn/{nrn}

Obtiene configuración a nivel de plataforma por NRN.

### Parámetros

- `nrn` (path, required): NRN jerárquico (URL encoded)
- `ids` (query, required): Lista de keys a obtener (comma-separated)

### Formato de IDs

```
namespace.key
```

Namespaces comunes: `global`, `prod`, `staging`

### Respuesta

```json
{
  "nrn": "organization=123:account=456",
  "namespaces": {
    "global": {
      "key1": "value1"
    },
    "prod": {
      "key2": "value2"
    }
  },
  "omittedKeys": ["nonexistent.key"]
}
```

### Ejemplo

```bash
np-api fetch-api "/nrn/organization=549683990:account=463975847:namespace=476951634?ids=global.key1,prod.key2"
```

### Notas

- Requiere `ids` explícito - no retorna todas las keys
- Keys no existentes aparecen en `omittedKeys`
- Diferente de `/parameter` - este es config de plataforma interna
