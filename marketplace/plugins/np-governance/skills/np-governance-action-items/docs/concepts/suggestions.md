# Suggestions

Una **suggestion** es una propuesta automatizada de solución para un action item. Tiene su propio lifecycle y es procesada por un **executor agent** distinto del **detector agent** que la creó.

## Roles

| Role | Description | Example identifier |
|------|-------------|--------------------|
| **Detector agent** | Crea el action item y la suggestion. Reportado como `created_by` | `agent:vulnerability-scanner` |
| **Human / System** | Aprueba o rechaza la suggestion (vía dashboard o API) | usuario humano |
| **Executor agent** | Encuentra suggestions approved, las ejecuta, y reporta resultado. Reportado como `owner` | `executor:pr-creator` |

Un mismo agente puede actuar como detector + executor, pero **conceptualmente** son roles distintos.

## Lifecycle

```
                ┌──────────────────────────────────────────────────────┐
                │  DETECTOR        HUMAN/SYSTEM       EXECUTOR         │
                │  creates         approves           executes         │
                │                  or rejects         and reports      │
                │                                                      │
  ┌─────────┐  │  ┌──────────┐                       ┌─────────┐      │
  │ pending │──┼─►│ approved │──────────────────────►│ applied │ TERM │
  └────┬────┘  │  └────┬─────┘                       └─────────┘      │
       │       │       │                                              │
       │       │       │                              ┌─────────┐     │
       │       │       └─────────────────────────────►│ failed  │     │
       │       │                                      └────┬────┘     │
       │       │                                           │          │
       │       │                            retry          │          │
       │       │                          ┌────────────────┘          │
       │       │                          v                           │
       │       │                     ┌──────────┐                     │
       │       │                     │ approved │                     │
       │       │                     └──────────┘                     │
       │       │                                                      │
       ├───────┼─► rejected   TERM (rejected by human)                 │
       │       │                                                      │
       └───────┼─► expired    TERM (expired without action)            │
                │                                                      │
                └──────────────────────────────────────────────────────┘
```

### Estados terminales

`applied`, `rejected`, `expired` — no se pueden cambiar.

### Estado retryable

`failed` — puede pasar de vuelta a `approved` para reintentar.

### Transiciones por PATCH

Todas las transiciones se hacen con `PATCH /governance/action_item/:id/suggestions/:sId` con `{status: "..."}`:

| From → To | Body |
|-----------|------|
| pending → approved | `{"status": "approved"}` |
| pending → rejected | `{"status": "rejected"}` |
| approved → applied | `{"status": "applied", "execution_result": {...}}` |
| approved → failed | `{"status": "failed", "execution_result": {...}}` |
| failed → approved (retry) | `{"status": "approved"}` |

## Auto-generated comments

Cada cambio de status de una suggestion genera **automáticamente** un comment en el action item parent. El comment incluye el actor (quién hizo el cambio) y la transición. Los agentes no necesitan agregar comments para estos eventos, aunque pueden agregar comments adicionales con detalles de progreso.

## `metadata` vs `user_metadata` vs `user_metadata_config`

Tres campos JSON cumplen propósitos distintos. Ver `metadata-vs-user-metadata.md` para detalle.

**Resumen**:
- `metadata` → datos técnicos del executor (free-form, anidado, no editable por user)
- `user_metadata` → params editables por user (flat, escalares only, editable solo en pending/failed)
- `user_metadata_config` → schema descriptivo de cada key de `user_metadata` para que la UI renderice forms

## Endpoints

| Method | Path | Permission |
|--------|------|------------|
| GET | `/governance/action_item/:id/suggestions` | `governance:action_item:read` |
| GET | `/governance/action_item/:id/suggestions/:sId` | `governance:action_item:read` |
| POST | `/governance/action_item/:id/suggestions` | `governance:action_item:suggestion:create` |
| PATCH | `/governance/action_item/:id/suggestions/:sId` | `governance:action_item:suggestion:update` |
| DELETE | `/governance/action_item/:id/suggestions/:sId` | `governance:action_item:suggestion:delete` |

## Filters en GET

- `status`: filtra por status (`pending`, `approved`, `applied`, etc.)
- `owner`: filtra por executor identifier
- `created_by`: filtra por agente detector

```bash
GET /governance/action_item/abc/suggestions?status=approved&owner=executor:pr-creator
```

## Expiry

Si una suggestion tiene `expires_at` y no se actuó antes de esa fecha, el sistema la pasa automáticamente a `expired` (terminal). Si se intenta aprobar una expirada, la operación falla.

## Confidence

Field opcional `confidence` (0.0–1.0) indica la certeza del detector. Convención de niveles en `confidence-levels.md`.

## Pattern: detector + executor flow

```bash
# === DETECTOR ===
# 1. Crear action item con metadata identificadora
AI_ID=$(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/create_action_item.sh \
  --nrn "organization=1" --title "..." --category-slug "security-vulnerability" \
  --created-by "agent:vuln-scanner" --metadata '{"cve_id":"CVE-2024-1234"}' | jq -r .id)

# 2. Crear suggestion con metadata para el executor
S_ID=$(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/create_suggestion.sh \
  --action-item-id "$AI_ID" \
  --created-by "agent:vuln-scanner" \
  --owner "executor:pr-creator" \
  --confidence 0.95 \
  --metadata '{"action_type":"dependency_upgrade","package":"lodash","to_version":"4.17.21"}' \
  --user-metadata '{"target_branch":"main","auto_merge":"false"}' | jq -r .id)

# === HUMAN APPROVES ===
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/approve_suggestion.sh \
  --action-item-id "$AI_ID" --suggestion-id "$S_ID"

# === EXECUTOR ===
# Polling: encuentra approved suggestions
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/poll_approved_suggestions.sh \
  --owner "executor:pr-creator" --nrn "organization=1"

# Antes de ejecutar: check hold/abort en comments humanos
HOLD=$(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/check_action_item_hold.sh --id "$AI_ID")
if [ "$(echo "$HOLD" | jq -r .should_proceed)" = "false" ]; then
  echo "Hold detected: $(echo "$HOLD" | jq -r .hold_reason)"
  exit 0
fi

# Ejecutar (lógica específica del executor) ... y reportar
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/mark_suggestion_applied.sh \
  --action-item-id "$AI_ID" --suggestion-id "$S_ID" \
  --execution-result '{"success":true,"message":"PR #456 created","details":{"pr_url":"https://..."}}'
```
