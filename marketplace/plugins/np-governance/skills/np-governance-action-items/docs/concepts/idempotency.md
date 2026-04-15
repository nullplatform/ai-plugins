# Idempotency Pattern

**Regla de oro**: antes de crear un action item, **siempre** buscar por una `metadata.<key>` que identifique unívocamente el problema. Esto evita duplicados cuando el agente corre múltiples veces.

## Pattern básico

```bash
# 1. Buscar por metadata key (status filtra a "vivos")
EXISTING=$(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/search_action_items_by_metadata.sh \
  --nrn "organization=1" \
  --metadata-key "cve_id" \
  --metadata-value "CVE-2024-1234")

COUNT=$(echo "$EXISTING" | jq '.results | length')

if [ "$COUNT" = "0" ]; then
  # 2. No existe → crear
  ${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/create_action_item.sh \
    --nrn "organization=1" \
    --title "CVE-2024-1234 in lodash" \
    --category-slug "security-vulnerability" \
    --created-by "agent:vuln-scanner" \
    --metadata '{"cve_id":"CVE-2024-1234","cvss_score":8.5,"package":"lodash"}'
else
  # 3. Ya existe → noop o agregar comment con info nueva
  EXISTING_ID=$(echo "$EXISTING" | jq -r '.results[0].id')
  echo "Already tracked: $EXISTING_ID"
fi
```

## Estados a considerar al buscar

| Scenario | Decisión del agente |
|----------|---------------------|
| No existe action item | **Crear nuevo** |
| Existe en `open` | **No crear**. Opcional: agregar comment con info nueva |
| Existe en `deferred` | **No crear** (humano lo difirió intencionalmente) |
| Existe en `pending_deferral`/`pending_rejection`/`pending_verification` | **No crear** (en flujo de aprobación) |
| Existe en `rejected` | **No crear** (humano rechazó) |
| Existe en `resolved`/`closed` | Evaluar: si el problema reapareció después de resolverse, crear uno NUEVO (no reabrir el viejo, para mantener historia limpia) |

El script `search_action_items_by_metadata.sh` por defecto incluye los estados "vivos" (`open`, `deferred`, `pending_*`) para detectar duplicados. Pasar `--include-resolved` si querés también ver los terminales.

## Diseñando el `metadata` field

El `metadata` debe contener al menos UN field que identifique unívocamente el problema:

| Tipo de agente | Idempotency key | Ejemplo de value |
|----------------|-----------------|------------------|
| Vulnerability scanner | `cve_id` o `vuln_id` | `CVE-2024-1234` |
| Cost optimizer | `resource_arn` o `instance_id` | `arn:aws:ec2:...:i-0abc` |
| Performance analyzer | `endpoint` o `trace_id` | `GET /api/users` |
| Compliance | `rule_id` | `pci-dss-3.2.1` |
| Deprecation tracker | `dep_id` | `python-2.7` |

Además del idempotency key, recomendado incluir:
- `agent_type`: tipo del agente (ej `vulnerability-scanner`)
- `agent_version`: versión del agente
- `detected_at`: timestamp de detección
- `scan_id`: ID del scan que originó la detección
- Datos contextuales del problema (severity, confidence, etc.)

```json
{
  "metadata": {
    "cve_id": "CVE-2024-1234",
    "agent_type": "vulnerability-scanner",
    "agent_version": "1.2.0",
    "detected_at": "2024-01-15T10:30:00Z",
    "scan_id": "scan-abc123",
    "cvss_score": 8.5,
    "severity": "critical",
    "affected_package": "lodash",
    "current_version": "4.17.19",
    "fixed_version": "4.17.21"
  }
}
```

## Filtros de query soportados

`GET /governance/action_item?metadata.<key>=<value>&nrn=...&status[]=open&status[]=deferred`

El backend soporta filtros JSONB sobre `metadata.*`. Cualquier campo del JSON puede usarse como filtro.

Otros filtros útiles:
- `created_by=agent:vuln-scanner` — solo items del agente
- `category_id=...` o `category_slug=...`
- `priority=critical`
- `labels.<key>=<value>` — filtros sobre el `labels` JSONB
- `due_date_before=...` / `due_date_after=...`
- `min_value=...` / `max_value=...`

## Manejo de errores

| HTTP code | Causa probable | Acción |
|-----------|---------------|--------|
| 409 Conflict | Slug duplicado u otra restricción de unicidad a nivel BD | Buscar por metadata y reusar el existente |
| 400 Bad Request | Validación fallida (NRN inválido, campos faltantes) | Loguear y skip; revisar el payload |
| 401/403 | Token sin permisos `governance:action_item:create` | Ver `permissions-matrix.md` |
| 404 | Categoría no existe | Llamar `ensure_category.sh` antes |
