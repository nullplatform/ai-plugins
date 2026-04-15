# Post-Generation Checks

`validate_generated.sh` corre después de que Claude generó los archivos del agente, para verificar que el agente cumple las convenciones esperadas. Si alguna validación falla, deja el state file en `phase: validation` con la lista de issues; si todas pasan, lo marca como `phase: complete`.

El script vive en este meta-skill (no en el agente generado): `${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/scripts/validate_generated.sh`. Se invoca contra el directorio del agente nuevo en el proyecto del usuario.

## Invocación

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-governance-agent-builder/scripts/validate_generated.sh \
  .claude/skills/np-governance-agent-<name> \
  --state-file .claude/state/agent-<name>.md
```

## Checklist

| # | Check | Failure mode |
|---|-------|--------------|
| 1 | `SKILL.md` tiene frontmatter con `name:` y `description:` | Falla si no |
| 2 | `SKILL.md` `name:` matchea `np-governance-agent-<slug>` | Falla si no |
| 3 | Todos los scripts en `scripts/` tienen un shebang que termina en `bash` | Falla si no |
| 4 | Todos los scripts son ejecutables (`-x`) | Auto-fix con `chmod +x` |
| 5 | `shellcheck` pasa en todos los `.sh` | Warning si shellcheck no instalado, warning si reporta issues |
| 6 | El skill está bajo `.claude/skills/` (no dentro de este repo) | Warning si no — el agente debería vivir en el proyecto del usuario |
| 7 | Existe `scripts/_lib.sh` (discovery helper) | Warning si no — sin él el agente no puede encontrar `np-governance-action-items` en runtime |
| 8 | Ningún script generado contiene `curl ` directo (excepto comments) | Falla si encuentra |
| 9 | `user_metadata` solo contiene escalares en los templates | Warning si encuentra objects/arrays |
| 10 | `detect.sh` (si existe) llama a `search_action_items_by_metadata.sh` o `reconcile_action_items.sh` antes de `create_action_item.sh` | Warning si no — fuerza idempotency |
| 11 | El state file existe en la ruta pasada con `--state-file` | Falla si no |
| 12 | El state file pasa a `phase: complete` cuando todas las validaciones pasan | Auto-marca |

**No se chequea** `bundles.json` ni `permissions.json` — el agente generado vive en el proyecto del usuario, no en este repo. Esos archivos pertenecen al plugin `np-governance` y no se tocan durante la generación.

## Cuándo correr

`validate_generated.sh` se invoca:

1. Automáticamente por el wizard como último paso, después de que Claude escribió los archivos del agente nuevo
2. Manualmente por el usuario después de modificar el agente generado
3. En un commit hook del proyecto del usuario (opcional)

## Manejo de fallas

Si la validación falla:

1. El wizard imprime los errores
2. Deja el state file en `phase: validation` (no `complete`)
3. Ofrece opciones al usuario:
   - "Try to auto-fix what I can and re-run validation"
   - "Open the failing files for me to inspect"
   - "Rollback the generation (delete the .claude/skills/np-governance-agent-<name>/ directory)"
   - "Leave as-is — I'll fix manually"

El estado `validation` permite re-runs del validate sin tener que correr todo el wizard de nuevo.
