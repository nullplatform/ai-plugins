# Suggestions CRUD

Scripts para gestionar suggestions. Endpoints anidados bajo `/governance/action_item/:id/suggestions`.

## list_suggestions.sh

```bash
list_suggestions.sh \
  --action-item-id <ai_id> \
  [--status pending|approved|applied|failed|rejected|expired] \
  [--owner <executor_id>] \
  [--created-by <agent_id>] \
  [--offset 0] [--limit 25]
```

## get_suggestion.sh

```bash
get_suggestion.sh \
  --action-item-id <ai_id> \
  --suggestion-id <s_id>
```

## create_suggestion.sh

```bash
create_suggestion.sh \
  --action-item-id <ai_id> \
  --created-by "agent:vuln-scanner" \
  --owner "executor:pr-creator" \
  [--confidence 0.95] \
  [--description "..."] \
  [--metadata '{"action_type":"...","..."}'] \
  [--user-metadata '{"target_branch":"main",...}'] \
  [--user-metadata-config '{"target_branch":{"label":"...","type":"string"}}'] \
  [--expires-at 2024-12-31T00:00:00Z]
```

**Validations**:
- `user_metadata` solo acepta scalars (string/number/boolean/null). Anidar objetos da 400.
- `created_by` y `owner` son requeridos.

## update_suggestion.sh

PATCH genérico para cualquier campo (incluido status). Para cambios de status preferir los scripts específicos.

```bash
update_suggestion.sh \
  --action-item-id <ai_id> \
  --suggestion-id <s_id> \
  [--description "..."] \
  [--metadata '{...}'] \
  [--user-metadata '{...}'] \
  [--confidence 0.85] \
  [--status approved|rejected|applied|failed] \
  [--execution-result '{"success":true,...}']
```

`user_metadata` se mergea (no resetea): mandar `{"key1":"new"}` solo cambia `key1`.

## approve_suggestion.sh

```bash
approve_suggestion.sh --action-item-id <ai_id> --suggestion-id <s_id>
```

Equivale a `PATCH ... {"status": "approved"}`. Solo válido desde `pending` o `failed`.

## reject_suggestion.sh

```bash
reject_suggestion.sh --action-item-id <ai_id> --suggestion-id <s_id>
```

Equivale a `PATCH ... {"status": "rejected"}`. Solo válido desde `pending`. Es terminal.

## mark_suggestion_applied.sh

```bash
mark_suggestion_applied.sh \
  --action-item-id <ai_id> \
  --suggestion-id <s_id> \
  --execution-result '{"success":true,"message":"PR #456 created","details":{"pr_url":"https://..."}}'
```

Solo válido desde `approved`. Es terminal. El executor lo llama después de ejecutar exitosamente.

## mark_suggestion_failed.sh

```bash
mark_suggestion_failed.sh \
  --action-item-id <ai_id> \
  --suggestion-id <s_id> \
  --execution-result '{"success":false,"message":"Tests failed","details":{"error":"3 tests failed"}}'
```

Solo válido desde `approved`. NO es terminal — se puede pasar a `approved` con `retry_suggestion.sh`.

## retry_suggestion.sh

```bash
retry_suggestion.sh \
  --action-item-id <ai_id> \
  --suggestion-id <s_id> \
  [--user-metadata '{"retry_attempt":"2"}']
```

Equivale a `PATCH ... {"status": "approved"}` desde `failed`. El user_metadata opcional permite ajustar parámetros para el retry.

## find_approved_suggestions.sh ⭐

Helper para executor agents: busca todas las suggestions en `approved` para un owner específico.

```bash
find_approved_suggestions.sh \
  --owner "executor:pr-creator" \
  --nrn "organization=1" \
  [--limit-action-items 100]
```

Output: array JSON de `[{action_item, suggestion}, ...]`. Hace paginación interna.

Algoritmo:
1. `GET /governance/action_item?nrn=...&status=open` (paginado)
2. Para cada action item, `GET /governance/action_item/:id/suggestions?status=approved&owner=...`
3. Acumula `{action_item, suggestion}` por cada match

## poll_approved_suggestions.sh ⭐

One-shot polling loop. Misma lógica que `find_approved_suggestions.sh` pero con output formatted para agentes que iteran.

```bash
poll_approved_suggestions.sh \
  --owner "executor:pr-creator" \
  --nrn "organization=1" \
  [--include-failed]
```

`--include-failed` también trae suggestions en `failed` que cumplan retry policy (default 3 intentos).

## check_action_item_hold.sh ⭐

Detecta si hay instrucciones humanas de hold/abort en los comentarios de un action item.

```bash
check_action_item_hold.sh --id <action_item_id>
```

Output JSON:
```json
{
  "should_proceed": false,
  "hold_reason": "user said 'do not execute'",
  "user_instructions": "do not execute, waiting for review",
  "comment_count": 5,
  "human_comment_count": 2
}
```

Keywords detectadas (case-insensitive): `abort`, `hold`, `do not execute`, `stop execution`, `cancel execution`, `skip this`, `do not apply`, `no ejecutar`, `detener`, `cancelar ejecucion`.

**Importante**: el script filtra solo comentarios humanos (excluye los de `executor:*` y `agent:*` que son auto-generated). Cualquier executor debe llamarlo **antes de ejecutar** para respetar instrucciones humanas.
