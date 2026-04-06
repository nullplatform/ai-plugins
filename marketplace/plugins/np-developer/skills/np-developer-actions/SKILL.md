---
name: np-developer-actions
description: This skill should be used when the user asks to "create a scope", "deploy an application", "manage parameters", "create an app", "trigger a build", "create a release", "link a service", or needs to perform day-to-day developer operations on nullplatform entities via the API.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/*.sh)
---

# np-developer-actions

Operaciones de developer en Nullplatform: crear scopes, desplegar, gestionar parametros.
Cada operacion es un flujo multi-paso con discovery, confirmacion y verificacion.

## Comando: $ARGUMENTS

## Cuando usar este skill

Usar este skill cuando el usuario quiera:
- **Crear una aplicacion** (nueva app con template y repositorio en un namespace)
- **Crear un servicio** (provisionar infraestructura: database, cola, cache, etc.)
- **Crear un scope** (ambiente/target de deployment) en una aplicacion
- **Desplegar** (crear o actualizar un deployment en un scope)
- **Crear o modificar parametros** (variables de entorno) de una aplicacion o scope
- **Linkear un servicio** existente y disponible a una aplicacion
- **Ejecutar una custom action** sobre un servicio o link (operaciones ad-hoc definidas por el platform team)

Palabras clave: crear aplicacion, nueva aplicacion, nueva app, create application,
crear servicio, nuevo servicio, provisionar, crear base de datos, crear cola,
crear cache, crear sqs, crear redis, crear postgres, crear dynamodb,
crear scope, nuevo scope, agregar ambiente, deploy, desplegar, deployment,
crear parametro, agregar variable, modificar parametro, cambiar variable de entorno,
environment variable, configurar scope, crear environment, linkear servicio, link service,
conectar servicio, vincular servicio, linkear base de datos, linkear cola, linkear mcp,
ejecutar accion, run action, correr accion, custom action, accion custom, operar servicio.

## Comandos Disponibles

| Comando | Proposito |
|---------|-----------|
| `/np-developer-actions` | Mapa de operaciones disponibles |
| `/np-developer-actions check-auth` | Verificar autenticacion |
| `/np-developer-actions search-action <term>` | Buscar acciones por termino |
| `/np-developer-actions describe-action <action>` | Documentacion completa de la accion |
| `/np-developer-actions exec-api --method M --data '{...}' "/endpoint"` | Ejecutar operacion |

## Operaciones documentadas

| Operacion | Doc | Descripcion |
|-----------|-----|-------------|
| Crear aplicacion | `docs/applications.md` | Crear nueva aplicacion con template y repositorio en un namespace |
| Crear servicio | `docs/services.md` | Provisionar nuevo servicio de infraestructura (DB, cola, cache, etc.) |
| Crear scope | `docs/scopes.md` | Crear un scope con discovery de tipos, dimensions y capabilities |
| Desplegar | `docs/deployments.md` | Crear deployment eligiendo build/release y scope target |
| Gestionar parametros | `docs/parameters.md` | Crear, modificar y eliminar variables de entorno |
| Linkear servicio | `docs/service-links.md` | Linkear un servicio existente y disponible a una aplicacion |
| Ejecutar custom action | `docs/custom-actions.md` | Ejecutar acciones custom sobre servicios o links |

**IMPORTANTE**: Cada operacion tiene su propio flujo documentado en `docs/`. Leer la doc
correspondiente ANTES de ejecutar. Los flujos incluyen consultas previas obligatorias via
`/np-api fetch-api`.

---

## REGLA CRITICA: Confirmacion antes de CADA operacion

**Antes de ejecutar cualquier `exec-api`**, preguntar al usuario explicando:
1. **QUE** se va a hacer (metodo + endpoint + body completo)
2. **POR QUE** se hace (el motivo del cambio)

Ejemplo: "Voy a ejecutar `POST /scope` con body `{...}` para crear un scope 'staging' en la
aplicacion <app_id> con dimension environment=staging. Procedo?"

## REGLA IMPORTANTE: Lectura via np-api

**Este skill NO hace consultas de lectura.**
Para obtener IDs, verificar estado, o consultar entidades, usar siempre `/np-api fetch-api "<endpoint>"`.

---

## Si $ARGUMENTS esta vacio → Mostrar Operaciones Disponibles

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/action-api.sh
```

Muestra el mapa de operaciones disponibles.

---

## Si $ARGUMENTS es "check-auth" → Verificar Autenticacion

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/action-api.sh check-auth
```

Mostrar el resultado al usuario. Si falla, indicar las opciones:

**RECOMENDADO: NP_API_KEY con permisos de escritura (no expira, token cacheado en ~/.claude/)**

```bash
export NP_API_KEY='tu-api-key'
```

1. Ir a Nullplatform UI -> Settings -> API Keys
2. Crear nueva API Key con permisos de escritura para la organizacion
3. Agregar `export NP_API_KEY='...'` a `~/.zshrc` o `~/.bashrc`

**Alternativa: NP_TOKEN (expira en ~24h)**

```bash
export NP_TOKEN='eyJ...'
```

1. Ir a la UI de Nullplatform
2. Click en tu perfil (esquina superior derecha)
3. Click en "Copy personal access token"

---

## Si $ARGUMENTS comienza con "search-action" → Buscar Acciones

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/action-api.sh search-action <term>
```

Muestra lista de acciones que contienen el termino buscado.

---

## Si $ARGUMENTS comienza con "describe-action" → Documentacion de Accion

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/action-api.sh describe-action <action>
```

Muestra documentacion completa: campos requeridos, body tipico, consultas previas, ejemplo.

---

## Si $ARGUMENTS comienza con "exec-api" → Ejecutar Operacion

**ANTES de ejecutar, SIEMPRE:**

1. Haber leido la doc del flujo correspondiente en `docs/`
2. Haber ejecutado las consultas previas via `/np-api fetch-api`
3. Haber mostrado al usuario QUE + POR QUE y recibido confirmacion

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-developer-actions/scripts/action-api.sh exec-api --method <METHOD> --data '<json>' "<endpoint>"
```

Retorna el JSON de la respuesta de la API.

---

## Si $ARGUMENTS describe una operacion directa → Ejecutar el flujo documentado

Cuando el usuario invoca el skill con una descripcion como:
- "crear scope en aplicacion 123"
- "desplegar en scope 456"
- "crear parametro DATABASE_URL"

**Ir directamente a la doc correspondiente** en `docs/` y seguir el flujo paso a paso.
NO es necesario pasar por search-action/describe-action si la operacion ya esta documentada.

---

## Flujo general de una operacion

1. **Discovery**: Consultar la API para obtener IDs, opciones disponibles, schemas
2. **Preguntar**: Usar `AskUserQuestion` para que el usuario elija opciones
3. **Confirmar**: Mostrar el body completo y pedir confirmacion
4. **Ejecutar**: `exec-api` con el body confirmado
5. **Verificar**: Consultar el estado post-ejecucion y diagnosticar si fallo

---

## Anti-patrones (NO hacer)

| Mal | Por que | Bien |
|-----|---------|------|
| Ejecutar sin discovery | No conoces las opciones disponibles | Consultar API primero |
| Asumir IDs o valores | Pueden ser incorrectos | Consultar con `/np-api fetch-api` |
| Ejecutar sin confirmar | El usuario debe aprobar cada escritura | Siempre confirmar antes |
| Usar exec-api para leer | Este skill es solo escritura | Usar `/np-api fetch-api` para lectura |
| No verificar post-ejecucion | La operacion puede fallar silenciosamente | Siempre verificar status |

---

## Documentar Nuevas Acciones

Cuando descubras una accion nueva o el usuario pida documentarla:

1. Editar el archivo `.md` correspondiente en `docs/` (o crear uno nuevo)
2. Agregar una seccion con este formato:

```markdown
## @action METHOD /ruta/del/endpoint

Descripcion breve de que hace.

### Flujo obligatorio

Pasos de discovery, preguntas al usuario, ejecucion y verificacion.

### Campos requeridos
- `campo1` (tipo): Descripcion

### Body tipico
{...}

### Consultas previas (via /np-api)
- Descripcion: `np-api fetch-api "/endpoint"`

### Verificar resultado
- Como verificar que la operacion fue exitosa
- Errores comunes y como resolverlos

### Ejemplo
action-api.sh exec-api --method METHOD --data '{...}' "/endpoint"
```

El CLI detecta `## @action` como marcador y extrae la documentacion automaticamente.
