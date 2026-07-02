# Executor Patterns

Patrones para construir un executor agent que polea suggestions approved, las ejecuta, y reporta el resultado.

## Flujo completo

```
loop forever (or per cron tick):
  1. find approved suggestions for this owner
  2. for each (action_item, suggestion):
       a. check_action_item_hold(action_item.id) → if hold, skip
       b. add comment "Execution started..."
       c. execute action based on suggestion.metadata.action_type
       d. if success:
            - mark_suggestion_applied (with execution_result)
            - add comment with result
            - if action resolves the problem: resolve_action_item (--resolution + --evidence-url)
       e. if failure:
            - mark_suggestion_failed (with execution_result)
            - add comment with error
  3. retry failed suggestions (up to N attempts)
  4. sleep / wait for next tick
```

## Implementación bash mínima

```bash
#!/bin/bash
set -e

OWNER="executor:pr-creator"
NRN="organization=1"
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/scripts"

# 1. Find approved
APPROVED=$("$SCRIPTS/find_approved_suggestions.sh" --owner "$OWNER" --nrn "$NRN")

# 2. Iterate
echo "$APPROVED" | jq -c '.[]' | while read -r item; do
  AI_ID=$(echo "$item" | jq -r '.action_item.id')
  S_ID=$(echo "$item" | jq -r '.suggestion.id')
  ACTION_TYPE=$(echo "$item" | jq -r '.suggestion.metadata.action_type')

  # 2a. Check hold
  HOLD=$("$SCRIPTS/check_action_item_hold.sh" --id "$AI_ID")
  if [ "$(echo "$HOLD" | jq -r .should_proceed)" = "false" ]; then
    REASON=$(echo "$HOLD" | jq -r .hold_reason)
    echo "Skipping $AI_ID: $REASON"
    continue
  fi

  # 2b. Comment start
  "$SCRIPTS/add_comment.sh" --id "$AI_ID" --author "$OWNER" \
    --content "## Execution started\nProcessing suggestion $S_ID (action_type=$ACTION_TYPE)"

  # 2c. Execute (your custom logic)
  if execute_action "$item"; then
    "$SCRIPTS/mark_suggestion_applied.sh" \
      --action-item-id "$AI_ID" --suggestion-id "$S_ID" \
      --execution-result "$EXEC_RESULT"
    "$SCRIPTS/add_comment.sh" --id "$AI_ID" --author "$OWNER" \
      --content "## Execution successful"
  else
    "$SCRIPTS/mark_suggestion_failed.sh" \
      --action-item-id "$AI_ID" --suggestion-id "$S_ID" \
      --execution-result "$EXEC_RESULT"
  fi
done
```

`execute_action()` es tu lógica específica: dependiendo de `metadata.action_type` (`dependency_upgrade`, `right_sizing`, `config_change`, etc.), invocás la herramienta correspondiente.

> **Identidad**: los flags `--actor` / `--author` son opcionales. La API resuelve la identidad del ejecutor a partir del token; esos flags solo se honran para llamadores con derechos de delegación. Si no, se ignoran y se registra la identidad del token.

## Resolver con evidencia

Cuando el executor resuelve un action item después de ejecutar un fix, conviene dejar traza de qué se hizo y dónde. `resolve_action_item.sh` acepta:

- `--resolution "<qué se hizo>"` — se persiste como comment y en el audit log.
- `--evidence-url <link a PR/pipeline/scan>` — queda registrado en el audit log.

```bash
"$SCRIPTS/resolve_action_item.sh" --id "$AI_ID" \
  --resolution "Bumped lodash 4.17.19 → 4.17.21 vía PR #456" \
  --evidence-url "https://github.com/org/repo/pull/456"
```

Así el audit y los comments quedan con el rastro del fix, sin depender de que alguien reconstruya después qué pasó.

## Aprobaciones en vuelo (`pending_*`)

`resolve` / `defer` / `reject` pueden requerir aprobación según la **policy del servicio de aprobaciones de la plataforma** (no la `config` del item). Cuando eso pasa, el item no queda resuelto: pasa a `pending_verification` (o `pending_deferral` / `pending_rejection`) y se crea un pedido de aprobación.

El executor **no puede aprobar ni denegar** por esta API — esos endpoints no existen. Solo puede pollear el status con `GET` (`get_action_item.sh`):

- **Aprobado** → el item pasa al estado final (`resolved` / `deferred` / `rejected`).
- **Denegado o cancelado** → vuelve a `open` con un comment automático del reviewer.

**Comportamiento recomendado**: no bloquear el loop esperando la decisión. Registrar que el item quedó en `pending_*` y seguir con los demás items; en el próximo tick, re-pollear el status y actuar según el desenlace (si volvió a `open`, se puede reintentar el fix; si quedó terminal, listo). Un poll con backoff exponencial también es válido si el executor procesa un solo item por vez.

## Hold/abort detection

`check_action_item_hold.sh` lee los comentarios humanos y busca keywords. Es el mecanismo para que un humano "pause" un executor en flight: simplemente agregar un comment como "do not execute, waiting for review".

Esto es importante porque:
- El humano aprobó la suggestion en un momento, pero después puede tener segundas opiniones.
- Permite "feedback loop" entre humanos y executors sin tener que re-rechazar la suggestion.
- Es el equivalente a un "feature flag temporal" controlado por comments.

**Recomendación**: chequear hold ANTES de cada acción potencialmente irreversible (crear PR, modificar config, etc.).

## Retry policy

Failed suggestions pueden volver a `approved` con `retry_suggestion.sh`. Política sugerida:

```bash
# Retry failed con < 3 attempts
FAILED=$("$SCRIPTS/list_suggestions.sh" \
  --action-item-id "$AI_ID" --status failed --owner "$OWNER")

echo "$FAILED" | jq -c '.results[]' | while read -r s; do
  S_ID=$(echo "$s" | jq -r .id)
  ATTEMPTS=$(echo "$s" | jq -r '.execution_result.details.attempt // 0')

  if [ "$ATTEMPTS" -lt 3 ]; then
    "$SCRIPTS/retry_suggestion.sh" \
      --action-item-id "$AI_ID" --suggestion-id "$S_ID" \
      --user-metadata "{\"retry_attempt\":\"$((ATTEMPTS + 1))\"}"
  fi
done
```

Después de retry-aprobada, la suggestion vuelve a `approved` y el executor la procesa en el próximo poll.

## Error handling

| Error | Mitigation |
|-------|-----------|
| 401/403 | Token sin permisos `governance:action_item:suggestion:update`. Ver `permissions-matrix.md` |
| 404 (suggestion not found) | La suggestion fue borrada. Skip y continuar |
| 409 (state conflict) | Otra entidad ya cambió el status (ej: humano la rechazó). Skip y continuar |
| 5xx | Backoff exponencial y reintento. No marcar `failed` por errores transitorios del API |

## Concurrency

Si corren múltiples instancias del mismo executor, hay riesgo de procesar la misma suggestion 2 veces. Mitigaciones:

1. **Soft locking via comments**: el primer executor que toma la suggestion agrega un comment `## Claimed by executor:pr-creator-instance-1`. Los otros chequean ese comment antes de ejecutar.
2. **Patcheable status custom field**: si la API soporta una status interna `executing` (ver con el equipo de governance), usarlo.
3. **Lock externo**: usar Redis/etcd para hacer lock distribuido por suggestion ID.

Para la mayoría de casos, **una sola instancia del executor por owner es suficiente** y evita el problema.

## Frequency

Los executors normalmente corren:
- **Cron** (cada 5–15 min) para casos no críticos
- **Event-driven** (webhook desde nullplatform cuando una suggestion pasa a approved) para latencia baja
- **Manual** (un user invoca el script) para troubleshooting

El skill no impone una frecuencia — es decisión del agente.
