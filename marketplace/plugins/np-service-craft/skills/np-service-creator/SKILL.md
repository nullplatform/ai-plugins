---
name: np-service-creator
description: This skill should be used when the user asks to "register a service in terraform", "create service_definition module", "create agent binding", "configure terraform for services", or needs to work with terraform modules for nullplatform service registration and agent association.
---

# Nullplatform Service Creator — Terraform Registration

Patrones de terraform para registrar service definitions y agent bindings en nullplatform.

## Critical Rules

1. **Confirm before `tofu apply`** — explain what will be created and why.
2. **NRN of binding MUST match NRN of service_definition** — mismatch causes "There is not a channel for the given parameters".
3. **tags_selectors MUST match agent tags** — mismatch causes notifications not to route.
4. **For local development**, use `git_provider = "local"` to read specs from the filesystem without needing to push to GitHub.
5. **NEVER hardcode module variables from memory** — always read them from the module source.

## Module Source of Truth

Los modulos de terraform para registrar servicios viven en `https://github.com/nullplatform/tofu-modules`:

| Module | Path | Purpose |
|--------|------|---------|
| `service_definition` | `nullplatform/service_definition/` | Creates service_specification + link_specification from JSON specs |
| `service_definition_agent_association` | `nullplatform/service_definition_agent_association/` | Creates notification_channel for agent routing |

## How to Determine Required Variables

**ANTES de generar cualquier bloque terraform**, clonar el repo y leer los `variables.tf` de cada modulo:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Leer:
- `/tmp/tofu-modules-ref/nullplatform/service_definition/variables.tf` — variables con y sin `default`. Las que no tienen default son mandatorias.
- `/tmp/tofu-modules-ref/nullplatform/service_definition_agent_association/variables.tf` — idem.

Tambien leer `main.tf` y `locals.tf` de cada modulo para entender como se arman los recursos internamente (ej: como se construye el cmdline del agent_association).

No copiar variables de este skill — inferirlas del codigo fuente cada vez.

## Two Modes

### Local Mode (desarrollo)

Usar `git_provider = "local"` + `local_specs_path` apuntando al directorio local del servicio. Lee los specs del filesystem sin necesidad de push.

### Remote Mode (produccion)

Usar `git_provider = "github"` (default) o `"gitlab"`. El modulo lee los specs via HTTP desde el repositorio git. Requiere que los specs esten pusheados.

## Agent Association: cmdline

El modulo `service_definition_agent_association` construye el cmdline internamente a partir de sus variables. Leer `main.tf` del modulo para entender el patron exacto.

Para dev local, setear `base_clone_path` al home del usuario (`pathexpand("~/.np")`) en vez del default `/root/.np`.

## Apply Order

Siempre aplicar en orden:
1. `nullplatform/` primero (crea service_specification, genera outputs)
2. `nullplatform-bindings/` segundo (crea notification_channel, lee outputs del paso 1)

## Pre-Registration Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | Schema in `attributes.schema` | `jq -e '.attributes.schema.type' specs/service-spec.json.tpl` |
| 2 | No `specification_schema` | `jq -e '.specification_schema' specs/service-spec.json.tpl` must fail |
| 3 | Links use `attributes.schema` | `jq -e '.attributes.schema' specs/links/*.json.tpl` |
| 4 | NRN matches between both modules | Compare nrn values |
| 5 | tags_selectors match agent tags | Compare with `-tags` flag |
| 6 | Scripts are executable | `ls -la entrypoint/ scripts/*/` |
| 7 | JSONs are valid | `jq . specs/*.json.tpl specs/links/*.json.tpl` |
| 8 | Fields with export:true have write_outputs | verify scripts exist |
