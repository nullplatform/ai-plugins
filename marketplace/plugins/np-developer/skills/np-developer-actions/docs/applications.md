# Crear Aplicacion

Crear una nueva aplicacion dentro de un namespace.

Una aplicacion es la unidad principal de deploy en Nullplatform. Cada aplicacion tiene un
repositorio de codigo, un template de tecnologia, y metadata organizacional definida por
la organizacion.

---

## Prerequisito: Verificar contexto de git

**ANTES de iniciar el flujo**, verificar si el directorio de trabajo actual es un repositorio git:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

### Si ES un repositorio git → CASO NO SOPORTADO

Informar al usuario:

> "Crear una aplicacion nueva desde un repositorio git existente no esta soportado todavia
> por este skill. La creacion de una aplicacion genera un repositorio nuevo, lo cual entra
> en conflicto con el repositorio actual. Para crear una aplicacion nueva, ejecuta este
> skill desde un directorio que no sea un repositorio git."

**No continuar con el flujo.**

### Si NO es un repositorio git → Continuar con el flujo

---

## @action POST /application

Crea una nueva aplicacion en un namespace.

### Flujo obligatorio

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery, pasos 1-4)
> y `/np-developer-actions exec-api` para ESCRITURA (paso 7). NUNCA usar `curl` ni
> `/np-api` para operaciones POST.

#### Paso 1: Descubrir la jerarquia y elegir el namespace

El unico dato garantizado al inicio es el `organization_id`, que se extrae del JWT token.
No asumir que se conoce `account_id` ni `namespace_id` - hay que descubrirlos.

```bash
# 1a. Obtener organization_id del token
np-api check-auth
# Output incluye: Organization ID: <org_id>

# 1b. Listar accounts de la organizacion
np-api fetch-api "/account?organization_id=<org_id>&status=active"
# Si hay un solo account activo, usarlo directamente.
# Si hay multiples, preguntar al usuario cual usar.

# 1c. Listar namespaces del account elegido
np-api fetch-api "/namespace?account_id=<account_id>&status=active&limit=50"
# Preguntar al usuario en que namespace crear la aplicacion.
```

Del response de namespaces obtener `id`, `name`, `slug` y `nrn` del namespace elegido.
El `nrn` del namespace se necesita para el paso 2 (templates).

#### Paso 2: Obtener templates disponibles

```bash
np-api fetch-api "/template?limit=200&target_nrn=<namespace_nrn>&global_templates=true"
```

Donde `namespace_nrn` es el NRN del namespace (ej: `organization=X:account=Y:namespace=Z`).

Mostrar al usuario las templates disponibles:

| # | Nombre | Tags | ID |
|---|--------|------|----|

Notas:
- `global_templates=true` incluye templates globales de Nullplatform ademas de las de la org
- Templates con `status: "inactive"` NO deben mostrarse
- Templates con `organization` y `account` son especificas de la org
- Templates con `organization: null` son globales de Nullplatform

#### Paso 3: Obtener metadata specification

La metadata es **organizacion-especifica**. Cada org define que campos adicionales requiere
al crear una aplicacion (ej: business unit, PCI compliance, SLO, owner).

Obtener el schema formal con campos, tipos, enums y required fields:

```bash
np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=<namespace_nrn_url_encoded>&merge=true"
```

Donde `namespace_nrn_url_encoded` es el NRN del namespace con `=` → `%3D` y `:` → `%3A`.
Ejemplo: `organization%3D1255165411%3Aaccount%3D95118862%3Anamespace%3D463208973`

La respuesta contiene un JSON Schema en `results[].schema` con:
- `required`: campos obligatorios
- `properties`: cada campo con `type`, `description`, y opcionalmente `enum` (valores validos)

Ejemplo de respuesta:

```json
{
  "results": [{
    "schema": {
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
        },
        "slo": {
          "type": "string",
          "description": "Service Level Objective classification",
          "enum": ["Critical", "High", "Medium", "Low"]
        },
        "applicationOwner": {
          "type": "string",
          "description": "The lead of the application",
          "enum": ["John Doe", "Jane Smith", "..."]
        }
      }
    }
  }]
}
```

Si `results` esta vacio, la organizacion no requiere metadata para aplicaciones.

> **IMPORTANTE**: El endpoint de metadata specification esta en el microservicio de metadata,
> accesible via API publica con prefijo `/metadata/`. La ruta completa es
> `/metadata/metadata_specification`. Ver `np-api docs/metadata.md` para mas detalles.

#### Paso 4: Determinar repository URL

El repositorio se genera automaticamente siguiendo el patron:

```
https://github.com/<git_org>/<namespace_slug>-<app_slug>
```

Donde:
- `git_org`: la organizacion de GitHub configurada en la cuenta (ej: `kwik-e-mart`)
- `namespace_slug`: slug del namespace (ej: `nullplatform-demos`)
- `app_slug`: slug generado del nombre de la app (ej: `test-app-discovery`)

El usuario puede elegir entre:
- **New repository**: se crea automaticamente con el template
- **Import existing code**: el usuario provee una URL de repo existente

Si el usuario quiere "new repository", construir la URL con el patron anterior.
Si quiere "import existing code", pedirle la URL del repositorio.

#### Paso 5: Preguntar al usuario

Usando `AskUserQuestion`, confirmar:
1. **Nombre** de la aplicacion
2. **Template** a usar
3. **Repository**: nuevo o importar (si importar, pedir URL)
4. **Metadata**: valores para los campos organizacionales

#### Paso 6: Confirmar con el usuario

Mostrar un resumen amigable para el usuario. NO mostrar detalles tecnicos (POST, JSON, endpoints).
El usuario no necesita ver la request, solo entender que se va a hacer.

Ejemplo de confirmacion:

> Voy a crear la aplicacion **orders-api** con estos datos:
> - **Namespace**: Nullplatform Demos
> - **Template**: Next.JS Build Coverage & Vulnerabilities scan
> - **Repositorio**: https://github.com/kwik-e-mart/nullplatform-demos-orders-api
> - **Business Unit**: OnBoarding
> - **PCI**: No
> - **SLO**: Critical
> - **Owner**: Michael Johnson
>
> ¿Confirmas?

Pedir confirmacion explicita.

#### Paso 7: Ejecutar

```bash
action-api.sh exec-api --method POST --data '{
  "name": "<app_name>",
  "namespace_id": <namespace_id>,
  "template_id": <template_id>,
  "repository_url": "<repo_url>",
  "metadata": {
    "application": {
      "campo1": "valor1",
      "campo2": "valor2"
    }
  }
}' "/application"
```

#### Paso 8: Verificar resultado

```bash
np-api fetch-api "/application/<app_id>"
```

La aplicacion pasa por: `creating` → `active`.

Si `status: "active"`:
- Mostrar el ID, nombre, slug, repository_url
- Continuar al paso 9 (clonar repositorio)

Si `status` no es `active` despues de ~30 segundos:
- Verificar si hay `messages` en la respuesta
- Puede haber fallado la creacion del repositorio en GitHub
- Verificar entity hooks y approvals (ver paso 8a y 8b)

##### Paso 8a: Verificar approvals

Si la aplicacion queda en `creating` o `pending`, puede requerir aprobacion:

```bash
# Buscar approvals para la aplicacion (NRN URL-encoded: = → %3D, : → %3A)
np-api fetch-api "/approval?nrn=<nrn_url_encoded>&entity=application&action=create"
```

Si hay un approval pendiente, seguir la misma logica de interpretacion que en scopes.md
(ver tabla completa de `status` + `execution_status`).

##### Paso 8b: Verificar entity hooks

Si la aplicacion queda stuck sin approval aparente, verificar si hay entity hooks bloqueando:

```bash
# Buscar entity hooks que apliquen a la creacion de aplicaciones
np-api fetch-api "/entity_hook?nrn=<nrn_url_encoded>"
```

Filtrar por hooks que tengan `entity: "application"` y `on: "create"` (o `on: "after_create"`).
Si hay hooks con `status: "recoverable_failure"` o `status: "failed"`, informar al usuario
que un hook esta bloqueando la creacion y mostrar los detalles del hook.

#### Paso 9: Clonar repositorio y preservar .claude/

Una vez la aplicacion esta `active`, clonar el repositorio nuevo al directorio de trabajo
actual, preservando la carpeta `.claude/` con los skills.

```bash
# 1. Guardar la carpeta .claude/ actual en un temporal
CLAUDE_BACKUP=$(mktemp -d)
cp -r .claude "$CLAUDE_BACKUP/"

# 2. Clonar el repositorio nuevo al directorio actual
#    (el directorio debe estar vacio salvo por .claude/)
git clone <repository_url> .

# 3. Restaurar .claude/ al repositorio clonado
cp -r "$CLAUDE_BACKUP/.claude" .

# 4. Limpiar temporal
rm -rf "$CLAUDE_BACKUP"

# 5. Agregar .claude/ al repositorio y hacer commit
git add .claude/
git commit -m "Add Claude skills configuration"
git push
```

> **IMPORTANTE**: El `git clone` requiere que el directorio este vacio (salvo `.claude/`).
> Si hay otros archivos, informar al usuario y pedir que limpie el directorio primero.

> **IMPORTANTE**: Antes de ejecutar el clone y los commits, confirmar con el usuario
> mostrando lo que se va a hacer.

### Campos del body

| Campo | Tipo | Requerido | Descripcion |
|-------|------|-----------|-------------|
| `name` | string | Si | Nombre unico dentro del namespace |
| `namespace_id` | number | Si | ID del namespace donde crear la app |
| `template_id` | number | Si | ID del template de tecnologia |
| `repository_url` | string | Si | URL del repositorio (nuevo o existente) |
| `metadata` | object | Depende de org | Campos organizacionales (business unit, PCI, etc.) |

### Body tipico

```json
{
  "name": "My New Api",
  "namespace_id": 463208973,
  "template_id": 1220542475,
  "repository_url": "https://github.com/kwik-e-mart/nullplatform-demos-my-new-api",
  "metadata": {
    "application": {
      "businessUnit": "Payments",
      "pci": "No",
      "slo": "High",
      "applicationOwner": "Jane Smith"
    }
  }
}
```

### Respuesta

- `id`: ID numerico de la aplicacion
- `name`: Nombre de la aplicacion
- `status`: `creating` → `active`
- `slug`: Slug generado del nombre
- `namespace_id`: ID del namespace
- `template_id`: ID del template usado
- `repository_url`: URL del repositorio
- `nrn`: NRN completo (organization=X:account=Y:namespace=Z:application=W)
- `metadata`: Metadata organizacional

### Consultas previas (via /np-api)

- Accounts: `np-api fetch-api "/account?organization_id=<org_id>&status=active"`
- Namespaces: `np-api fetch-api "/namespace?account_id=<account_id>&status=active&limit=50"`
- Templates: `np-api fetch-api "/template?limit=200&target_nrn=<nrn>&global_templates=true"`
- Metadata specification: `np-api fetch-api "/metadata/metadata_specification?entity=application&nrn=<namespace_nrn_url_encoded>&merge=true"`
- Verificar resultado: `np-api fetch-api "/application/<new_app_id>"`

### Notas

- A diferencia de servicios y links, la creacion de aplicacion es un **solo POST** (no requiere action separada)
- La aplicacion queda en estado `creating` brevemente mientras se crea el repositorio en GitHub
- El `slug` se genera automaticamente del `name` (lowercase, espacios → guiones)
- El `template_id` determina que archivos se copian al nuevo repositorio
- Los campos de `metadata` son **organizacion-especificos** y pueden variar entre orgs
- Si no se envia `metadata` y la org la requiere, la creacion puede fallar o quedar incompleta
- `auto_deploy_on_creation` defaultea a `false`
- Para monorepos: usar `is_mono_repo: true` y `repository_app_path: "<path>"`

### Ejemplo

```bash
action-api.sh exec-api --method POST --data '{
  "name": "Test App Discovery",
  "namespace_id": 463208973,
  "template_id": 1220542475,
  "repository_url": "https://github.com/kwik-e-mart/nullplatform-demos-test-app-discovery",
  "metadata": {
    "application": {
      "businessUnit": "Money Market",
      "pci": "No",
      "slo": "High",
      "applicationOwner": "David Brown"
    }
  }
}' "/application"
```
