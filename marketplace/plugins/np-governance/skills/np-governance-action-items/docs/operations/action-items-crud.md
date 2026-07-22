# Action Items CRUD

Cómo usar los scripts CRUD del skill. Todos delegan a `np-api/scripts/fetch_np_api_url.sh` con `--method` y rutean a `/governance/action_item*`.

> **Identidad**: la API resuelve la identidad del actor a partir del token. Solo dos operaciones aceptan un override de identidad en el body, y solo para llamadores con derechos de delegación (un agente actuando en nombre de un usuario): `create_action_item.sh --created-by` y `add_comment.sh --author`. Las **transiciones** (`defer` / `reject` / `resolve` / `reopen` / `close`) **no** tienen canal de actor en el body: la identidad registrada es siempre la del token, sin excepción. Corré cada transición bajo el token cuya identidad querés que quede en el audit.

> **Aprobaciones**: que un `defer` / `reject` / `resolve` requiera aprobación lo decide la **policy del servicio de aprobaciones de la plataforma**, no la `config` del item. Cuando se requiere, el item queda en el `pending_*` correspondiente y esta API **no** aprueba ni deniega. El consumidor solo pollea el status con `GET`: si se aprueba pasa al estado final (`deferred` / `rejected` / `resolved`), si se deniega o cancela vuelve a `open` con un comment automático del reviewer.

## list_action_items.sh

Lista action items con filtros.

```bash
list_action_items.sh \
  --nrn "organization=1" \
  [--status open|deferred|...] \
  [--category-id <id>] \
  [--category-slug <slug>] \
  [--priority critical|high|medium|low] \
  [--created-by <agent_id>] \
  [--title <substring>] \
  [--metadata-key <key> --metadata-value <value>] \
  [--label-key <key> --label-value <value>] \
  [--due-date-before <iso8601>] \
  [--due-date-after <iso8601>] \
  [--min-value <num>] \
  [--max-value <num>] \
  [--offset <n>] \
  [--limit <n>] \
  [--order-by score|value|priority|createdAt|dueDate|status|category] \
  [--order ASC|DESC]
```

Default: `--order-by score --order DESC --limit 25`. Output: JSON con `{results, pagination}`.

`--title` hace match case-insensitive por substring del título. `--status` se puede repetir para filtrar por varios estados.

`--category-id` es directo (el list endpoint filtra por `category_id`). `--category-slug` **no** es un filtro del endpoint: el script resuelve el slug a un id client-side (1 request extra a `action_item_category`) antes de listar. Si pasás ambos, gana `--category-id`. `--order-by` fuera del allowlist (`score|value|priority|createdAt|dueDate|status|category`) da error de uso.

## get_action_item.sh

```bash
get_action_item.sh --id <action_item_id>
```

## search_action_items_by_metadata.sh ⭐

Helper de idempotency. Busca por un campo de `metadata`.

```bash
search_action_items_by_metadata.sh \
  --nrn "organization=1" \
  --metadata-key cve_id \
  --metadata-value "CVE-2024-1234" \
  [--statuses "open,deferred,pending_deferral,pending_verification"] \
  [--include-resolved]
```

Por default solo busca en estados "vivos". Pasar `--include-resolved` para incluir también `resolved`/`rejected`/`closed`.

## create_action_item.sh

```bash
create_action_item.sh \
  --nrn "organization=1:account=2" \
  --title "Critical: CVE-2024-1234 in lodash" \
  [--created-by "agent:vuln-scanner"] \
  (--category-id <id> | --category-slug <slug>) \
  [--description "..."] \
  [--priority critical|high|medium|low] \
  [--value 85] \
  [--due-date 2026-12-31] \
  [--metadata '{"cve_id":"CVE-2024-1234",...}'] \
  [--labels '{"team":"security","env":"prod"}'] \
  [--affected-resources '[{"type":"app","name":"api","permalink":"..."}]'] \
  [--references '[{"name":"CVE","permalink":"..."}]'] \
  [--config '{"max_deferral_days":90}']
```

`--due-date` acepta formato `YYYY-MM-DD` o date-time ISO8601; para deadlines de calendario preferir `date` (p.ej. `2026-12-31`).

## update_action_item.sh

PATCH parcial de **campos de datos**. Cualquier subset de campos. Las transiciones de estado **no** se hacen acá: usar los scripts de acción (`defer` / `resolve` / `reject` / `close` / `reopen`).

```bash
update_action_item.sh --id <id> \
  [--title "..."] \
  [--description "..."] \
  [--priority high] \
  [--value 100] \
  [--due-date 2026-12-31] \
  [--metadata '{"new_field":"value"}'] \
  [--labels '{"team":"new"}'] \
  [--affected-resources '[...]'] \
  [--references '[...]'] \
  [--config '{...}']
```

## defer_action_item.sh

```bash
defer_action_item.sh --id <id> \
  --until 2026-12-31 \
  [--reason "Waiting for vendor patch"] \
  [--category "Waiting on third party"]
```

`--until` es obligatorio y acepta `YYYY-MM-DD` o date-time ISO8601; en el wire viaja como `defer_until` (en la entidad, el campo de respuesta es `deferred_until`). `--category` (string libre 1-100) solo se registra en el audit log.

Si la policy del servicio de aprobaciones lo requiere, el item pasa a `pending_deferral`; si no, va directo a `deferred` (set `deferred_until`). Ver la nota de **Aprobaciones** al inicio.

## resolve_action_item.sh

```bash
resolve_action_item.sh --id <id> \
  [--resolution "Bumped lodash 4.17.19 → 4.17.21"] \
  [--evidence-url "https://github.com/org/repo/pull/456"] \
  [--category "Issue fixed"]
```

Todos los campos son opcionales. `--resolution` se persiste como comment y en el audit log; `--evidence-url` queda en el audit log; `--category` (string libre 1-100) solo en el audit log.

Si la policy del servicio de aprobaciones lo requiere → `pending_verification`; si no → `resolved` directo (set `resolved_at`). Ver la nota de **Aprobaciones** al inicio.

## reject_action_item.sh

```bash
reject_action_item.sh --id <id> \
  --reason "False positive after manual review" \
  [--category "False positive"]
```

`--reason` es **obligatorio** (1-2000 chars) — los rechazos deben justificarse; se persiste como comment. `--category` (string libre 1-100) solo se registra en el audit log.

Si la policy del servicio de aprobaciones lo requiere → `pending_rejection`; si no → `rejected`. Ver la nota de **Aprobaciones** al inicio.

## reopen_action_item.sh

```bash
reopen_action_item.sh --id <id>
```

Solo desde `rejected` o `deferred`. Vuelve a `open`, limpia `resolved_at` y `deferred_until`. La API ignora el body por completo; la identidad se resuelve del token (no hay canal de actor). Requiere el claim `governance:action_item:reopen`.

## close_action_item.sh

```bash
close_action_item.sh --id <id> \
  [--reason "Resource decommissioned"]
```

Cierra un item en `open`. Equivalente a "cancelled" / "no aplica más". `--reason` es opcional pero **recomendado** para trazabilidad: se registra en el audit log. Requiere el claim `governance:action_item:close`.

## list_comments.sh

```bash
list_comments.sh --id <action_item_id>
```

Output: array de `{id, author, content, created_at}`.

## add_comment.sh

```bash
add_comment.sh --id <action_item_id> \
  --content "## PR Created\n\nPR #456 created..." \
  [--author "executor:pr-creator"]
```

El content soporta markdown.

## list_audit_logs.sh

```bash
list_audit_logs.sh --id <action_item_id>
```

Output: array de `{id, action, actor, timestamp, details}`.

## reconcile_action_items.sh

Ver `reconciliation-howto.md` para detalle completo.

```bash
reconcile_action_items.sh \
  --nrn "organization=1" \
  --agent-id "agent:vuln-scanner" \
  --metadata-key cve_id \
  --problems-file ./current_vulns.json \
  [--dry-run]
```
