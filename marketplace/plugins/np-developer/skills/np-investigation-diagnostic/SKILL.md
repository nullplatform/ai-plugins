---
name: nullplatform-investigation-diagnostic
description: Use when the user asks to investigate, diagnose, look at, check, or troubleshoot any nullplatform entity (deployments, scopes, services, applications, builds, releases). Also use when the user mentions problems, errors, failures, or unhealthy states in nullplatform.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/agent-kubectl.sh)
---

# Nullplatform Investigation & Diagnostic

Skill para investigar y diagnosticar problemas en nullplatform.

## Cuándo Usar

- Investigar entidades con problemas (status: failed, unhealthy, etc.)
- Entender qué pasó y quién hizo qué
- Generar reportes de auditoría completos
- Diagnóstico de deployments, scopes, services, applications

## Skills Requeridos

Este skill orquesta el uso de dos skills especializados:

| Skill | Propósito | Invocación |
|-------|-----------|------------|
| `np-api` | Estado actual de entidades | `Skill tool: np-api` |
| `np-audits-read` | Historial de cambios (audit trail) | `Skill tool: np-audits-read` |

### Regla Crítica

**SIEMPRE invocar AMBOS skills al inicio de una investigación.**

No uses uno sin el otro. La API da el estado actual, la auditoría da el historial. Ambos son necesarios para un diagnóstico completo.

## Reglas de Seguridad Importantes

**Este skill es SOLO LECTURA** - diagnóstico, no fixes.

| Permitido | Prohibido |
|-----------|-----------|
| Consultar estado de entidades | Modificar entidades |
| Obtener historial de cambios | Crear/eliminar recursos |
| Generar reportes | Ejecutar acciones |
| Analizar datos | Cambiar configuraciones |

## Proceso de Investigación

```
1. INTAKE → 2. CONTEXTO → 3. ESTADO ACTUAL → 4. HISTORIAL → (4.5 K8S DEEP DIVE) → 5. ANÁLISIS → 6. REPORTE
```

---

### Fase 1: Intake

**Objetivo**: Entender qué se está investigando.

**Recopilar del usuario**:

| Dato | Pregunta |
|------|----------|
| ID de entidad | ¿Cuál es el ID? |
| Tipo de entidad | ¿Es un deployment, scope, service, application? |
| Síntomas | ¿Qué error o problema observas? |
| Timeline | ¿Cuándo empezó? ¿Es intermitente o constante? |
| Impacto | ¿Qué está afectando? ¿Producción? |

**Si falta información**: Preguntar antes de continuar.

---

### Fase 2: Contexto Organizacional

**Objetivo**: Entender dónde vive la entidad.

**Usar**: `np-api`

**Obtener**:
- Jerarquía: organization → account → namespace → application
- Entidades relacionadas (scopes, services, deployments)
- Metadata organizacional (portfolio, tech manager, etc.)

**Preguntas a responder**:
- ¿A qué aplicación pertenece?
- ¿En qué namespace/account/organización está?
- ¿Qué otras entidades están relacionadas?

---

### Fase 3: Estado Actual

**Objetivo**: Saber cómo está la entidad AHORA.

**Usar**: `np-api`

**Obtener**:
- Estado actual (status)
- Configuración y atributos
- Mensajes de error
- Entidades relacionadas y su estado

**Preguntas a responder por tipo de entidad**:

#### Service
- ¿Cuál es el status?
- ¿Qué actions se ejecutaron?
- ¿Qué dice la especificación?
- ¿Hay discrepancias entre parámetros y resultados?

#### Deployment
- ¿En qué fase está/falló?
- ¿Qué mensajes hay?
- ¿Cuál es el scope y application?
- ¿Qué release/build se desplegó?

#### Scope
- ¿Está activo o failed?
- ¿Tiene deployments recientes?
- ¿Cuáles son sus capabilities?
- ¿Qué services están linkeados?

#### Application
- ¿Cuántos scopes tiene?
- ¿Hay builds/releases recientes?
- ¿Cuál es el estado general?

---

### Fase 4: Historial (Audit Trail)

**Objetivo**: Saber QUÉ PASÓ y QUIÉN lo hizo.

**Usar**: `np-audits-read`

**Obtener**:
- Todos los eventos de la entidad
- Quién hizo qué y cuándo
- Operaciones fallidas (errores HTTP)
- Payloads de request/response

**Preguntas a responder**:
- ¿Quién creó/modificó la entidad?
- ¿Hubo intentos fallidos?
- ¿Qué parámetros se enviaron?
- ¿Hubo intervenciones manuales?

---

### Fase 4.5: K8s Deep Dive (opcional)

**Objetivo**: Mirar el estado real del cluster cuando la API y los audits no alcanzan.

**Cuándo entrar en esta fase** (Claude debe decidir proactivamente, sin esperar al usuario):

- El deployment está `success` en nullplatform pero el usuario reporta el servicio caído.
- Mensajes de acción o audit mencionan `CrashLoopBackOff`, `OOMKilled`, `ImagePullBackOff`, timeouts, o problemas de ingress/route.
- El audit muestra un apply exitoso pero el usuario ve 404/5xx en producción (clase de problema Istio-vs-ALB).
- El usuario pide explícitamente estado de K8s o logs.

**Herramienta**: `/np-api` + helper `agent-kubectl.sh`.

**Regla de seguridad**: sigue siendo solo lectura. El script server-side ya bloquea verbos que no sean `get`/`logs` y flags peligrosos — no intentes bypass.

---

#### Paso A: Resolver el selector del agente

Dado el scope/service/application que estás investigando, encontrar qué selector usa su agente:

1. **Obtener el NRN** de la entidad (ya lo tenés de Fase 2):
   ```
   /np-api fetch-api "/scope/{id}"
   ```
   → leer `nrn`.

2. **Listar los channels tipo agent para ese NRN**:
   ```
   /np-api fetch-api "/notification/channel?nrn={nrn}&showDescendants=true"
   ```
   → filtrar `results[] | select(.type == "agent")`.

3. **Para cada agent channel, obtener el detalle**:
   ```
   /np-api fetch-api "/notification/channel/{channel_id}"
   ```
   → leer `configuration.agent.channel_selectors` (ej: `{cluster: "runtime"}`, `{service: "sync-ad"}`, `{environment: "javi-k8s"}`).

4. **Elegir el selector**:
   - Si hay un único agent channel, usá su `channel_selectors`.
   - Si hay varios, preferí el que coincide con el tipo de entidad que estás debuggeando (runtime → `cluster=runtime`, service-provisioned → `service=<slug>`).
   - Si hay ambigüedad real, preguntá al usuario.

---

#### Paso B: Ejecutar queries útiles

Pasá el selector al helper:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/agent-kubectl.sh <verb> [--nrn <nrn>] [--selector key=value]... -- <kubectl-args>
```

La respuesta es JSON; el output del kubectl está en `.executions[].results.stdOut`. Leelo, no lo transformes.

**Queries útiles (no exhaustivo)**:

| Síntoma | Comando sugerido |
|---------|------------------|
| Estado de pods de un scope | `get pods -n <ns> -l scope_id=<id>` |
| Eventos recientes del cluster | `get events -n <ns> --sort-by=.lastTimestamp` |
| Problema de routing (404 Istio-vs-ALB) | `get httproute -A -l scope_id=<id>` y `get ingress -A -l scope_id=<id>` |
| Estado de un deployment específico | `get deployment -n <ns> <deployment-name> -o yaml` |
| CrashLoopBackOff | `logs <pod> --tail 200 --previous` |
| Multi-container crash | `logs <pod> -c <container> --tail 200 --previous` |
| Filtrar por label | `logs -l app=<label> --tail 100 -c <container>` |

**Aclaraciones de argumentos**:
- El script server-side default a `$K8S_NAMESPACE` si no pasás `-n`, pero para investigaciones es más claro pasar `-n` explícito.
- Para `logs`: `-f`/`--follow` están bloqueados. Usá `--tail`, `--since`, `--previous`, `-c` para acotar.
- Para `get` sobre `secret`: el output se fuerza a JSON y se eliminan `.data` / `.stringData` automáticamente. Está bien consultarlo.

---

#### Paso C: Alimentar los resultados a Fase 5

Los hallazgos de K8s (pod names, status, reason, eventos, líneas de log) entran al análisis de Fase 5 junto con los datos de API/audit. Documentá en el timeline:

| Fuente | Tipo de dato |
|--------|--------------|
| API | Estado declarativo de la entidad |
| Audit | Historial de cambios |
| K8s (esta fase) | Estado real del runtime |

---

### Fase 5: Análisis

**Objetivo**: Correlacionar toda la información.

**Actividades**:

1. **Construir timeline**: Ordenar todos los eventos cronológicamente
2. **Identificar discrepancias**: ¿Hay datos inconsistentes?
3. **Buscar causa raíz**: ¿Qué cambió antes del problema?
4. **Mapear usuarios**: ¿Quiénes estuvieron involucrados?

**Patrones comunes a buscar**:

| Patrón | Indicadores |
|--------|-------------|
| Configuración incorrecta | Parámetros enviados vs esperados |
| Timeout | Mucho tiempo entre creación y fallo |
| Permisos | Errores 403, intentos rechazados |
| Intervención manual | PATCH para marcar como failed |
| Inconsistencia de datos | Diferentes valores en diferentes fuentes |

---

### Fase 6: Reporte

**Objetivo**: Documentar los hallazgos.

**Usar el template de reporte** (ver abajo).

---

## Template de Reporte

```markdown
# {Tipo Entidad} {ID}
## {Resumen del problema}

| Campo | Valor |
|-------|-------|
| **Entidad** | {tipo} {id} |
| **Estado** | {status} |
| **Fecha investigación** | {hoy} |

---

## Resumen Ejecutivo

{2-3 oraciones describiendo qué pasó y por qué}

---

## Diagrama de Contexto

{Diagrama ASCII mostrando la jerarquía organizacional y entidades relacionadas}

---

## Timeline de Eventos

| Fecha/Hora | Evento | Usuario | Status |
|------------|--------|---------|--------|
| {timestamp} | {qué pasó} | {quién} | {resultado} |

---

## Hallazgos Clave

1. {Hallazgo principal}
2. {Hallazgo secundario}
3. {Hallazgo adicional}

---

## Causa Raíz

{Explicación de por qué ocurrió el problema}

---

## Usuarios Involucrados

| Usuario | Email | Acciones |
|---------|-------|----------|
| {nombre} | {email} | {qué hizo} |

---

## Recomendaciones

| Prioridad | Acción |
|-----------|--------|
| Alta | {acción inmediata} |
| Media | {acción correctiva} |
| Baja | {mejora preventiva} |
```

---

## Iconos de Referencia

| Icono | Significado |
|-------|-------------|
| ✅ | OK / Correcto |
| ⚠️ | Warning / Revisar |
| ❌ | Error / Fallido |
| 🔄 | En progreso |
| 💥 | Causa raíz |
| 💡 | Insight |
| 👤 | Usuario |

---

## Checklist de Investigación

Antes de finalizar, verificar:

- [ ] ¿Invoqué `np-api`?
- [ ] ¿Invoqué `np-audits-read`?
- [ ] ¿Obtuve el estado actual de la entidad?
- [ ] ¿Obtuve el historial de cambios?
- [ ] ¿Identifiqué la causa raíz?
- [ ] ¿Documenté los usuarios involucrados?
- [ ] ¿Consideré Fase 4.5 (K8s Deep Dive) cuando la API no alcanzaba?
- [ ] ¿Generé el reporte completo?
