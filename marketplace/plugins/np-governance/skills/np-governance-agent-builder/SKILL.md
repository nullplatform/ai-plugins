---
name: np-governance-agent-builder
description: Guided wizard to generate new Nullplatform Governance Action Item agents (detectors, executors, or both) inside the user's project. Use when the user says "create a governance agent", "new action item agent", "build a detector for X", "generar executor", or invokes /np-governance-create-action-item-agent.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/scripts/*.sh), AskUserQuestion, Write, Edit, Read, Glob
---

# np-governance-agent-builder

Meta-skill que guía al usuario para crear nuevos agentes de governance (detector y/o executor) **en el proyecto del usuario**, no en este repo. El agente generado vive en `<user-project>/.claude/skills/np-governance-agent-<slug>/` como un skill project-local que usa los scripts del plugin `np-governance` instalado.

**No usa motor de templates**. Después del wizard, vos (Claude) leés `docs/generation-recipes.md` y usás el `Write` tool para crear cada archivo, sustituyendo los placeholders `<<...>>` con los valores del state file. Esto te permite adaptar el contenido por agente (ej: expandir `Action types: foo,bar` en branches reales `case foo)` / `case bar)` en `execute.sh`).

## Architecture (importante leer antes de empezar)

El usuario corre el slash command desde su proyecto. La cwd es la raíz del proyecto del usuario.

```
<user-project>/                         ← cwd cuando corre el wizard
├── .claude/
│   ├── state/
│   │   └── agent-<slug>.md             ← state file
│   └── skills/
│       └── np-governance-agent-<slug>/ ← target del Write tool
│           ├── SKILL.md
│           ├── docs/
│           └── scripts/
│               ├── _lib.sh             ← discovery helper
│               ├── setup_category.sh
│               ├── detect.sh
│               ├── execute.sh
│               └── run_once.sh
```

**Nunca** se modifica el `bundles.json` ni el `permissions/permissions.json` de este repo — esos son artefactos de build de NUESTRO plugin. El agente generado es independiente del repo `np-claude-skills`.

**Discovery problem**: el agente generado vive fuera del plugin, así que `${CLAUDE_PLUGIN_ROOT}` no está seteado cuando corre. Por eso cada agente trae un `scripts/_lib.sh` que descubre la ubicación de `np-governance-action-items/scripts` en runtime (chequea `$CLAUDE_PLUGIN_ROOT`, luego paths comunes en `~/.claude/plugins/`, luego `find` como fallback, finalmente la env var `NP_GOVERNANCE_AI_SCRIPTS`).

## Pre-flight (siempre antes de empezar el wizard)

1. **Buscar state file existente**: `Glob(".claude/state/agent-*.md")`. Para cada match, leé la línea `**Current phase**:`. Si `phase != complete`, preguntá al usuario con `AskUserQuestion` si quiere resumir ese wizard o empezar uno nuevo.
2. **Verificar que el plugin `np-governance` está instalado**: chequear que existe `${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/model.md`. Si no, abortar con instrucción clara.
3. **Verificar auth**: ejecutar `${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/check_auth.sh`. Si falla, mostrar las opciones (`NP_API_KEY` o `NP_TOKEN`).

## Crear el state file (al iniciar un wizard nuevo)

Una vez que el usuario confirmó el slug del agente (kebab-case, matcha `^[a-z][a-z0-9-]*$` — si no, repreguntá con `AskUserQuestion`):

1. `Glob` `.claude/skills/np-governance-agent-<slug>/` para detectar colisión. Si ya existe, preguntá al usuario si sobreescribe o elige otro nombre.
2. `Glob` `.claude/state/agent-<slug>.md`. Si existe y `phase != complete`, seguir el protocolo de resume de `docs/state-file-template.md`.
3. Si no hay colisiones, usá el `Write` tool para crear `.claude/state/agent-<slug>.md` con el **Initial state block** definido en `docs/state-file-template.md`, sustituyendo `<<SLUG>>` por el slug elegido y `<<TIMESTAMP>>` por el ISO8601 actual. `Write` crea el directorio `.claude/state/` automáticamente si no existe.

No hay script para esto — hacelo directo con las herramientas nativas. Es determinista pero trivial: no amerita un `.sh`.

## Knowledge base (carga conceptos del modelo via @)

@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/model.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/lifecycle.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/idempotency.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/reconciliation.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/suggestions.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/metadata-vs-user-metadata.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-action-items/docs/concepts/categories.md

## Documentation

@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/wizard-flow.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/state-file-template.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/generation-recipes.md
@${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/docs/post-generation-checks.md

## Workflow

```
1. Pre-flight (state file detection, plugin check, auth check)
   ↓
2. Ask user for slug (if not provided). Validate kebab-case and colision with
   existing .claude/skills/np-governance-agent-<slug>/.
   ↓
3. Write .claude/state/agent-<slug>.md using the Initial state block from
   docs/state-file-template.md.
   ↓
4. AskUserQuestion in up to 5 batches (max 4 questions per batch)
   - Batch 1: Identity (name, type, problem, domain)
   - Batch 2: Category (existing or new, slug, unit symbol, config)
   - Batch 3: Idempotency (metadata key, other metadata, user_metadata)
   - Batch 4: Execution (only if executor/both: owner, action types, retry, hold)
   - Batch 5: Frequency + NRN scope
   After each batch, use Edit to update .claude/state/agent-<slug>.md and
   advance **Current phase**.
   ↓
5. Read docs/generation-recipes.md and use the Write tool to create each
   file under .claude/skills/np-governance-agent-<slug>/, substituting
   <<PLACEHOLDERS>> with values from the state file. Adapt content where
   useful (e.g., expand action_types into real case branches).
   chmod +x .claude/skills/np-governance-agent-<slug>/scripts/*.sh
   ↓
6. validate_generated.sh .claude/skills/np-governance-agent-<slug> \
       --state-file .claude/state/agent-<slug>.md
   ↓
7. Report summary with next steps for testing
```

## Critical Rules

1. **Siempre usar AskUserQuestion** para preguntar al usuario, nunca volcar texto plano. Max 4 preguntas por batch.
2. **Forzar idempotency**: el wizard SIEMPRE pregunta el `metadata_match_key` (Batch 3, Q1). Sin idempotency key no se puede continuar.
3. **`user_metadata` solo escalares**: validar al recibir respuestas que el usuario no propone objects/arrays.
4. **El agente generado NO reimplementa lógica** — solo wrappers delgados sobre los scripts de `np-governance-action-items`, descubiertos en runtime via `_lib.sh`.
5. **Cada agente generado trae su `_lib.sh`** y lo sourcean todos los demás scripts (`setup_category.sh`, `detect.sh`, `execute.sh`).
6. **Nunca tocar `bundles.json` ni `permissions/permissions.json` de este repo** — el agente vive en el proyecto del usuario, no en el plugin.
7. **State file primero**: cualquier operación lee el state file primero. Si no existe, crear; si existe en `phase != complete`, preguntar si resumir.

## Available Scripts

El meta-skill tiene **un solo script**, y es porque corre herramientas externas (`shellcheck`) y sirve como validación determinista re-runnable por el usuario:

| Script | Purpose |
|--------|---------|
| `validate_generated.sh` | Sanity checks post-generación (frontmatter, shebangs, shellcheck, no curl, idempotency call, `_lib.sh` presence, skill is under `.claude/skills/`) |

Todo lo demás —crear el state file, validar el slug, detectar resume, escribir los archivos del agente nuevo, aplicar placeholders, avanzar la phase— lo hacés vos (Claude) con las herramientas nativas (`Glob`, `Read`, `Write`, `Edit`, `AskUserQuestion`) siguiendo los docs.

## Slash command association

Este skill se invoca normalmente vía el slash command `/np-governance-create-action-item-agent` que está en `src/commands/`.

## Output del wizard

Al completar el wizard exitosamente, reportá al usuario algo como:

```
Agent generated successfully!

📁 New skill: .claude/skills/np-governance-agent-<name>/
📋 Files created:
  - SKILL.md
  - docs/overview.md
  - docs/detect.md (if detector)
  - docs/execute.md (if executor)
  - scripts/_lib.sh        ← discovery helper
  - scripts/setup_category.sh (if detector)
  - scripts/detect.sh (if detector)
  - scripts/execute.sh (if executor)
  - scripts/run_once.sh

✓ Validation passed

Requirements:
  - The np-governance plugin must be installed (it provides the scripts the
    agent calls into via _lib.sh discovery).
  - Or set NP_GOVERNANCE_AI_SCRIPTS=/abs/path/to/np-governance-action-items/scripts

Next steps:
  1. Customize detect.sh SCAN section with your real detection logic
  2. Customize execute.sh ACTION HANDLERS with your action_type branches
  3. Test: ./.claude/skills/np-governance-agent-<name>/scripts/run_once.sh "organization=1"
  4. Commit to your repo: git add .claude/skills/np-governance-agent-<name>/
```

Si la validación falla, deja el state file en `phase: validation` con la lista de issues y ofrece reparar.
