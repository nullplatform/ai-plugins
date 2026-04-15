---
name: np-governance-action-items
description: Operate on Nullplatform Governance Action Items - list, create, update action items, manage categories and suggestions. Includes patterns for idempotency, reconciliation, and executor agents. Use when the user wants to query, create, modify or analyze action items, categories, or suggestions, or build agent flows around them.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/*.sh)
---

# np-governance-action-items

Skill operativo para el sistema de Action Items de Nullplatform Governance. Provee scripts CRUD para action items, categorías y suggestions, junto con patterns reutilizables (idempotency, reconciliation, executor polling, hold detection).

Endpoints públicos: `https://api.nullplatform.com/governance/action_item` y `https://api.nullplatform.com/governance/action_item_category`.

## Critical Rules

1. **NUNCA usar `curl` directo** contra `api.nullplatform.com`. Todos los scripts delegan a `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh` con el método correspondiente.
2. **Idempotency es obligatorio** en cualquier flujo de creación: antes de crear un action item, buscar por `metadata.<key>` para evitar duplicados. Ver `docs/concepts/idempotency.md`.
3. **Estado `metadata` vs `user_metadata`**: `metadata` es libre (objeto anidado) y solo lo edita el agente. `user_metadata` es flat key/value (solo escalares: string/number/boolean/null) y lo edita el usuario humano. Ver `docs/concepts/metadata-vs-user-metadata.md`.
4. **Reconciliation respeta decisiones humanas**: nunca cerrar items en `deferred`, `pending_*` o creados por otros agentes. Ver `docs/concepts/reconciliation.md`.
5. **Cada action item pertenece a un NRN**: el NRN define ownership y permisos. Cualquier query de listado debe incluir `--nrn`.

## Available Scripts

### Action Items (14)

| Script | Endpoint | Propósito |
|--------|----------|-----------|
| `list_action_items.sh` | `GET /governance/action_item` | Listar con filtros (nrn, status, category, priority, metadata.*) |
| `get_action_item.sh` | `GET /governance/action_item/:id` | Detalle de un action item |
| `search_action_items_by_metadata.sh` | `GET /governance/action_item?metadata.<key>=<value>` | ⭐ Helper de idempotency |
| `create_action_item.sh` | `POST /governance/action_item` | Crear action item |
| `update_action_item.sh` | `PATCH /governance/action_item/:id` | Update parcial |
| `defer_action_item.sh` | `POST /governance/action_item/:id/defer` | Diferir hasta una fecha |
| `resolve_action_item.sh` | `POST /governance/action_item/:id/resolve` | Marcar como resuelto |
| `reject_action_item.sh` | `POST /governance/action_item/:id/reject` | Rechazar con razón |
| `reopen_action_item.sh` | `POST /governance/action_item/:id/reopen` | Reabrir desde deferred/rejected |
| `close_action_item.sh` | `POST /governance/action_item/:id/close` | Cerrar (open → closed) |
| `list_comments.sh` | `GET /governance/action_item/:id/comments` | Listar comentarios |
| `add_comment.sh` | `POST /governance/action_item/:id/comments` | Agregar comentario |
| `list_audit_logs.sh` | `GET /governance/action_item/:id/audit-logs` | Audit log completo |
| `reconcile_action_items.sh` | (orchestrator) | ⭐ Reconciliation: detect → create/close |

### Categories (6)

| Script | Endpoint | Propósito |
|--------|----------|-----------|
| `list_categories.sh` | `GET /governance/action_item_category` | Listar categorías |
| `get_category.sh` | `GET /governance/action_item_category/:id` | Detalle |
| `ensure_category.sh` | (search-or-create) | ⭐ Idempotent: busca por slug, si no existe crea |
| `create_category.sh` | `POST /governance/action_item_category` | Crear categoría |
| `update_category.sh` | `PATCH /governance/action_item_category/:id` | Update parcial |
| `delete_category.sh` | `DELETE /governance/action_item_category/:id` | Eliminar (falla si tiene action items asociados) |

### Suggestions (12)

| Script | Endpoint | Propósito |
|--------|----------|-----------|
| `list_suggestions.sh` | `GET /governance/action_item/:id/suggestions` | Listar suggestions |
| `get_suggestion.sh` | `GET /governance/action_item/:id/suggestions/:sId` | Detalle |
| `create_suggestion.sh` | `POST /governance/action_item/:id/suggestions` | Crear suggestion |
| `update_suggestion.sh` | `PATCH /governance/action_item/:id/suggestions/:sId` | Update genérico |
| `approve_suggestion.sh` | `PATCH ... {status: approved}` | pending → approved |
| `reject_suggestion.sh` | `PATCH ... {status: rejected}` | pending → rejected |
| `mark_suggestion_applied.sh` | `PATCH ... {status: applied, execution_result}` | approved → applied |
| `mark_suggestion_failed.sh` | `PATCH ... {status: failed, execution_result}` | approved → failed |
| `retry_suggestion.sh` | `PATCH ... {status: approved}` | failed → approved (retry) |
| `find_approved_suggestions.sh` | (helper) | ⭐ Executor: busca approved para un owner |
| `poll_approved_suggestions.sh` | (helper) | ⭐ Executor: one-shot polling loop |
| `check_action_item_hold.sh` | (helper) | ⭐ Executor: detecta hold/abort en comments humanos |

## Documentation (progressive disclosure)

### Conceptual (carga on-demand cuando se necesita el modelo)

@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/model.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/lifecycle.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/idempotency.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/reconciliation.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/categories.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/suggestions.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/metadata-vs-user-metadata.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/confidence-levels.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/permissions-matrix.md

### Operacional (cómo usar los scripts)

@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/action-items-crud.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/categories-crud.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/suggestions-crud.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/executor-patterns.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/reconciliation-howto.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/operations/troubleshooting.md

## Quick Examples

### Listar action items abiertos en un NRN
```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/list_action_items.sh \
  --nrn "organization=1" --status open --limit 25
```

### Crear con idempotency
```bash
# 1. Buscar por metadata key
EXISTING=$(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/search_action_items_by_metadata.sh \
  --nrn "organization=1" --metadata-key cve_id --metadata-value CVE-2024-1234)

# 2. Si no existe, crear
if [ "$(echo "$EXISTING" | jq '.results | length')" = "0" ]; then
  ${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/create_action_item.sh \
    --nrn "organization=1" \
    --title "CVE-2024-1234 in lodash" \
    --category-slug "security-vulnerability" \
    --priority critical \
    --created-by "agent:vuln-scanner" \
    --metadata '{"cve_id":"CVE-2024-1234","cvss_score":8.5}'
fi
```

### Suggestion lifecycle
```bash
# Detector crea suggestion
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/create_suggestion.sh \
  --action-item-id "<id>" \
  --created-by "agent:vuln-scanner" \
  --owner "executor:pr-creator" \
  --confidence 0.95 \
  --metadata '{"action_type":"dependency_upgrade","package":"lodash","to_version":"4.17.21"}' \
  --user-metadata '{"target_branch":"main","auto_merge":"false"}'

# Humano aprueba
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/approve_suggestion.sh \
  --action-item-id "<id>" --suggestion-id "<sId>"

# Executor reporta éxito
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/mark_suggestion_applied.sh \
  --action-item-id "<id>" --suggestion-id "<sId>" \
  --execution-result '{"success":true,"message":"PR created","details":{"pr_url":"..."}}'
```

## Authentication

Todos los scripts heredan auth de `np-api`. Configurar una de estas variables de entorno:

```bash
# Recomendado: API key (no expira, token cacheado)
export NP_API_KEY='sk-...'

# Alternativa: bearer token (expira ~24h)
export NP_TOKEN='eyJ...'
```

Verificar con: `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh`

Permisos JWT requeridos: `governance:action_item:list/read/create/update/delete/defer/reject/resolve/approve`, `governance:action_item:suggestion:create/update/delete/approve/reject/execute`, `governance:action_item:category:list/read/create/update/delete`. Ver `docs/concepts/permissions-matrix.md` para el set completo y un ejemplo de rol YAML.
