# Wizard Flow

El wizard usa `AskUserQuestion` en 5 batches. Max 4 preguntas por batch. Después de cada batch, **siempre** actualizar el state file (`.claude/state/agent-<name>.md`).

## Batch 1 — Identidad

| # | Question | Header | Type | Options |
|---|----------|--------|------|---------|
| 1 | "¿Nombre del agente? (slug kebab-case, ej `vuln-scanner`, `cost-rightsizer`)" | Agent name | open text (single) | — |
| 2 | "¿Qué tipo de agente?" | Agent type | single | `Detector only` / `Executor only` / `Both (Recommended)` / `Reconciler-only` |
| 3 | "¿Qué problema detecta o resuelve? (1-2 líneas)" | Problem | open text (single) | — |
| 4 | "¿Dominio funcional?" | Domain | single | `Security` / `Cost optimization` / `Performance` / `Reliability` / `Compliance` / `Technical debt` |

**Validación post-batch**:
- El nombre debe ser kebab-case (`[a-z][a-z0-9-]*`). Si no, repreguntar.
- Verificar que `.claude/skills/np-governance-agent-<name>/` no exista en el proyecto del usuario. Si ya existe, ofrecer overwrite o pick otro nombre.

**State file update**: `## Identity` section (name, type, problem, domain).

## Batch 2 — Categoría

| # | Question | Header | Type | Options |
|---|----------|--------|------|---------|
| 1 | "¿Crear categoría nueva o usar existente?" | Category strategy | single | `Create new (Recommended)` / `Use existing by slug` |
| 2 | "Slug de la categoría (ej `security-vulnerability`, `cost-optimization`)" | Category slug | open text (single) | — |
| 3 | "Símbolo de la unidad de valor (`$`, `R`, `ms`, `%`, `h`)" | Unit symbol | open text (single) | — |
| 4 | "Configuración de la categoría (multi-select)" | Category config | multiSelect | `requires_verification` / `requires_approval_to_reject` / `requires_approval_to_defer` / `max_deferral_days=90` |

**State file update**: `## Category` section. Guardar como `create-new` o `use-existing` según respuesta de Q1.

Si Q1 = `use-existing`, generar `setup_category.sh` que solo hace search (no crea). Si `create-new`, el script generará vía `ensure_category.sh` con todos los datos.

## Batch 3 — Idempotency y metadata

| # | Question | Header | Type | Options |
|---|----------|--------|------|---------|
| 1 | "¿Cuál es el campo de `metadata` que identifica unívocamente un problema? (ej `cve_id`, `resource_arn`, `trace_id`)" | Idempotency key | open text (single) | — |
| 2 | "¿Otros campos de `metadata` importantes para el contexto técnico? (CSV, ej `cvss_score,severity,package`)" | Other metadata | open text (single) | — |
| 3 | "¿Qué `user_metadata` debe ser configurable por usuario? (CSV, solo escalares, ej `target_branch,auto_merge,reviewer`)" | User metadata | open text (single) | — |
| 4 | "¿Incluir `user_metadata_config` para que UI renderice forms con labels?" | UM config | single | `Yes (Recommended)` / `No` |

**Validación crítica (Q1)**: el `metadata_match_key` es obligatorio. Si está vacío, repreguntar — sin idempotency key no se puede continuar.

**State file update**: `## Idempotency` section.

## Batch 4 — Ejecución (solo si type = Executor only o Both)

Si type = `Detector only` o `Reconciler-only`, **saltar este batch**.

| # | Question | Header | Type | Options |
|---|----------|--------|------|---------|
| 1 | "Owner tag del executor (ej `executor:pr-creator`, `executor:terraform-applier`)" | Owner | open text (single) | — |
| 2 | "¿Qué `action_type`s ejecuta? (CSV, ej `dependency_upgrade,config_change`)" | Action types | open text (single) | — |
| 3 | "Política de retry para suggestions failed" | Retry policy | single | `No retries` / `Max 3 attempts (Recommended)` / `Custom (max 5)` |
| 4 | "¿Respeta hold/abort instructions en comments humanos?" | Respect hold | single | `Yes (Recommended)` / `No` |

**State file update**: `## Execution` section.

## Batch 5 — Frequency y NRN scope

| # | Question | Header | Type | Options |
|---|----------|--------|------|---------|
| 1 | "¿Con qué frecuencia correrá el agente?" | Frequency | single | `On-demand` / `Cron (user-scheduled)` / `Event-driven (webhook)` / `Multiple` |
| 2 | "NRN scope por defecto (puede ser dinámico)" | Default NRN | open text (single) | — |
| 3 | "¿Registra automáticamente la categoría en el primer run?" | Auto-register category | single | `Yes (Recommended)` / `No` |
| 4 | "Slug en `created_by` (cómo aparece el agente en los items que crea)" | Created-by tag | open text (single) | — (default: `agent:<name>`) |

**State file update**: `## Frequency` section.

## Confirmation

Antes de generar archivos, mostrar al usuario el resumen completo del state file y preguntar:

```
Question: "¿Confirmás la generación del agente <name>?"
Options: ["Yes, generate now", "Edit batch X", "Cancel"]
```

Si confirma:

1. Leer `docs/generation-recipes.md` y usar el `Write` tool para crear cada archivo del skill nuevo bajo `.claude/skills/np-governance-agent-<name>/` (en el proyecto del usuario), sustituyendo los placeholders `<<...>>` con los valores del state file. Adaptar contenido donde tenga sentido (ej: expandir `Action types: foo,bar` en branches reales `case foo)` / `case bar)` en `execute.sh`).
2. **No olvides `scripts/_lib.sh`** — todos los demás scripts lo sourcean para descubrir `np-governance-action-items` en runtime.
3. `chmod +x .claude/skills/np-governance-agent-<name>/scripts/*.sh`
4. Ejecutar `validate_generated.sh .claude/skills/np-governance-agent-<name> --state-file .claude/state/agent-<name>.md`

**No** se modifica `bundles.json` ni `permissions/permissions.json` de este repo — el agente vive en el proyecto del usuario, no en nuestro plugin.

## Resume protocol

Si el state file existe con `phase != complete`:

```
Question: "Encontré un wizard en progreso para `<name>` (phase: <phase>). ¿Qué hacés?"
Options:
  - "Resume from <next batch>"
  - "Restart from scratch"
  - "Cancel"
```

Si resume, leer el state file, identificar qué batches están completos, y empezar desde el siguiente.
