# Reconciliation Pattern

Un agente maduro no solo crea action items, sino que **reconcilia** su estado con la realidad cada vez que escanea. La reconciliación es el ciclo: detect → create new → close obsolete.

## Concepto

```
Cada run del agente:
  1. Escanea y obtiene LISTA ACTUAL de problemas
  2. Lista action items existentes creados por el agente (open + deferred + pending_*)
  3. Compara por metadata key (idempotency key)
  4. Decisiones:
     - Problemas NUEVOS sin action item → crear
     - Problemas existentes con action item → noop (o agregar comment si cambió algo)
     - Action items SIN problema actual → cerrar automáticamente (con comment)
```

## Reglas de seguridad (CRITICAL)

| Regla | Justificación |
|-------|---------------|
| **Solo cerrar items del propio agente** | Filtrar `created_by=agent:my-agent` antes de auto-cerrar. Nunca tocar items creados por humanos u otros agentes |
| **Respetar items `deferred`** | Si un humano difirió, no cerrar aunque el problema ya no exista. Opcional: agregar comment "no longer detected" |
| **No tocar items en `pending_*`** | Esos están en flujo de aprobación humana |
| **Siempre comentar antes de cerrar** | Agregar un comment explicando por qué se cerró (idempotency key, scan time, agente). Deja traceability |
| **No reabrir items cerrados** | Si un problema reaparece después de cerrado, crear UN NUEVO action item. Mantiene history limpia |
| **Frecuencia atada al scan** | Reconciliar en cada run del agente, no en un job separado |

## Ejemplo de pseudocódigo

```python
def reconcile(nrn, agent_id, current_problems, metadata_match_key):
    # 1. Fetch all live items from this agent (paginated)
    existing = fetch_action_items(
        nrn=nrn,
        created_by=agent_id,
        status=['open', 'deferred', 'pending_deferral', 'pending_verification', 'pending_rejection']
    )
    
    existing_by_key = {item.metadata[metadata_match_key]: item for item in existing}
    current_by_key = {p[metadata_match_key]: p for p in current_problems}
    
    results = {'created': 0, 'closed': 0, 'unchanged': 0, 'skipped': 0}
    
    # 2. Create for new problems
    for key, problem in current_by_key.items():
        if key not in existing_by_key:
            create_action_item(nrn, problem)
            results['created'] += 1
        else:
            results['unchanged'] += 1
    
    # 3. Auto-close obsolete items (only the ones in 'open' status)
    for key, item in existing_by_key.items():
        if key not in current_by_key:
            if item.status == 'open':
                add_comment(item.id, f"Auto-closed: {metadata_match_key}={key} no longer detected by {agent_id}")
                close_action_item(item.id, actor=agent_id,
                                  reason="Resource no longer present in latest scan; auto-closed by reconciliation")
                results['closed'] += 1
            else:
                # deferred / pending_* — respect human decision
                results['skipped'] += 1
    
    return results
```

## Script bash equivalente

El script `reconcile_action_items.sh` implementa este algoritmo:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/reconcile_action_items.sh \
  --nrn "organization=1" \
  --agent-id "agent:vuln-scanner" \
  --metadata-key "cve_id" \
  --problems-file ./current_vulns.json \
  --dry-run
```

`current_vulns.json` debe ser un array JSON donde cada objeto contiene al menos el `metadata-key` especificado:

```json
[
  {
    "cve_id": "CVE-2024-1234",
    "title": "Critical: lodash CVE-2024-1234",
    "priority": "critical",
    "metadata": {
      "cve_id": "CVE-2024-1234",
      "cvss_score": 8.5,
      "package": "lodash"
    }
  },
  {
    "cve_id": "CVE-2024-5678",
    "title": "High: express CVE-2024-5678",
    "priority": "high",
    "metadata": { ... }
  }
]
```

Output del script (summary JSON a stdout; las acciones se loguean a stderr):

```json
{
  "dry_run": false,
  "scan": {
    "current_problems": 7,
    "existing_items": 6
  },
  "created": 2,
  "closed": 1,
  "unchanged": 5,
  "skipped": 1
}
```

`created` = problemas nuevos creados; `closed` = items en `open` auto-cerrados porque su problema ya no se detecta; `unchanged` = items cuyo problema sigue presente; `skipped` = items obsoletos en `deferred` / `pending_*` que se respetaron sin tocar.

`--dry-run` imprime el plan sin ejecutar ningún POST/PATCH.

## Cuando NO usar reconciliation

- Cuando el problema es **transitorio** (ej: alertas de monitoring que se auto-resuelven en segundos). Mejor manejar con TTL.
- Cuando es difícil saber si "no se detectó" significa "no existe" o "el scan falló". En ese caso, NO auto-cerrar — solo crear nuevos.
- Cuando hay multiple agentes con el mismo `metadata.<key>` pero distinto `created_by`. Cada uno solo cierra los suyos.
