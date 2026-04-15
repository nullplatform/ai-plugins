# `metadata` vs `user_metadata` vs `user_metadata_config`

Tres campos JSON con propósitos distintos en suggestions (y solo `metadata` en action items).

## Comparación

| Field | Who writes | Who reads | Structure | Editable when |
|-------|-----------|-----------|-----------|---------------|
| `metadata` | Detector agent | Executor agent | Free-form (puede anidar objetos y arrays) | Always (PATCH sin status) |
| `user_metadata` | Human user | Executor agent | **Flat** key/value (solo `string`/`number`/`boolean`/`null`) | Solo `pending` y `failed` |
| `user_metadata_config` | Detector agent | UI (forms) | Schema descriptivo de cada key de `user_metadata` | Always |

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
| Solo escalares | `string`, `number`, `boolean`, `null`. **NO** objects, NO arrays |
| Flat | No keys nested. Solo un nivel de profundidad |
| Editable solo en `pending`/`failed` | En `approved`/`applied`/`rejected`/`expired` está locked |
| Merge no replace | PATCH con `{"user_metadata": {"key1": "new"}}` solo cambia `key1`, no resetea el resto |

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

**Anti-patrón**: meter objetos o arrays en `user_metadata`. La API lo rechaza con 400.

## `user_metadata_config`

Schema descriptivo opcional que describe **cada key** de `user_metadata`. Permite a las UIs renderizar forms con labels, descripciones, types, defaults.

```json
{
  "user_metadata_config": {
    "target_branch": {
      "label": "Target Branch",
      "description": "Branch where the fix PR will be created",
      "type": "string",
      "default": "main"
    },
    "auto_merge": {
      "label": "Auto Merge",
      "description": "Auto-merge the PR after CI passes",
      "type": "boolean",
      "default": "false"
    },
    "reviewer": {
      "label": "Reviewer",
      "description": "GitHub username to request review from",
      "type": "string",
      "default": "team-lead"
    }
  }
}
```

| Field per key | Type | Required | Description |
|---------------|------|----------|-------------|
| `label` | string | Yes | Human-readable label |
| `description` | string | No | Tooltip / explanation |
| `type` | string | No | One of `"string"`, `"number"`, `"boolean"` (informational, para UI hints) |
| `default` | scalar | No | Default suggested (informational, NO se aplica automáticamente) |

**Reglas**:
- Es opcional. Si no se manda, `user_metadata` funciona igual.
- Las UIs usan `type` para renderizar inputs apropiados (checkbox para boolean, etc.).
- `default` es solo informativo: la UI puede mostrarlo como placeholder, pero NO se aplica automáticamente. El user tiene que escribirlo.

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
    "target_branch": {"label": "Target Branch", "type": "string", "default": "main"},
    "auto_merge": {"label": "Auto Merge", "type": "boolean", "default": "false"},
    "reviewer": {"label": "Reviewer", "type": "string"}
  }
}
```

Flujo:
1. Detector crea con los 3 fields.
2. UI renderiza form con los 3 campos editables (porque está en `pending`).
3. User cambia `target_branch` a `develop` y aprueba.
4. PATCH `{"user_metadata": {"target_branch": "develop"}}` (no resetea los demás).
5. PATCH `{"status": "approved"}` (el `user_metadata` queda locked desde acá).
6. Executor lee `user_metadata.target_branch === "develop"` y crea el PR en esa branch.
