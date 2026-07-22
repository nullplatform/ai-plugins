# `metadata` vs `user_metadata` vs `user_metadata_config`

Tres campos JSON con propósitos distintos en suggestions (y solo `metadata` en action items).

## Comparación

| Field | Who writes | Who reads | Structure | Editable when |
|-------|-----------|-----------|-----------|---------------|
| `metadata` | Detector agent | Executor agent | Free-form (puede anidar objetos y arrays) | Always (PATCH sin status) |
| `user_metadata` | Human user | Executor agent | **Flat** key/value (solo `string`/`number`/`boolean`/`null`) | Solo `pending` y `failed` |
| `user_metadata_config` | Detector agent | UI (forms) | **JSON Schema** (`type: object` + `properties` en la raíz) que describe `user_metadata` | Always |

## `metadata`

Datos técnicos que el executor agent necesita para realizar la acción. Es **free-form**: puede contener objetos anidados, arrays, cualquier estructura. El user humano normalmente no edita esto.

```json
{
  "metadata": {
    "action_type": "dependency_upgrade",
    "package_manager": "npm",
    "changes": [
      {
        "file": "package.json",
        "operation": "update_dependency",
        "package": "lodash",
        "from_version": "^4.17.19",
        "to_version": "^4.17.21"
      }
    ],
    "auto_merge": false,
    "estimated_effort": "5 minutes",
    "rollback_procedure": "Revert PR and run npm install"
  }
}
```

El executor lee `metadata.action_type` para enrutar a la lógica correcta y luego usa los demás campos como input.

## `user_metadata`

Parámetros que el **usuario humano** puede ajustar **antes de aprobar** la suggestion (o antes de retry-approving una failed). Reglas estrictas:

| Rule | Detail |
|------|--------|
| Escalares o arrays de escalares | Valores `string`, `number`, `boolean`, `null`, o arrays de esos. **NO** objetos anidados |
| Flat | No keys nested. Solo un nivel de profundidad |
| Editable solo en `pending`/`failed` | En `approved`/`applied`/`rejected`/`expired` está locked |
| Merge o replace según el request | Un PATCH **con** `status` mergea (solo cambia las claves que mandes); un PATCH **sin** `status` **reemplaza** el campo completo. Ver `operations/suggestions-crud.md` |

```json
{
  "user_metadata": {
    "target_branch": "main",
    "auto_merge": "false",
    "reviewer": "team-lead",
    "skip_ci": "false",
    "priority_label": "P1"
  }
}
```

El executor lee `user_metadata` cuando ejecuta para ajustar su comportamiento:
```javascript
const targetBranch = suggestion.user_metadata?.target_branch || 'main';
const autoMerge = suggestion.user_metadata?.auto_merge === 'true';  // string→bool
```

**Anti-patrón**: meter objetos anidados en `user_metadata`. La API lo rechaza con 400 (arrays de escalares sí se aceptan). Nota: esta validación se aplica en el PATCH sin `status`; el create de la suggestion no la valida.

## `user_metadata_config`

Schema opcional que describe `user_metadata` para que la UI renderice un form. **Es un JSON Schema plano** (`type: object` con `properties` en la raíz) — la UI de action items (admin-dashboard `SuggestionCard`) lo pasa DIRECTO a `DynamicForm` (JSONForms).

**Reglas verificadas contra la UI real (2026-07-20):**

1. **El form solo se renderiza si `user_metadata` tiene claves.** El gate es `hasUserMetadata` — un config perfecto con `user_metadata: {}` no muestra NADA. Por eso el detector debe **seedear `user_metadata` con los defaults** al crear la suggestion (el humano los ajusta antes de aprobar; el executor lee los valores finales).
2. **El schema va en la raíz, sin wrappers.** Un `{"schema": {...}}` anidado se ignora y la UI degrada a un auto-schema plano generado desde los values (pierde labels, enums y descripciones).
3. **Enums con labels humanos: `oneOf` con `const` + `title`.** JSONForms (`isOneOfEnumSchema`) muestra el `title` y guarda el `const` — el executor sigue leyendo valores machine-readable.
4. **Cuidado con `pattern` en campos opcionales**: un string vacío seedeado que no matchea el pattern deja el form en error y bloquea el save. Preferir describir el formato en `description`.
5. **`description` de la suggestion es MARKDOWN**: la UI la renderiza con ReactMarkdown — estructurarla (negritas, listas numeradas), un párrafo corrido se lee pésimo.

```json
{
  "user_metadata_config": {
    "type": "object",
    "properties": {
      "deploy_timing": {
        "type": "string",
        "title": "How to apply",
        "oneOf": [
          { "const": "next-deploy", "title": "Apply only — ships with the next regular deploy" },
          { "const": "now", "title": "Deploy now" },
          { "const": "scheduled", "title": "Schedule the deploy" }
        ],
        "default": "next-deploy"
      },
      "deploy_at": {
        "type": "string",
        "title": "Scheduled deploy time — optional (HH:MM)",
        "description": "Only used with Schedule. Empty = tonight's window."
      }
    }
  }
}
```

| Propiedad JSON Schema | Soporte UI | Nota |
|---|---|---|
| `title` | ✅ | Label del campo |
| `description` | ✅ | Ayuda/tooltip |
| `enum` | ✅ | Dropdown con los valores crudos |
| `oneOf` const+title | ✅ | Dropdown con labels humanos (preferido) |
| `default` | Informativo | NO se aplica solo — seedear el valor en `user_metadata` |
| `pattern` | ⚠️ | Valida en vivo; rompe con seeds vacíos |

## Ejemplo combinado

```json
POST /governance/action_item/abc/suggestions
{
  "created_by": "agent:vuln-scanner",
  "owner": "executor:pr-creator",
  "confidence": 0.95,
  "description": "Upgrade lodash to fix CVE-2024-1234",

  "metadata": {
    "action_type": "dependency_upgrade",
    "changes": [
      {"file": "package.json", "from": "4.17.19", "to": "4.17.21"}
    ]
  },

  "user_metadata": {
    "target_branch": "main",
    "auto_merge": "false",
    "reviewer": "team-lead"
  },

  "user_metadata_config": {
    "type": "object",
    "properties": {
      "target_branch": {"type": "string", "title": "Target Branch", "default": "main"},
      "auto_merge": {"type": "boolean", "title": "Auto Merge", "default": false},
      "reviewer": {"type": "string", "title": "Reviewer"}
    }
  }
}
```

Flujo:
1. Detector crea con los 3 fields — `user_metadata` YA seedeado con los defaults (si va vacío, la UI no muestra el form).
2. UI renderiza form con los 3 campos editables (porque está en `pending`).
3. User cambia `target_branch` a `develop` y aprueba.
4. PATCH `{"user_metadata": {"target_branch": "develop"}}` (no resetea los demás).
5. PATCH `{"status": "approved"}` (el `user_metadata` queda locked desde acá).
6. Executor lee `user_metadata.target_branch === "develop"` y crea el PR en esa branch.
