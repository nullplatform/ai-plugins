# Troubleshooting

## Auth errors (401/403)

### Síntoma
```
{"error":"Unauthorized"} or {"error":"Forbidden: missing claim governance:..."}
```

### Causa probable
1. `NP_API_KEY` o `NP_TOKEN` no configurado
2. Token expirado (NP_TOKEN tiene ~24h de vida)
3. Token sin claims `governance:*`
4. Token no tiene acceso al NRN del recurso

### Solución
```bash
# Verificar auth
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh

# Inspeccionar claims del JWT (si usás NP_TOKEN)
echo "$NP_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.permissions // .'

# Usar API key (no expira)
export NP_API_KEY='sk-...'
```

Para obtener los claims de governance, pedí al admin de tu organización los permisos listados en `concepts/permissions-matrix.md`.

### 403 al cambiar `status` por PATCH/PUT

Cambiar `status` vía `PATCH` / `PUT` está reservado al servicio de aprobaciones (requiere la capability interna `approval:bypass`). Un consumidor normal recibe **403**, aunque tenga `governance:action_item:update`. Las transiciones de estado se hacen con los scripts de acción: `defer_action_item.sh` / `resolve_action_item.sh` / `reject_action_item.sh` / `close_action_item.sh` / `reopen_action_item.sh`.

### 403 en reopen / close

`reopen` y `close` requieren sus propios claims: `governance:action_item:reopen` y `governance:action_item:close`. El claim `governance:action_item:update` ya **no** alcanza para estas transiciones (solo sirve para editar campos de datos y agregar comentarios). Ver `concepts/permissions-matrix.md`.

---

## Endpoint not found (404)

### Síntoma
```
{"error":"Not Found"} on /governance/action_item
```

### Causas probables

**A. El gateway aún no rutea `/governance/*`**: el deploy puede no estar completo en `api.nullplatform.com`.

Verificar con:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/fetch_np_api_url.sh "/governance/action_item?limit=1"
```

Si retorna `404 Not Found` consistentemente en `/governance/*` pero otros endpoints de `api.nullplatform.com` responden OK, el gateway todavía no deployó el ruteo para governance. Esperar el deploy o escalar al equipo. **No intentar apuntar a backends internos** — todas las llamadas deben pasar por `api.nullplatform.com` vía `np-api/scripts/fetch_np_api_url.sh`.

**B. El action item no existe**: 404 en GET de un id específico significa que el id es inválido o el item fue borrado.

**C. Categoría no encontrada al crear**: si pasás `--category-slug` y la categoría no existe en el NRN. Solución: crear con `ensure_category.sh` antes.

**D. `/action_item/:id/approve` o `/deny` devuelven 404**: esos endpoints no existen en esta API. El flujo de aprobación lo completa el **servicio de aprobaciones de la plataforma** vía callback; esta API no expone approve/deny. Un consumidor solo pollea el status con `GET`. Ver `concepts/lifecycle.md`.

---

## Validation errors (400)

### Síntoma
```
{"error":"Validation failed: <field>"}
```

### Casos comunes

**Reject sin `reason`**:
```
"error":"Validation failed: reason"
```

`reason` es **obligatorio** al rechazar. Pasarlo siempre: `reject_action_item.sh --id <id> --reason "<justificación>"`. Un reject sin `reason` devuelve 400.

**`user_metadata` con tipos no escalares**:
```
"error":"user_metadata.changes: must be string, number, boolean or null"
```

Mover el campo a `metadata` (que sí acepta objetos/arrays).

**NRN inválido**:
```
"error":"Invalid NRN format"
```

NRN debe seguir el patrón `organization=N[:account=N[:namespace=N[:application=N]]]`.

**Categoría con parent inválido**:
```
"error":"parent category cannot have a parent (max 2 levels)"
```

La jerarquía es máximo 2 niveles. El parent que pasás ya tiene un parent.

**Affected resources > 50**:
```
"error":"affected_resources: maximum 50 items allowed"
```

Agrupar resources si tenés más de 50.

---

## Conflict (409) al crear

### Síntoma
```
{"error":"category with this name already exists in this NRN"}
```

### Causa
Restricción `UNIQUE(name, nrn)` en categorías.

### Solución
Usar `ensure_category.sh` en lugar de `create_category.sh` directo. Search-or-create.

---

## Lifecycle errors

### "Cannot transition from <state> to <state>"

Las transiciones están restringidas. Ver `concepts/lifecycle.md`. Ejemplos válidos:
- `open → resolved` ✓
- `deferred → open` (via reopen) ✓
- `resolved → open` ✗ (terminal — crear un item nuevo)
- `closed → open` ✗ (terminal)

### "Cannot defer: max_deferral_count reached"

La categoría tiene `max_deferral_count` y el item ya alcanzó el límite. No se puede diferir más. Resolver o rechazar.

### "Cannot defer: deferral period exceeds max_deferral_days"

La fecha `--until` está más lejos de lo permitido por la categoría. Ajustar la fecha o pedir al admin que cambie el config de la categoría.

---

## Item "atascado" en `pending_*`

### Síntoma

Un item quedó en `pending_deferral` / `pending_verification` / `pending_rejection` y no avanza.

### Causa

Hay un pedido de aprobación pendiente en el **servicio de aprobaciones de la plataforma**. La transición (`deferred` / `resolved` / `rejected`) se completa cuando el reviewer aprueba o deniega, vía callback — no la dispara esta API.

### Solución

Esta API no destraba el item: no existen endpoints approve/deny acá. Pollear el status con `get_action_item.sh` y esperar el desenlace:
- **Aprobado** → estado final (`deferred` / `resolved` / `rejected`).
- **Denegado o cancelado** → vuelve a `open` con un comment automático del reviewer.

---

## Suggestion lifecycle errors

### "Cannot approve: suggestion is in <state>"

Solo se puede aprobar desde `pending` o `failed`. Si está en `applied`/`rejected`/`expired`, ya es terminal — no se puede cambiar.

### "user_metadata is locked in <state>"

`user_metadata` solo es editable en `pending` y `failed`. En `approved`/terminales no se puede cambiar.

### "execution_result is required for status applied|failed"

Cuando reportás `applied` o `failed`, el `execution_result` (JSON con `success`, `message`, `details`) es obligatorio. Pasarlo con `--execution-result`.

---

## Performance

### "GET /governance/action_item is slow"

Posibles causas:
- Querys sin filtrar por NRN (escanea toda la org)
- `limit` muy alto (max recomendado: 100)
- Filtros sobre `metadata.*` sin índice (depende del deployment)

Soluciones:
- Siempre filtrar por NRN específico
- Usar paginación (`offset` + `limit`)
- Filtrar por `status` (default solo trae activos)

---

## Reconciliation issues

### "Closed items reappear after next scan"

Si auto-cerraste un item y el scanner lo vuelve a detectar en el siguiente run, vas a crear un item nuevo (no reabrir el viejo, esa es la convención). Si estás creando duplicados:

1. Verificá que el `metadata-key` realmente identifique unívocamente el problema (no usar timestamps, IDs random, etc.)
2. Usá `--dry-run` para ver qué decisiones toma el reconciler

### "Auto-closed an item I deferred"

Bug. El reconciler debe respetar `deferred` (y `pending_*`). Verificar que:
- El item tiene `created_by` igual al `--agent-id`
- El search del reconciler incluye `deferred` en los estados vivos (debería por default)

Reportar al equipo si pasa.

