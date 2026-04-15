# Action Items CRUD

Cómo usar los scripts CRUD del skill. Todos delegan a `np-api/scripts/fetch_np_api_url.sh` con `--method` y rutean a `/governance/action_item*`.

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
  [--metadata-key <key> --metadata-value <value>] \
  [--label-key <key> --label-value <value>] \
  [--due-date-before <iso8601>] \
  [--due-date-after <iso8601>] \
  [--min-value <num>] \
  [--max-value <num>] \
  [--offset <n>] \
  [--limit <n>] \
  [--order-by score|value|priority|createdAt|dueDate] \
  [--order ASC|DESC]
```

Default: `--order-by score --order DESC --limit 25`. Output: JSON con `{results, pagination}`.

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
  --created-by "agent:vuln-scanner" \
  (--category-id <id> | --category-slug <slug>) \
  [--description "..."] \
  [--priority critical|high|medium|low] \
  [--value 85] \
  [--due-date 2024-12-31T00:00:00Z] \
  [--metadata '{"cve_id":"CVE-2024-1234",...}'] \
  [--labels '{"team":"security","env":"prod"}'] \
  [--affected-resources '[{"type":"app","name":"api","permalink":"..."}]'] \
  [--references '[{"name":"CVE","permalink":"..."}]'] \
  [--config '{"requires_verification":true}']
```

## update_action_item.sh

PATCH parcial. Cualquier subset de campos.

```bash
update_action_item.sh --id <id> \
  [--title "..."] \
  [--description "..."] \
  [--priority high] \
  [--value 100] \
  [--metadata '{"new_field":"value"}'] \
  [--labels '{"team":"new"}']
```

## defer_action_item.sh

```bash
defer_action_item.sh --id <id> \
  --until 2024-12-31T00:00:00Z \
  --actor "agent:my-agent" \
  [--reason "Waiting for vendor patch"]
```

Si la categoría tiene `requires_approval_to_defer=true`, pasa a `pending_deferral`. Si no, directo a `deferred`.

## resolve_action_item.sh

```bash
resolve_action_item.sh --id <id> --actor "agent:my-agent"
```

Si `requires_verification=true` → `pending_verification`. Si no → `resolved` directo.

## reject_action_item.sh

```bash
reject_action_item.sh --id <id> --actor "user@example.com" --reason "False positive after manual review"
```

Si `requires_approval_to_reject=true` → `pending_rejection`. Si no → `rejected`.

## reopen_action_item.sh

```bash
reopen_action_item.sh --id <id> --actor "agent:my-agent"
```

Solo desde `rejected` o `deferred`. Vuelve a `open`, limpia `resolved_at` y `deferred_until`.

## close_action_item.sh

```bash
close_action_item.sh --id <id> --actor "user@example.com"
```

Cierra un item en `open`. Equivalente a "cancelled" / "no aplica más".

## list_comments.sh

```bash
list_comments.sh --id <action_item_id>
```

Output: array de `{id, author, content, created_at}`.

## add_comment.sh

```bash
add_comment.sh --id <action_item_id> \
  --author "executor:pr-creator" \
  --content "## PR Created\n\nPR #456 created..."
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
