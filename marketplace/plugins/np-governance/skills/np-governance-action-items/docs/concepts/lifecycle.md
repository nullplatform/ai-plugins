# Lifecycle: Action Items

## Estados (enum)

| Status | Description |
|--------|-------------|
| `open` | Estado inicial, en progreso |
| `pending_deferral` | Esperando aprobación para diferir (cuando la policy del servicio de aprobaciones lo requiere) |
| `deferred` | Diferido hasta `deferred_until`. Se reabre automáticamente cuando vence |
| `pending_verification` | Esperando verificación antes de marcar resuelto (cuando la policy del servicio de aprobaciones lo requiere) |
| `resolved` | Resuelto exitosamente. Set `resolved_at`. Terminal |
| `pending_rejection` | Esperando aprobación para rechazar (cuando la policy del servicio de aprobaciones lo requiere) |
| `rejected` | Rechazado intencionalmente. Terminal |
| `closed` | Cerrado por su creador (el flujo equivalente a "ya no aplica"). Terminal |

## Transiciones válidas

```
                  ┌──────────────────────────────────────────┐
                  │                                          │
                  v                                          │
    ┌────────────────────────────┐                          │
    │  open                       │◄─── reopen ───┐          │
    └────┬───────┬────────┬───────┘                │          │
         │       │        │                        │          │
         v       v        v                        │          │
  pending_  pending_   pending_                deferred   rejected
  deferral  verif.    rejection                   │
     │         │           │
     v         v           v
  deferred  resolved   rejected
  (auto                          
   reopen)
                                  
                                          
                                          
```

### Detalle por flujo

Las transiciones se disparan **solo** con los endpoints POST de acción (`defer` / `reject` / `resolve` / `reopen` / `close`). Que un `defer` / `reject` / `resolve` requiera aprobación lo decide la **política de aprobaciones de la plataforma**, no la `config` del item. Cuando se requiere aprobación, la acción deja el item en el `pending_*` correspondiente y crea un pedido de aprobación; el servicio de aprobaciones de la plataforma completa el flujo por callback (llega con `reviewer: {email, name}` y, opcionalmente, `review_message`). Un agente/consumidor **no puede aprobar ni denegar** por esta API: solo puede consultar el status con `GET` y esperar.

En `defer` / `reject` / `resolve`, el campo opcional `category` (string libre 1-100) se registra únicamente en el audit log; no afecta la lógica de estado.

**Defer (request)**:
1. `POST /governance/action_item/:id/defer` con `{defer_until, reason?, category?, actor?}`. `defer_until` acepta formato `date` (`YYYY-MM-DD`) o `date-time`.
2. Si la policy de aprobaciones lo requiere → status pasa a `pending_deferral` y se crea el pedido de aprobación.
3. Si no → status pasa directo a `deferred`, set `deferred_until`, increment `deferral_count`. Si se dio `reason`, se persiste también como comment.
4. Validaciones: `config.max_deferral_count` y `config.max_deferral_days` (ambos vigentes) no pueden superarse.

**Defer (approval)**:
- Se completa por callback del servicio de aprobaciones (ver arriba).
- Aprobado → `deferred` (set `deferred_until`, increment `deferral_count`). Si el reviewer dejó `review_message`, queda como comment y en el audit.
- Denegado o cancelado → vuelve a `open` con un comment automático: el `review_message` del reviewer o, si no hay, un fallback fijo (`Deferral request was denied during approval.` / `Deferral request was withdrawn before approval.`).

**Auto-reopen de deferred**:
- Background job busca items con `status=deferred` y `deferred_until <= NOW()` y los pasa a `open` automáticamente (audit action `deferral_expired`).

**Resolve (request)**:
- `POST /governance/action_item/:id/resolve` con `{resolution?, evidence_url?, category?, actor?}` — sin campos requeridos; body estricto (claves extra → 400). `resolution` se persiste también como comment.
- Si la policy de aprobaciones lo requiere → `pending_verification`.
- Si no → `resolved` directo, set `resolved_at`.

**Resolve (approval)**:
- Se completa por callback (ver arriba).
- Aprobado → `resolved` (set `resolved_at`).
- Denegado o cancelado → vuelve a `open` con un comment automático (`review_message` del reviewer o el fallback de Resolution).

**Reject (request)**:
- `POST /governance/action_item/:id/reject` con `{reason, category?, actor?}` — **`reason` es requerido** (1-2000 chars) y se persiste como comment.
- Si la policy de aprobaciones lo requiere → `pending_rejection`.
- Si no → `rejected` directo.

**Reject (approval)**:
- Se completa por callback (ver arriba).
- Aprobado → `rejected`.
- Denegado o cancelado → vuelve a `open` con un comment automático (`review_message` del reviewer o el fallback de Rejection).

**Reopen** (manual):
- `POST /governance/action_item/:id/reopen` desde `rejected` o `deferred` → `open`. El body se ignora (salvo `actor`, que solo se honra para callers con delegación). Limpia `resolved_at` y `deferred_until`.

**Close**:
- `POST /governance/action_item/:id/close` con `{reason?}` desde `open` → `closed`. `reason` se registra en el audit log. Set `resolved_at`. Terminal.

### Cambios de status: solo vía endpoints de acción

Las transiciones de estado se hacen **exclusivamente** con los endpoints POST de acción de arriba. Cambiar `status` vía `PATCH` / `PUT` está reservado al servicio de aprobaciones y requiere la capability **`approval:bypass`**; un consumidor normal que intente una transición por `PATCH` / `PUT` recibe **403**. El claim `governance:action_item:update` alcanza para editar campos (`PATCH` / `PUT`) y agregar comentarios, pero **no** para cambiar el status.

## Estados terminales

`resolved`, `rejected`, `closed`. No se permite transición saliente excepto `reopen` (rejected/deferred → open).

## Audit log

Cada transición se registra automáticamente en `audit_logs`. Cada entrada incluye el `actor`, el `from`/`to` del status y, según el caso, `reason`, `category`, `resolution`, `evidence_url`, `deferred_until`, `review_message` o `comment`. En las entradas generadas por una aprobación, el `actor` es el **reviewer**. Ver el vocabulario completo de `action` en `model.md`.
