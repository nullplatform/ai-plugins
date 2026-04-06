# NRN (Nullplatform Resource Name)

NRN es un identificador jerarquico unico para cualquier recurso en Nullplatform (similar a AWS ARN).
Ademas de identificar recursos, el endpoint `/nrn/` funciona como un key-value store jerarquico
con herencia automatica.

**NOTA DEPRECACION**: El NRN como key-value store podria ser removido en el futuro.
Nullplatform recomienda usar platform settings y providers en su lugar.

## Formato

```
organization=123:account=456:namespace=789:application=101:scope=202
```

Niveles (de mayor a menor):
1. `organization=<id>`
2. `organization=<id>:account=<id>`
3. `organization=<id>:account=<id>:namespace=<id>`
4. `organization=<id>:account=<id>:namespace=<id>:application=<id>`
5. `organization=<id>:account=<id>:namespace=<id>:application=<id>:scope=<id>`

## NRN como scope de configuracion

Muchas entidades se crean a un nivel de NRN y cascadean a hijos:

| Entidad | Cascadea | Ejemplo |
|---------|----------|---------|
| Dimension | Si | Creada en org, visible en todos los accounts/namespaces/apps |
| Entity Hook Action | Si | Creada en account, aplica a todas las apps del account |
| Notification Channel | Si (con showDescendants) | Creada en account, visible con `showDescendants=true` |
| Runtime Configuration | Si | Creada a un nivel, afecta scopes que matcheen dimensions |
| Approval Action | Si | Creada en account, aplica a todas las apps del account |

**Regla parent-child para Dimensions**: No puede haber la misma dimension en parent Y child.
Si puede haber en siblings (dos accounts diferentes).

## @endpoint /nrn/{nrn_string}

Lee valores del key-value store jerarquico. Los valores se heredan y mergean desde niveles
superiores.

### Parametros
- `nrn_string` (path, required): NRN completo (NO URL-encoded en el path)
- `ids` (query, **required**): Lista de keys separados por coma
- `output_json_values` (query): `true` para parsear JSON en vez de devolver strings
- `no-merge` (query): `true` para obtener solo valores de este nivel, sin herencia
- `profile` (query): Nombre del profile a aplicar

### Ejemplo
```bash
# Leer valores especificos
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1,key2"

# Sin herencia (solo este nivel)
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1&no-merge=true"

# Con profile
np-api fetch-api "/nrn/organization=1255165411:account=95118862?ids=key1&profile=my-profile"
```

### Herencia y merge

Cuando se lee un key en un NRN child:
1. Se busca el key en el NRN especificado
2. Si no existe, se busca en el parent (y asi sucesivamente)
3. Si existe en multiples niveles, se hace **deep merge** de JSON objects y arrays
4. El child overridea los valores del parent

### Notas
- `ids` es **obligatorio** — sin el, el endpoint no devuelve nada util
- Los valores pueden ser strings, JSON objects, o JSON arrays
- Con `output_json_values=true`, los JSON strings se parsean automaticamente
- Con `no-merge=true`, solo se devuelven valores del nivel exacto del NRN
- **Potencialmente deprecado**: considerar usar platform settings/providers

---

## @endpoint /nrn/{nrn_string}/available_profiles

Lista los profiles disponibles para un NRN.

### Parametros
- `nrn_string` (path, required): NRN completo

### Ejemplo
```bash
np-api fetch-api "/nrn/organization=1255165411:account=95118862/available_profiles"
```

### Notas
- Los profiles permiten configuracion cross-cutting (ej: configuracion por ambiente)
- Naming convention: `${profile_name}::${namespace}.${key}`
- Los profiles tienen ordering (numero menor = mayor prioridad)
- Se asignan a scopes para aplicar la configuracion correspondiente

---

## Wildcards en NRN

Algunos endpoints soportan wildcards para escanear niveles:

```bash
# Todos los accounts de la org (dimension, service, etc.)
GET /dimension?nrn=organization%3D1255165411%3Aaccount%3D*

# Todos los services de la org
GET /service?nrn=organization%3D1255165411%3Aaccount%3D*&limit=1500
```

El wildcard `*` reemplaza el ID en un nivel y devuelve resultados de todos los hijos.

## URL Encoding

En query params, el NRN debe estar URL-encoded:
- `=` → `%3D`
- `:` → `%3A`

En path params (`/nrn/{nrn_string}`), el NRN va sin encoding.
