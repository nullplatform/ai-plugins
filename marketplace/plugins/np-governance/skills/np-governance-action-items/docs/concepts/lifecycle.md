# Lifecycle: Action Items

## Estados (enum)

| Status | Description |
|--------|-------------|
| `open` | Estado inicial, en progreso |
| `pending_deferral` | Esperando aprobación humana para diferir (si `config.requires_approval_to_defer=true`) |
| `deferred` | Diferido hasta `deferred_until`. Se reabre automáticamente cuando vence |
| `pending_verification` | Esperando verificación antes de marcar resuelto (si `config.requires_verification=true`) |
| `resolved` | Resuelto exitosamente. Set `resolved_at`. Terminal |
| `pending_rejection` | Esperando aprobación para rechazar (si `config.requires_approval_to_reject=true`) |
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

**Defer (request)**:
1. `POST /governance/action_item/:id/defer` con `{until, reason, actor}`.
2. Si `config.requires_approval_to_defer = true` → status pasa a `pending_deferral`.
3. Si no → status pasa directo a `deferred`, set `deferred_until`, increment `deferral_count`.
4. Validaciones: `max_deferral_count` y `max_deferral_days` no pueden superarse.

**Defer (approval)**:
- `POST /governance/action_item/:id/approve` con `{actor}` mientras está en `pending_deferral` → pasa a `deferred`.
- `POST /governance/action_item/:id/deny` con `{actor, comment}` → vuelve a `open`.

**Auto-reopen de deferred**:
- Background job busca items con `status=deferred` y `deferred_until <= NOW()` y los pasa a `open` automáticamente.

**Resolve (request)**:
- `POST /governance/action_item/:id/resolve` con `{actor}`.
- Si `config.requires_verification = true` → `pending_verification`.
- Si no → `resolved` directo, set `resolved_at`.

**Resolve (approval)**:
- `POST /.../approve` mientras está en `pending_verification` → `resolved`.
- `POST /.../deny` → vuelve a `open`.

**Reject (request)**:
- `POST /governance/action_item/:id/reject` con `{reason, actor}`.
- Si `config.requires_approval_to_reject = true` → `pending_rejection`.
- Si no → `rejected` directo.

**Reject (approval)**:
- `POST /.../approve` mientras está en `pending_rejection` → `rejected`.
- `POST /.../deny` → vuelve a `open`.

**Reopen** (manual):
- `POST /governance/action_item/:id/reopen` con `{actor}` desde `rejected` o `deferred` → `open`. Limpia `resolved_at` y `deferred_until`.

**Close**:
- `POST /governance/action_item/:id/close` con `{actor}` desde `open` → `closed`. Set `resolved_at`. Terminal.

### Cambios via PATCH directo

`PATCH /governance/action_item/:id` con `{status: "..."}` también funciona para transiciones simples (sin pasar por los endpoints de lifecycle), pero **no respeta `config.requires_*`**. Preferir los endpoints específicos cuando hay aprobaciones de por medio.

Ejemplo válido para agentes que verifican externamente:
```json
PATCH /governance/action_item/abc123
{
  "status": "resolved",
  "actor": "agent:vuln-scanner"
}
```

## Estados terminales

`resolved`, `rejected`, `closed`. No se permite transición saliente excepto `reopen` (rejected/deferred → open).

## Audit log

Cada transición se registra automáticamente en `audit_logs`. Los detalles incluyen el actor, el `from`/`to` del status, y la razón si fue provista.
