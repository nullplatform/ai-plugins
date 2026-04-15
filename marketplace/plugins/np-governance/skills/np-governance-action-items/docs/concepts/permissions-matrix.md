# Permissions Matrix

Los endpoints de governance requieren claims JWT específicos en el token. Si el token no tiene el claim, el endpoint responde 401/403.

## Claims requeridos

### Action items

| Claim | Required for |
|-------|--------------|
| `governance:action_item:list` | `GET /governance/action_item` |
| `governance:action_item:read` | `GET /governance/action_item/:id`, `GET /:id/comments`, `GET /:id/audit-logs`, `GET /:id/suggestions` |
| `governance:action_item:create` | `POST /governance/action_item`, `POST /:id/comments` |
| `governance:action_item:update` | `PATCH /:id`, `PUT /:id`, `POST /:id/comments`, `POST /:id/reopen`, `POST /:id/close` |
| `governance:action_item:delete` | `DELETE /:id` |
| `governance:action_item:defer` | `POST /:id/defer` |
| `governance:action_item:reject` | `POST /:id/reject` |
| `governance:action_item:resolve` | `POST /:id/resolve` |
| `governance:action_item:approve` | `POST /:id/approve`, `POST /:id/deny` (para pending_*) |

### Suggestions

| Claim | Required for |
|-------|--------------|
| `governance:action_item:suggestion:create` | `POST /governance/action_item/:id/suggestions` |
| `governance:action_item:suggestion:update` | `PATCH /:id/suggestions/:sId` (incluye approve/reject/applied/failed) |
| `governance:action_item:suggestion:delete` | `DELETE /:id/suggestions/:sId` |
| `governance:action_item:suggestion:approve` | `POST /:id/suggestions/:sId/approve` |
| `governance:action_item:suggestion:reject` | `POST /:id/suggestions/:sId/reject` |
| `governance:action_item:suggestion:execute` | `POST /:id/suggestions/:sId/execute` (alternativa al PATCH) |

### Categories

| Claim | Required for |
|-------|--------------|
| `governance:action_item:category:list` | `GET /governance/action_item_category` |
| `governance:action_item:category:read` | `GET /governance/action_item_category/:id` |
| `governance:action_item:category:create` | `POST /governance/action_item_category` |
| `governance:action_item:category:update` | `PATCH /:id`, `PUT /:id` |
| `governance:action_item:category:delete` | `DELETE /:id` |

## Permisos mínimos por rol

### Detector agent (read + create + comment)

```yaml
- governance:action_item:list
- governance:action_item:read
- governance:action_item:create
- governance:action_item:update           # para agregar comentarios
- governance:action_item:resolve          # para auto-resolver en reconciliation
- governance:action_item:suggestion:create
- governance:action_item:category:list
- governance:action_item:category:create  # opcional, si auto-crea categorías
```

### Executor agent (read + update suggestions + comment)

```yaml
- governance:action_item:list
- governance:action_item:read
- governance:action_item:update                 # para comentarios y status
- governance:action_item:suggestion:update      # para applied/failed
- governance:action_item:resolve                # para cerrar items resueltos
```

### Operator humano (full)

```yaml
- governance:action_item:*
- governance:action_item:suggestion:*
- governance:action_item:category:*
```

## Cómo verificar tus claims

Si una llamada falla con 401/403, primero verificá tu auth:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh
```

Para inspeccionar los claims del token actual, decodificá el JWT (la parte del medio):

```bash
echo "$NP_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.permissions // .claims // .'
```

Si tu token no tiene los claims `governance:*`, pedile al admin de tu organización que los agregue al rol del API key o user.

## NRN-based authorization

Los claims son por sí solos no suficientes — además de tener el claim, el token debe tener acceso al **NRN** del action item. Ej: para listar items de `organization=1:account=2`, el token tiene que tener acceso a ese NRN o un ancestor.

El NRN se valida en cada request:
- En GETs viene como query param `?nrn=...`
- En POSTs viene en el body `{"nrn": "..."}`
- En PATCH/DELETE el sistema lee el NRN del recurso que se está modificando
