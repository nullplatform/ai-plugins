# Reconciliation Howto

Cómo usar el script `reconcile_action_items.sh` y los patrones detrás.

## Concepto

Ver `concepts/reconciliation.md` para el background completo. Resumen: cada vez que un agente escanea, debe (1) crear items para problemas nuevos y (2) auto-cerrar items que ya no aplican.

## Input format

`reconcile_action_items.sh` recibe un archivo JSON con la lista de problemas detectados en el scan actual. Cada objeto debe tener al menos:

1. El campo identificado por `--metadata-key` (al nivel raíz o dentro de `metadata`)
2. Los campos para crear el action item: `title`, `priority`, `category_slug` o `category_id`, `metadata`
3. Otros campos opcionales: `description`, `value`, `affected_resources`, `references`, `labels`

```json
[
  {
    "cve_id": "CVE-2024-1234",
    "title": "Critical: lodash CVE-2024-1234",
    "priority": "critical",
    "category_slug": "security-vulnerability",
    "value": 85,
    "description": "## Vulnerability\n...",
    "metadata": {
      "cve_id": "CVE-2024-1234",
      "cvss_score": 8.5,
      "package": "lodash",
      "current_version": "4.17.19",
      "fixed_version": "4.17.21"
    },
    "affected_resources": [
      {"type": "application", "name": "payment-service"}
    ]
  },
  {
    "cve_id": "CVE-2024-5678",
    "title": "High: express CVE-2024-5678",
    ...
  }
]
```

## Invocación

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts/reconcile_action_items.sh \
  --nrn "organization=1:account=2" \
  --agent-id "agent:vuln-scanner" \
  --metadata-key "cve_id" \
  --problems-file ./current_vulns.json \
  [--dry-run]
```

| Flag | Required | Description |
|------|----------|-------------|
| `--nrn` | Yes | NRN scope donde reconciliar |
| `--agent-id` | Yes | Filtro de `created_by`. Solo cierra items de este agente |
| `--metadata-key` | Yes | Campo de metadata usado como identidad única (ej `cve_id`, `resource_arn`) |
| `--problems-file` | Yes | Path al JSON con la lista actual de problemas |
| `--dry-run` | No | Imprime el plan sin ejecutar POST/PATCH |

### Permisos e identidad

- **Permisos**: el auto-cierre usa `close_action_item.sh`, que requiere el claim `governance:action_item:close` (además de `:create`, `:list`, `:read` y `:update` para crear, listar y comentar). Ver `concepts/permissions-matrix.md`.
- **Identidad**: la API resuelve la identidad del actor a partir del token. En el create, `--created-by` (que el reconciler fija al `--agent-id`) solo se honra para llamadores con derechos de delegación; en el auto-close no hay override de actor posible (ese endpoint no tiene canal de actor). El `created_by` con el que quedan los items creados debe coincidir con el `--agent-id` usado para filtrar en el próximo run. Si el token del agente **no** tiene delegación, los items quedan atribuidos a la identidad del token y el filtro `created_by=<agent-id>` no los va a encontrar en el siguiente run (y el reconciler recrearía duplicados). Recomendación práctica: usar como `--agent-id` la misma identidad del token, o correr con delegación.

## Output

El script imprime un summary JSON a stdout (las acciones se loguean a stderr):

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

- `created`: problemas nuevos sin item existente → se crearon.
- `closed`: items en `open` cuyo problema ya no se detecta → se auto-cerraron.
- `unchanged`: items cuyo problema sigue presente → sin cambios.
- `skipped`: items obsoletos en `deferred` / `pending_*` → se respetaron sin tocar (solo se loguean).

## Algoritmo (interno)

1. Lee `--problems-file` y construye `currentByKey = {metadata_key_value: problem}`
2. `GET /governance/action_item?nrn=...&created_by=<agent>&status[]=open&status[]=deferred&status[]=pending_*` (paginado)
3. Construye `existingByKey = {item.metadata[key]: item}`
4. Diff:
   - **Created**: `currentByKey.keys() - existingByKey.keys()` → `create_action_item.sh` para cada uno
   - **Closed**: `existingByKey.keys() - currentByKey.keys()`, filtrando solo los `status==open`:
     - Llama `add_comment.sh` con la explicación del auto-cierre
     - Llama `close_action_item.sh` con `--reason "Resource no longer present in latest scan; auto-closed by reconciliation"`
   - **Unchanged**: en ambos
   - **Skipped**: items en `deferred` o `pending_*` que ya no tienen problema actual (NO se cierran, solo se loguean)
5. Imprime el reporte JSON

## Dry-run

`--dry-run` no llama ningún POST/PATCH. Loguea a stderr las acciones que **se ejecutarían** y emite el summary JSON con `"dry_run": true`:

```
WOULD CREATE: CVE-2024-1234 (Critical: lodash...)
WOULD CREATE: CVE-2024-5678 (High: express...)
WOULD CLOSE: ai_old (key cve_id=CVE-2023-9999 no longer detected)
WOULD SKIP: ai_def (status=deferred, respecting human decision)
```

Recomendado correr con `--dry-run` la primera vez para verificar el comportamiento antes de ejecutar real.

## Cuándo NO usar reconciliation

- **Problemas transitorios**: alertas que se auto-resuelven en segundos. Mejor con TTL.
- **Detección no determinística**: si el scan puede fallar y "no detectar" no significa "no existe", NO auto-cerrar. Solo crear nuevos.
- **Items compartidos entre agentes**: cada agente solo cierra los suyos (filtrado por `created_by`).

## Ejemplo end-to-end

```bash
#!/bin/bash
set -e
NRN="organization=1:account=2"
AGENT_ID="agent:vuln-scanner"
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts"

# 1. Setup category (idempotent)
"$SCRIPTS/ensure_category.sh" \
  --nrn "$NRN" --slug "security-vulnerability" \
  --name "Security Vulnerability" --color "#DC2626" --icon "shield" \
  --unit-name "Risk Score" --unit-symbol "R" \
  --config '{"max_deferral_days":90}' > /dev/null

# 2. Run scanner (your custom logic)
my-vuln-scanner --output ./current_vulns.json

# 3. Reconcile (dry-run first to validate)
"$SCRIPTS/reconcile_action_items.sh" \
  --nrn "$NRN" \
  --agent-id "$AGENT_ID" \
  --metadata-key cve_id \
  --problems-file ./current_vulns.json \
  --dry-run

# 4. If looks good, execute for real
"$SCRIPTS/reconcile_action_items.sh" \
  --nrn "$NRN" \
  --agent-id "$AGENT_ID" \
  --metadata-key cve_id \
  --problems-file ./current_vulns.json
```
