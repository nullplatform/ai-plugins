---
name: np-organization-create
description: This skill should be used when the user asks to "create an organization", "new nullplatform org", "onboard a new client", "initialize organization", or needs to create a new nullplatform organization via the onboarding API. This is an irreversible operation.
---

# Nullplatform Organization Create

Crea una nueva organizacion de Nullplatform via la onboarding API.

## Cuando Usar

- Creando una organizacion nueva de Nullplatform desde cero
- Primer paso antes de cualquier configuracion de infraestructura

## REGLAS DE SEGURIDAD

**Crear una organizacion es una accion IRREVERSIBLE.** Se debe proceder con extrema cautela.

1. **SIEMPRE** mostrar el request completo al usuario antes de ejecutar
2. **SIEMPRE** pedir confirmacion explicita antes de ejecutar el POST
3. **SIEMPRE** preguntar si el nombre de la organizacion fue validado con los stakeholders
4. **SIEMPRE** verificar cada email de owner con el usuario antes de enviar (se envian invitaciones reales)
5. **NUNCA** ejecutar el POST sin todas las confirmaciones anteriores

## Prerequisitos

1. Archivo `organization-create-api.key` en la raiz del proyecto
   - Contiene una API Key con grant `organization:create` en `organization=0` (root)
   - Este archivo es **altamente sensible** y debe estar en `.gitignore`
   - Para obtenerla: contactar al equipo de Nullplatform
2. Verificar que `organization-create-api.key` esta en `.gitignore`
3. Conectividad a la VPN (requerida para `*.nullapps.io`)

## Endpoint

| Campo | Valor |
|-------|-------|
| URL | `https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization` |
| Metodo | POST |
| Auth | Bearer token generado desde `organization-create-api.key` |
| Content-Type | application/json |

## Body Schema

```json
{
  "organization_name": "nombre-de-la-org",
  "account_name": "nombre-del-account",
  "owners": [
    {
      "email": "user@example.com",
      "name": "Nombre",
      "last_name": "Apellido"
    }
  ]
}
```

**IMPORTANTE**: Los campos de owners usan `snake_case` (`last_name`, NO `lastName`).

## Workflow

### Paso 0: Verificar si la organizacion ya existe

Antes de iniciar el flujo de creacion, verificar si `organization.properties` ya contiene un `organization_id`.

Si existe:
1. Preguntar al usuario si la org ya fue creada o si necesita crear una nueva
2. Si ya fue creada → **saltear directamente al siguiente paso** (`/np-setup-orchestrator`). No ejecutar verificacion post-creacion ni ningun otro paso de este skill.
3. Si necesita crear una nueva → continuar con el Paso 1

### Paso 1: Verificar prerequisitos

```bash
# Verificar que organization-create-api.key existe
ls organization-create-api.key

# Verificar que esta en .gitignore
grep -q "organization-create-api.key" .gitignore && echo "OK" || echo "FALTA en .gitignore"

# Verificar conectividad a la VPN (OBLIGATORIO antes de cualquier request)
curl -s --max-time 5 -o /dev/null -w "%{http_code}" "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/health" || true
```

**Si el health check falla o no responde** → DETENERSE e indicar:

> No hay conectividad con `*.nullapps.io`. Conectate a la VPN de Nullplatform antes de continuar.
>
> Una vez conectado, volve a ejecutar `/np-organization-create`.

**No continuar con los pasos siguientes si la VPN no esta conectada.**

Si `organization-create-api.key` no existe, indicar:

> Necesitas una API Key con grant `organization:create` en `organization=0`.
>
> **Como obtenerla:**
> 1. Contactar al equipo de Nullplatform
> 2. Solicitar una API Key root con grant: `organization:create` en `organization=0`
> 3. Guardar: `echo 'TU_API_KEY' > organization-create-api.key`

Si no esta en `.gitignore`, agregarlo antes de continuar.

### Paso 2: Recopilar datos

Preguntar al usuario usando AskUserQuestion:

1. **Nombre de la organizacion** (sera el identificador permanente)
2. **Nombre del primer account** (ej: "playground", "production")
3. **Owners** (email, nombre y apellido de cada uno)

### Paso 3: Validacion con stakeholders

**OBLIGATORIO** - Usar AskUserQuestion:

> El nombre de la organizacion sera `{organization_name}`.
> Este nombre es PERMANENTE y no se puede cambiar despues.
>
> Fue validado este nombre con los stakeholders?

Opciones:
- **Si, esta validado** → Continuar
- **No, necesito validarlo primero** → Pausar y esperar

### Paso 4: Verificar owners

Mostrar tabla con todos los owners y pedir confirmacion:

```markdown
## Owners que recibiran invitacion

| # | Email | Nombre | Apellido |
|---|-------|--------|----------|
| 1 | user@example.com | Nombre | Apellido |
| ... | ... | ... | ... |

ATENCION: Se enviaran invitaciones reales a estos emails.
```

Usar AskUserQuestion:

> Los emails y datos de los owners son correctos?

### Paso 5: Mostrar request y confirmar

Mostrar el request completo:

```markdown
## Request a ejecutar

**POST** `https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization`

**Body:**
{json completo formateado}

**Auth:** Token generado desde organization-create-api.key
```

Usar AskUserQuestion para confirmacion final:

> Confirmas la creacion de la organizacion `{organization_name}`?
> Esta accion es IRREVERSIBLE.

Opciones:
- **Si, crear la organizacion** → Ejecutar
- **No, cancelar** → Abortar

### Paso 6: Ejecutar

Usar `/np-api fetch-api` con `--key-file`:

```bash
/np-api fetch-api \
  --key-file organization-create-api.key \
  --method POST \
  --data '{"organization_name":"...","account_name":"...","owners":[...]}' \
  "https://onboarding-onboarding-api-production-lmhky.prod.nullapps.io/organization"
```

### Paso 7: Procesar resultado

**Si es exitoso:**

1. Extraer el `id` de la respuesta (campo `id`, no `organization_id`)
2. Crear `organization.properties`:
   ```bash
   echo "organization_id={id}" > organization.properties
   ```
3. Mostrar resumen:
   ```markdown
   ## Organizacion creada

   | Campo | Valor |
   |-------|-------|
   | Organization ID | {id} |
   | Nombre | {organization_name} |
   | Account | {account_name} |
   | Owners invitados | {count} |

   Archivo `organization.properties` creado.

   **Siguiente paso:** Verificacion post-creacion (Paso 8).
   ```

### Paso 8: Verificacion post-creacion

**NOTA:** Este paso se ejecuta UNICAMENTE despues de crear una organizacion nueva (Pasos 6-7). Si la org ya existia y se salteo la creacion (Paso 0), NO ejecutar esta verificacion.

**IMPORTANTE:** La API key root (`organization-create-api.key` con grant `organization:create` en `organization=0`) **solo funciona contra la onboarding API** (`*.nullapps.io`). La API publica (`api.nullplatform.com`) rechaza tokens root con 403. Para verificar la org recien creada se necesita un token de la nueva organizacion.

#### 8.1 Crear API key de la nueva organizacion

La API key root (`organization-create-api.key`) **solo funciona contra la onboarding API** (`*.nullapps.io`). Para operar con la API publica (`api.nullplatform.com`) se necesita una API key de la nueva organizacion.

Guiar al usuario:

```markdown
## Crear API key para la nueva organizacion

**Pasos:**
1. Un owner invitado acepta la invitacion por email e inicia sesion en https://app.nullplatform.com
2. Ir a **Platform Settings → API Keys → Create API Key**
3. Configurar:
   - **Name:** Un nombre descriptivo (ej: `setup-key`)
   - **Scope:** La organizacion recien creada
   - **Roles:** Seleccionar **todos** estos roles:
     - `Admin` — Manage all the resources
     - `Agent` — Role to be used by nullplatform agents
     - `Developer` — Create builds, releases, scopes, start deployments
     - `Ops` — Modify environments and infrastructure-related resources
     - `SecOps` — Modify security ops related resources
     - `Secrets Reader` — Read secret parameters
4. Copiar la API key generada (solo se muestra una vez)
5. Guardarla en un archivo en la raiz del proyecto:
   ```bash
   echo '<API_KEY>' > np-api.key
   ```
6. Verificar que `np-api.key` esta en `.gitignore`:
   ```bash
   grep -q "np-api.key" .gitignore && echo "OK" || echo "np-api.key" >> .gitignore
   ```
```

Usar AskUserQuestion:

> Crea una API key con los roles listados arriba (Admin, Agent, Developer, Ops, SecOps, Secrets Reader) en la nueva organizacion.
> Cuando la tengas guardada en `np-api.key`, avisame para continuar con la verificacion.

Opciones:
- **Ya tengo la API key en np-api.key** → Continuar con verificacion
- **Saltear verificacion** → Ir directamente al siguiente paso

**IMPORTANTE:** Esta API key se reutiliza en los pasos siguientes del setup (`/np-setup-orchestrator`, infrastructure wizard, bindings, etc.). Asignar solo `Admin` no alcanza — los skills posteriores validan que la key tenga los roles especificos listados arriba.

#### Roles disponibles (referencia)

| Role | Descripcion | Requerido para setup |
|------|-------------|---------------------|
| Admin | Manage all the resources | Si |
| Agent | Role to be used by nullplatform agents | Si |
| CI | Machine user that performs continuous integration | No |
| Developer | Create builds, releases, scopes, start deployments | Si |
| Member | Read access to resource information | No |
| Ops | Modify environments and infrastructure-related resources | Si |
| SecOps | Modify security ops related resources | Si |
| Secrets Reader | Read secret parameters | Si |
| Troubleshooting | Inspect and gather information to diagnose issues |

Para el setup inicial se recomienda **Admin**. Para uso posterior, crear keys con el minimo de permisos necesarios.

#### 8.2 Verificar que la organizacion existe

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/organization/{id}"
```

Verificar que la respuesta contiene:
- `id` coincide con el retornado en la creacion
- `name` coincide con `organization_name`
- `status` es `active`

#### 8.3 Verificar que el account se creo (solo si se paso `account_name`)

**Este paso se ejecuta UNICAMENTE si el usuario paso `account_name` en el body de creacion.**
Si no se paso `account_name`, saltear este paso.

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/account?organization_id={id}"
```

Verificar que la respuesta contiene al menos un account con el nombre esperado.

#### 8.4 Verificar que los usuarios/owners se crearon

```bash
/np-api fetch-api \
  --key-file np-api.key \
  "/user?organization_id={id}"
```

Comparar los emails retornados con los owners enviados en el body de creacion.

#### 8.5 Mostrar resultado de verificacion

```markdown
## Verificacion post-creacion

| Check | Estado | Detalle |
|-------|--------|---------|
| Organizacion existe | OK/ERROR | ID: {id}, Name: {name}, Status: {status} |
| Account creado | OK/ERROR/N/A | ID: {id}, Name: {name} |
| Usuarios creados | OK/ERROR | {count}/{total} owners encontrados |
```

Si todo esta OK:

```markdown
Organizacion verificada correctamente.

**Siguiente paso:** `/np-setup-orchestrator` para continuar con la configuracion.
```

Si algo falla, indicar que contacte al equipo de Nullplatform con el `id` de la organizacion.

**Si falla:**

Mostrar el error y posibles causas:

| Error | Causa probable |
|-------|---------------|
| 401 Invalid token | El personal access token expiro o es invalido |
| 403 Forbidden | El token no pertenece a la organizacion recien creada |
| 400 Schema error | Campos mal formateados (verificar snake_case) |
| 404 Not found | La organizacion aun no termino de provisionarse, esperar unos minutos |

## Troubleshooting

### Creacion de la organizacion

#### "Invalid token provided"

- Verificar que `organization-create-api.key` contiene una API key valida
- Verificar que la API key tiene grant `organization:create` en `organization=0`

#### "Forbidden" / 403 en el POST de creacion

- La API key no es de nivel root
- Contactar al equipo de Nullplatform para verificar permisos

#### Connection refused / DNS error

- Verificar que estas conectado a la VPN
- Los endpoints `*.nullapps.io` requieren VPN

#### "must have required property 'last_name'"

- El body usa `snake_case`: `last_name`, NO `lastName`

### Verificacion post-creacion

#### 403 en verificacion (api.nullplatform.com)

- **Causa:** Se esta usando la API key root (`organization-create-api.key`) contra `api.nullplatform.com`. Esta key solo funciona contra la onboarding API (`*.nullapps.io`).
- **Solucion:** Crear una API key con role Admin en la nueva organizacion (ver Paso 8.1) y guardarla en `np-api.key`.

#### Owner no recibio invitacion

- Verificar que el email es correcto
- Revisar carpeta de spam
- Contactar al equipo de Nullplatform si el email no llega despues de 15 minutos

#### API key de la nueva org da 401

- Verificar que `np-api.key` contiene la key correcta (no la root)
- Verificar que el scope de la key es la organizacion nueva (no `organization=0`)

## Siguiente Paso

Una vez creada la organizacion, continuar con la configuracion completa:

**Decile a Claude**: "Configuremos la organizacion"

O invoca directamente: `/np-setup-orchestrator`
