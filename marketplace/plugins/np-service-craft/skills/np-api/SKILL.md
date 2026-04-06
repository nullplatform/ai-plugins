---
name: np-api
description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/*.sh)
---

# np-api

Skill para explorar y consultar la API de Nullplatform.

## Comando: $ARGUMENTS

## Comandos Disponibles

| Comando | Proposito |
|---------|-----------|
| `/np-api` | Mapa de entidades y relaciones |
| `/np-api check-auth` | Verificar autenticacion con Nullplatform |
| `/np-api search-endpoint <term>` | Buscar endpoints por termino |
| `/np-api describe-endpoint <endpoint>` | Documentacion completa del endpoint |
| `/np-api fetch-api <url>` | Ejecutar request a la API |

---

## Si $ARGUMENTS es "check-auth" → Verificar Autenticacion

Ejecutar el script de verificacion:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh
```

Mostrar el resultado al usuario. Si falla, indicar las opciones:

**RECOMENDADO: NP_API_KEY (no expira, token cacheado en ~/.claude/)**

```bash
export NP_API_KEY='tu-api-key'
```

1. Ir a Nullplatform UI -> Settings -> API Keys
2. Crear nueva API Key para la organización
3. Agregar `export NP_API_KEY='...'` a `~/.zshrc` o `~/.bashrc`

**Alternativa: NP_TOKEN (expira en ~24h)**

```bash
export NP_TOKEN='eyJ...'
```

1. Ir a la UI de Nullplatform
2. Click en tu perfil (esquina superior derecha)
3. Click en "Copy personal access token"

---

## Si $ARGUMENTS comienza con "search-endpoint" → Buscar Endpoints

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh search-endpoint <term>
```

Muestra lista de endpoints que contienen el termino buscado.

---

## Si $ARGUMENTS comienza con "describe-endpoint" → Documentacion de Endpoint

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh describe-endpoint <endpoint>
```

Muestra documentacion completa del endpoint: parametros, respuesta, navegacion, ejemplos.

---

## Si $ARGUMENTS comienza con "fetch-api" → Request a la API

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api <url>
```

Retorna el JSON de la respuesta de la API.

---

## Si $ARGUMENTS comienza con "resend-notification" → Redirigir

> **Movido**: El comando resend-notification se movio a `/np-service-craft resend-notification <id> [channel_id]`
> porque requiere la API key admin (de `secrets.tfvars`), no la key de troubleshooting de np-api.

Informar al usuario que use `/np-service-craft resend-notification <id> [channel_id]` en su lugar.

Para **buscar** notificaciones y **ver resultados** (lectura, no requiere admin):

```bash
# Buscar notificaciones
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api "/notification?nrn=<nrn_encoded>&source=service"

# Ver resultado de entrega por canal
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh fetch-api "/notification/<id>/result"
```

---

## Si $ARGUMENTS esta vacio → Mostrar Mapa de Entidades

Ejecutar:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-api.sh
```

Muestra el mapa de entidades y jerarquia de Nullplatform.

---

## Flujo Recomendado

Para explorar la API de forma segura:

1. **Primero**: `/np-api` para ver el mapa de entidades
2. **Segundo**: `/np-api search-endpoint <term>` para encontrar el endpoint
3. **Tercero**: `/np-api describe-endpoint <endpoint>` para ver la documentacion
4. **Cuarto**: `/np-api fetch-api <url>` para ejecutar el request

### Checklist antes de fetch-api

- [ ] ¿Hice `search-endpoint` para confirmar que el endpoint existe?
- [ ] ¿Hice `describe-endpoint` para conocer los parametros validos?
- [ ] ¿Estoy usando parametros documentados, no inferidos?

---

## Anti-patrones (NO hacer)

| Mal | Por que | Bien |
|-----|---------|------|
| `fetch-api "/scope/123"` directo | Asumis que el endpoint existe | Primero `search-endpoint scope` |
| `fetch-api "/scope?application_id=X"` | Asumis query params | Primero `describe-endpoint /scope` |
| Inferir endpoints de respuestas JSON | La API puede no seguir convenciones REST | Siempre verificar con `search-endpoint` o `describe-endpoint` |

---

## Scripts Adicionales

| Script | Proposito |
|--------|-----------|
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh <url>` | Fetch directo de API |
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/deploy-agent-dump.sh <deployment_id>` | Dump K8s de deployment |
| `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/scope-agent-dump.sh <scope_id>` | Dump K8s de scope |

---

## Documentar Nuevos Endpoints

Cuando descubras un endpoint nuevo o el usuario pida documentarlo:

1. Editar el archivo `.md` correspondiente en `docs/` (o crear uno nuevo)
2. Agregar una seccion con este formato:

```markdown
## @endpoint /ruta/del/endpoint

Descripcion breve de que hace.

### Parametros
- `param1` (path|query, required|optional): Descripcion

### Respuesta
- `campo1`: Descripcion
- `campo2`: Descripcion

### Navegacion
- **→ entidad**: `campo` → `/otro/endpoint`
- **← desde**: `/endpoint?filtro={id}`

### Ejemplo
\```bash
np-api fetch-api "/ruta/del/endpoint/123"
\```

### Notas
- Comportamientos no obvios
- Errores comunes
```

El CLI detecta `## @endpoint` como marcador y extrae la documentacion automaticamente.

---

## Generar Reporte de Sesion

Cuando el usuario pida "genera un reporte de np-api" o "np-api report":

### Paso 1: Extraer actividad de la conversacion

Revisar toda la conversacion y extraer:

- Prompts del usuario (resumidos)
- Llamadas a `/np-api` (comando completo)
- Resultados de cada llamada (exito/fallo)
- Decisiones tomadas basadas en los resultados

### Paso 2: Generar tabla de actividad

| Segs | Accion | Contenido | Exitosa |
|-----|--------|-----------|---------|
| 0 | prompt | Resumen del prompt del usuario | - |
| N | np-api | Comando ejecutado | ✓ / ✗ |

### Paso 3: Analizar errores

Para cada llamada fallida:

- **Comando**: Que se ejecuto
- **Resultado**: Que devolvio
- **Causa**: Por que fallo (error de usuario vs error de documentacion)
- **Fix sugerido**: Si es error de documentacion, indicar archivo, linea, y cambio especifico

### Paso 4: Generar sugerencias de mejora

Lista de cambios a docs/*.md con formato:

- [ ] archivo.md:linea - Descripcion del cambio
