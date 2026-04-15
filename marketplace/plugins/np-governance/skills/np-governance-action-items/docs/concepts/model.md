# Data Model

## ActionItem

Representa un problema, oportunidad o acción pendiente detectado en un sistema.

### Campos obligatorios

| Field | Type | Description |
|-------|------|-------------|
| `nrn` | string | NRN del recurso afectado (define ownership y permisos) |
| `title` | string | Título corto descriptivo (max 200 chars) |
| `category_id` o `category_slug` | string | ID o slug de la categoría (requerido al crear) |
| `created_by` | string | Identificador del creador (ej: `agent:vuln-scanner`, email humano) |

### Campos recomendados

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Descripción detallada en markdown (max 10000) |
| `priority` | enum | `critical` / `high` / `medium` / `low` (default: medium) |
| `value` | number | Beneficio/ahorro estimado en la unidad de la categoría |
| `metadata` | object | **Critical**: datos para identificación e idempotency (free-form, puede anidar) |
| `affected_resources` | array | Recursos afectados (max 50): `[{type, name, permalink, description}]` |
| `references` | array | Links a docs/PRs (max 20): `[{name, permalink, description}]` |
| `labels` | object | Key-value flat para clasificación: `{team: "platform", env: "prod"}` |
| `due_date` | ISO8601 | Fecha límite |
| `config` | object | Override de la config heredada de la categoría |

### Campos read-only (set por el sistema)

| Field | Description |
|-------|-------------|
| `id` | nanoid de 12 chars |
| `slug` | slug único generado desde el title |
| `status` | Estado actual (ver `lifecycle.md`) |
| `score` | Calculado: `value * priorityWeight` (LOW=1, MEDIUM=2, HIGH=3, CRITICAL=4) |
| `deferred_until` | Set cuando status=deferred |
| `resolved_at` | Set cuando status=resolved/rejected/closed |
| `comments` | Array de `{id, author, content, created_at}` |
| `audit_logs` | Array de `{id, action, actor, timestamp, details}` |
| `deferral_count` | Cantidad de veces diferido |
| `created_at`, `updated_at` | Timestamps |

### `config` schema

```json
{
  "requires_verification": false,
  "requires_approval_to_defer": false,
  "requires_approval_to_reject": false,
  "max_deferral_days": null,
  "max_deferral_count": null
}
```

Si está null en el action item, hereda del category.config. El override permite que un item específico tenga config diferente al de su categoría.

---

## Category

Clasifica action items y define defaults de comportamiento.

### Campos obligatorios

| Field | Type | Description |
|-------|------|-------------|
| `nrn` | string | NRN de scope donde vive la categoría |
| `name` | string | Nombre legible (ej "Security Vulnerability") |

### Campos opcionales

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Descripción (max 2000) |
| `parent_id` | string | FK a otra category (jerarquía max 2 niveles) |
| `color` | string | Hex color para UI (ej `#DC2626`) |
| `icon` | string | Nombre del ícono (ej `shield`) |
| `unit_name` | string | Nombre de la unidad de valor (ej "Risk Score") |
| `unit_symbol` | string | Símbolo (`$`, `R`, `ms`) |
| `config` | object | Defaults para action items de esta categoría (ver schema arriba) |

### Read-only

| Field | Description |
|-------|-------------|
| `id` | nanoid 12 chars |
| `slug` | Slug único derivado del name |
| `status` | `active` / `inactive` |
| `created_at`, `updated_at` | Timestamps |

### Restricciones

- **Unique(name, nrn)**: no se puede crear dos categorías con el mismo nombre en el mismo NRN.
- **Jerarquía max 2 niveles**: una category puede tener un `parent_id`, pero ese parent NO puede tener parent (validado al crear).
- **No se puede borrar** si tiene action items asociados o tiene children.

---

## Suggestion

Propuesta automática de solución para un action item. Tiene su propio lifecycle (ver `suggestions.md`).

### Campos obligatorios

| Field | Type | Description |
|-------|------|-------------|
| `created_by` | string | Identificador del agente detector (ej `agent:vuln-scanner`) |
| `owner` | string | Identificador del executor que la procesará (ej `executor:pr-creator`) |

### Campos opcionales

| Field | Type | Description |
|-------|------|-------------|
| `confidence` | number | Score 0.0–1.0 (ver `confidence-levels.md`) |
| `description` | string | Explicación legible en markdown |
| `metadata` | object | Datos técnicos para el executor (free-form, puede anidar) |
| `user_metadata` | object | Key-value flat editable por humanos (solo escalares — ver `metadata-vs-user-metadata.md`) |
| `user_metadata_config` | object | Schema que describe cada key de `user_metadata` para forms en UI |
| `expires_at` | ISO8601 | Cuándo expira si no se actúa |

### Read-only

| Field | Description |
|-------|-------------|
| `id`, `slug` | Identificadores |
| `status` | `pending` / `approved` / `applied` / `failed` / `rejected` / `expired` |
| `executed_at` | Timestamp de cuándo fue ejecutada |
| `execution_result` | `{success, message, details}` reportado por el executor |
| `created_at`, `updated_at` | Timestamps |

---

## Comment

```json
{
  "id": "uuid",
  "author": "string (max 200)",
  "content": "string (max 5000)",
  "created_at": "ISO8601"
}
```

Cada cambio de status de action item o suggestion genera **automáticamente** un comment con el actor y la transición. Los agentes también pueden agregar comments manualmente para progreso o contexto.

---

## AuditLog

```json
{
  "id": "uuid",
  "action": "created|updated|deferred|resolved|rejected|...",
  "actor": "string",
  "timestamp": "ISO8601",
  "details": { /* contexto del cambio */ }
}
```

Solo legible vía `GET /governance/action_item/:id/audit-logs`. No editable.
