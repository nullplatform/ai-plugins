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

---

## Validation errors (400)

### Síntoma
```
{"error":"Validation failed: <field>"}
```

### Casos comunes

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

### "Resolved items reappear after next scan"

Si auto-resolviste un item y el scanner lo vuelve a detectar en el siguiente run, vas a crear un item nuevo (no reabrir el viejo, esa es la convención). Si estás creando duplicados:

1. Verificá que el `metadata-key` realmente identifique unívocamente el problema (no usar timestamps, IDs random, etc.)
2. Usá `--dry-run` para ver qué decisiones toma el reconciler

### "Auto-resolved an item I deferred"

Bug. El reconciler debe respetar `deferred`. Verificar que:
- El item tiene `created_by` igual al `--agent-id`
- El `--statuses` del search incluye `deferred` (debería por default)

Reportar al equipo si pasa.

