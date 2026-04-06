---
name: np-service-guide
description: Use when the user asks about creating, understanding, or working with nullplatform services. This is the entry point for all service development tasks — it provides the architecture overview and routes to specialized skills for specs, scripts, terraform, and testing.
---

# Nullplatform Service Development Guide

Entry point para desarrollar servicios de nullplatform. Un **service** es un recurso cloud (database, cache, storage, messaging, etc.) que se provisiona via terraform y se conecta a aplicaciones via links.

## Critical Rules

1. **ALWAYS invocar el skill especializado** antes de hacer trabajo en esa area. Este guide da contexto; los skills especializados tienen las convenciones detalladas.
2. **ALWAYS revisar ejemplos del repositorio de referencia** antes de crear un servicio nuevo (ver seccion Reference Repository).
3. **NEVER usar `specification_schema`** como campo top-level en specs — siempre `attributes.schema`.
4. **NEVER escribir scripts sin `set -euo pipefail`** y manejo de errores.
5. **NEVER usar `curl` contra la API** — siempre `/np-api fetch-api`.

## Reference Repository

El repositorio `https://github.com/nullplatform/services` contiene servicios de referencia con implementaciones completas (specs, deployment, permissions, workflows, scripts, entrypoints).

Para explorar los ejemplos disponibles:

```bash
# Clonar/actualizar referencia
git clone https://github.com/nullplatform/services /tmp/np-services-reference 2>/dev/null \
  || (cd /tmp/np-services-reference && git pull)

# Listar servicios disponibles (busca por service-spec.json.tpl)
find /tmp/np-services-reference -name "service-spec.json.tpl" -not -path "*/.git/*" | \
  xargs -I{} sh -c 'echo "---"; dirname {} | sed "s|/tmp/np-services-reference/||"; jq "{name, slug, selectors}" {}'
```

No hardcodear la estructura del repo -- siempre explorar dinamicamente porque puede cambiar.

## Routing Table

| Tarea | Skill |
|-------|-------|
| Crear/listar/registrar/testear servicios (ciclo completo) | `np-service-craft` |
| Convenciones de service-spec.json.tpl, link specs, values.yaml | `np-service-specs` |
| Convenciones de workflows YAML, build_context, do_tofu, entrypoints | `np-service-workflows` |
| Registro en terraform (service_definition, bindings) | `np-service-creator` |
| Setup del agente local para testing | `np-agent-local-setup` |
| Gestion de notification channels | `np-notification-manager` |
| Consultas a la API de nullplatform | `np-api` |

## Service Philosophy

### 1. Developer-First Design
- Los campos del spec deben ser comprensibles para un developer que no conoce el cloud provider
- Ejemplo: pedir `storage_size: 100` (GB) en vez de `allocated_storage: 100`
- Campos avanzados van en `values.yaml`, no en el spec

### 2. Minimal Schema
- Solo exponer en el spec los campos que el developer necesita decidir
- Settings de infraestructura (VPC, subnets, profiles) van en `values.yaml`
- Menos campos = menos errores al crear instancias

### 3. Terraform-First Provisioning
- La mayoria de servicios se provisiona con terraform (via do_tofu)
- Para APIs REST sin provider terraform, usar `null_resource` con provisioners o scripts directos
- Siempre usar state remoto por instancia (key basado en service name)

### 4. Links = Permissions + Credentials
- Un link conecta una app a un servicio
- El link workflow ejecuta el permissions module (IAM/RBAC) y opcionalmente genera credenciales
- Campos con `export: true` se convierten en env vars de la app

## Service Structure

```
services/<service-name>/
+-- specs/
|   +-- service-spec.json.tpl       # Schema UI + selectors
|   +-- links/
|       +-- connect.json.tpl        # Como las apps se conectan
+-- deployment/
|   +-- main.tf                     # Recursos cloud
|   +-- variables.tf, outputs.tf, providers.tf
+-- permissions/
|   +-- main.tf                     # IAM/RBAC para linking
|   +-- locals.tf, variables.tf
+-- workflows/<provider>/
|   +-- create.yaml, delete.yaml, update.yaml
|   +-- link.yaml, unlink.yaml, read.yaml
+-- scripts/<provider>/
|   +-- build_context               # Parsea contexto -> env vars
|   +-- do_tofu                     # Ejecuta tofu init + apply/destroy
|   +-- write_service_outputs       # (opcional) Escribe outputs post-tofu
|   +-- write_link_outputs          # (opcional) Escribe credenciales post-link
|   +-- build_permissions_context   # (opcional) Contexto para permissions module
+-- entrypoint/
|   +-- entrypoint                  # Router principal (bridge NP_API_KEY)
|   +-- service                     # Handler de service actions
|   +-- link                        # Handler de link actions
+-- values.yaml                     # Config estatica (region, profiles, etc)
```

## Decision Tree: Que Tipo de Servicio

```
Tiene terraform provider? ──Yes──> Terraform-based service
  │                                (deployment/ con main.tf)
  No
  │
Tiene API REST? ──Yes──> API-based service
  │                      (scripts/ con do_provision)
  No
  │
Recurso existente? ──Yes──> Import service
                             (solo specs + link)
```

## Provider-Specific Gotchas

Cargar solo cuando sea relevante al provider del servicio:

- AWS: ver `docs/gotchas-aws.md`
- Azure: ver `docs/gotchas-azure.md`
