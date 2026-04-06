---
name: np-setup-orchestrator
description: Orquesta la configuracion completa de una organizacion de Nullplatform. Usar cuando se necesite inicializar un proyecto, verificar estado de infraestructura/cloud/K8s/API, diagnosticar problemas, o ejecutar checks de herramientas, cloud, Kubernetes, Nullplatform API, telemetria y servicios.
---

# Nullplatform Setup Orchestrator

## REGLA IMPORTANTE: Uso de np-api

**NUNCA uses `curl` directamente para consultar la API de Nullplatform (`api.nullplatform.com`).**

Para CUALQUIER consulta a la API de Nullplatform, DEBES usar:

- `/np-api fetch-api "<endpoint>"` - Para consultas a la API
- `/np-api check-auth` - Para verificar autenticación
- El skill `np-api` - Para operaciones programáticas (invocar via `/np-api`)

**Excepciones permitidas (NO son la API de Nullplatform):**

- `curl` a endpoints de aplicaciones desplegadas (`*.nullapps.io`) para health checks
- `curl` a servicios externos (AWS, Azure, GCP)

## Comandos Disponibles

| Comando | Descripción |
|---------|-------------|
| `/np-setup-orchestrator` | Verifica estado, ofrece inicializar si falta config |
| `/np-setup-orchestrator init` | Wizard inicial paso a paso |
| `/np-setup-orchestrator check-status` | Ejecuta TODOS los checks |
| `/np-setup-orchestrator check-tools` | Verificar herramientas instaladas |
| `/np-setup-orchestrator check-cloud` | Verificar acceso al cloud |
| `/np-setup-orchestrator check-k8s` | Verificar acceso a Kubernetes |
| `/np-setup-orchestrator check-np` | Verificar Nullplatform API |
| `/np-setup-orchestrator check-telemetry` | Verificar telemetría (logs y métricas) |
| `/np-setup-orchestrator check-services` | Listar servicios, ofrecer diagnosticar/modificar/crear |
| `/np-setup-orchestrator check-tf-key` | Verificar common.tfvars (np_api_key) |

---

## Comando: $ARGUMENTS

---

## Si $ARGUMENTS está vacío → Verificar Estado e Inicialización

### Flujo

1. **Verificar si el proyecto está inicializado**

```bash
cat organization.properties 2>/dev/null
ls np-api-skill.key np-api-skill.token 2>/dev/null
ls -d infrastructure/ nullplatform/ nullplatform-bindings/ 2>/dev/null
ls common.tfvars infrastructure/*/terraform.tfvars nullplatform/terraform.tfvars nullplatform-bindings/terraform.tfvars 2>/dev/null
```

2. **Si FALTA ALGUNO de los componentes base (checks 1-3)** → Usar AskUserQuestion: "Este repositorio no está completamente configurado para Nullplatform. ¿Querés inicializar?"
   - **Sí, inicializar** → Ejecutar flujo de `init`
   - **No, solo mostrar estado** → Mostrar resumen de lo que falta

3. **Si TODO está configurado** → Ejecutar check-status automáticamente para ganar contexto situacional. El reporte incluye recomendaciones de próximos pasos.

---

## Si $ARGUMENTS es "init" → Wizard Inicial Paso a Paso

### Verificación Previa

```bash
cat organization.properties 2>/dev/null
ls np-api-skill.key np-api-skill.token 2>/dev/null
ls -d infrastructure/ nullplatform/ nullplatform-bindings/ 2>/dev/null
ls common.tfvars 2>/dev/null
```

**Si TODOS los componentes existen** → Mostrar que ya está inicializado y ofrecer con AskUserQuestion:
- **Ejecutar diagnóstico completo** → `/np-setup-orchestrator check-status`
- **Configurar infraestructura** → `/np-infrastructure-wizard`
- **Configurar dimensions y scopes** → `/np-nullplatform-wizard`
- **Configurar bindings** → `/np-nullplatform-bindings-wizard`

> Si en la conversación ya se ejecutó `check-status`, la primera opción debe decir "Volver a ejecutar diagnóstico completo".

**Si FALTA algún componente** → Continuar con el wizard.

---

### Paso 1: Crear organización

Verificar con `cat organization.properties`. Si no existe, usar AskUserQuestion:
- **Crear una organización nueva** → Invocar `/np-organization-create`. Genera `organization.properties` automáticamente.
- **Ya tengo una organización** → Solicitar organization_id y crear: `echo "organization_id={ORG_ID}" > organization.properties`

### Paso 2: Configurar autenticación para skills

Verificar con `ls np-api-skill.key np-api-skill.token`. Si no existe, guiar:

Se usa **una única API Key** para todo (skills + Terraform). Se guarda en `np-api-skill.key` y se referencia desde `common.tfvars`.

**IMPORTANTE:** No usar API Keys root ni de otras organizaciones. La key debe pertenecer a esta organización.

1. Nullplatform UI → Settings → API Keys
2. Crear con:
   - **Scope:** Preferentemente a nivel **Account** (más restrictivo). También puede ser a nivel Organization.
   - **Roles:** Asignar **TODOS** los roles: Admin, Agent, Developer, Ops, SecOps, Secrets Reader
3. `echo 'TU_API_KEY' > np-api-skill.key`

Una vez creada, generar automáticamente `common.tfvars` con la key (si aplica).

Verificar que `np-api-skill.key` está en .gitignore. Si no, agregarlo.

### Paso 3: Crear estructura de archivos

Verificar con `ls -d infrastructure/ nullplatform/ nullplatform-bindings/`. Si faltan, crear la estructura directamente.

Usar AskUserQuestion para cloud provider: AWS, Azure (luego AKS o ARO), GCP, OCI.

Crear la siguiente estructura de carpetas y archivos. La fuente de verdad para el contenido de cada archivo es el repositorio `nullplatform/tofu-modules` (branch `main`):

```
{output}/
├── infrastructure/{cloud}/     # Infraestructura del cloud (VPC, K8s, DNS, etc.)
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── locals.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── nullplatform/               # Configuracion central de Nullplatform
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── nullplatform-bindings/      # Conecta Nullplatform con cloud + code repo
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   ├── data.tf
│   ├── locals.tf
│   └── terraform.tfvars.example
├── common.tfvars.example
└── .gitignore
```

Los `main.tf` NO se crean en este paso. Se generan dinamicamente en:
- `infrastructure/{cloud}/main.tf` → `/np-infrastructure-wizard`
- `nullplatform/main.tf` → `/np-nullplatform-wizard`
- `nullplatform-bindings/main.tf` → `/np-nullplatform-bindings-wizard`

### Paso 4: Configurar variables comunes

Si `common.tfvars` no existe, crearlo con valores por defecto y luego dejar al usuario modificar lo que necesite.

**Procedimiento:**

1. Leer el contenido plano de `np-api-skill.key` (usar Read, no variables de shell)
2. Generar `common.tfvars` con estos defaults:

```hcl
nrn               = ""
np_api_key        = "<valor plano leido de np-api-skill.key>"
organization_slug = ""
tags_selectors = {
  "environment" = "development"
}
```

3. Mostrar al usuario el archivo generado y preguntar con AskUserQuestion:

> Generé `common.tfvars` con los valores por defecto. Necesito que completes:
> - `nrn`: NRN del recurso (ej: `organization=123:account=456`)
> - `organization_slug`: Slug de la organización

4. Actualizar el archivo con los valores que el usuario proporcione

| Variable | Default | Notas |
|----------|---------|-------|
| `np_api_key` | Leido de `np-api-skill.key` | Se autocompleta, no pedir al usuario |
| `nrn` | Vacio | El usuario debe proporcionarlo |
| `organization_slug` | Vacio | El usuario debe proporcionarlo |
| `tags_selectors` | `{ "environment" = "development" }` | Default razonable, el usuario puede cambiarlo |

> El `nrn` completo puede no estar disponible aún si es org nueva. Completar parcialmente y actualizar después.

### Paso 5: Configurar infraestructura cloud

Invocar `/np-infrastructure-wizard` para configurar la infraestructura completa (VPC, K8s, DNS, agent). NO crear terraform.tfvars manualmente.

### Paso 6: Configurar dimensions y scopes

Invocar `/np-nullplatform-wizard` para configurar dimensions y scopes. NO crear terraform.tfvars manualmente.

### Paso 7: Configurar bindings

Invocar `/np-nullplatform-bindings-wizard` para configurar bindings. NO crear terraform.tfvars manualmente.

### Paso 8: Resumen

Mostrar tabla con estado de todos los componentes y sugerir `/np-setup-orchestrator check-status`.

---

## Si $ARGUMENTS es "check-status" → Diagnóstico Completo

Ejecuta TODOS los checks en secuencia y genera reporte consolidado.

### Secuencia

1. check-tools
2. check-tf-key
3. check-cloud → ver [references/check-cloud.md](references/check-cloud.md)
4. check-k8s → ver [references/check-k8s.md](references/check-k8s.md)
5. check-np → ver [references/check-np.md](references/check-np.md)
6. check-telemetry → ver [references/check-telemetry.md](references/check-telemetry.md)
7. check-services → ver [references/check-services.md](references/check-services.md)
8. Generar reporte consolidado con resumen y siguiente paso sugerido

### Lógica de Recomendaciones

| Condición | Recomendación |
|-----------|---------------|
| No hay organization.properties | `/np-organization-create` o `/np-setup-orchestrator init` |
| Token expirado | Renovar token y volver a ejecutar |
| No hay infraestructura cloud | `/np-infrastructure-wizard` |
| Faltan dimensions/scopes | `/np-nullplatform-wizard` |
| Faltan bindings | `/np-nullplatform-bindings-wizard` |
| Última app/scope/deploy falló | `/np-setup-troubleshooting {tipo} {id}` (el más reciente) |
| Sin actividad reciente | Crear aplicación desde UI de Nullplatform |
| Métricas de sistema vacías | Verificar configuración de telemetría del agente |
| Hay servicios sin registrar | `/np-service-craft register <name>` |
| Hay servicios sin binding | `/np-service-craft register <name>` (revisar bindings) |
| No hay servicios definidos | `/np-service-craft create` para crear uno nuevo |
| Todo funcionando | El flujo completo funciona correctamente |

---

## Si $ARGUMENTS es "check-tools" → Verificar Herramientas

### Herramientas a Verificar

| Herramienta | Comando | Requerida |
|-------------|---------|-----------|
| OpenTofu | `tofu version` | Sí (o Terraform) |
| Terraform | `terraform version` | Sí (o OpenTofu) |
| kubectl | `kubectl version --client` | Sí |
| jq | `jq --version` | Sí |

### Flujo

```bash
tofu version 2>/dev/null || terraform version 2>/dev/null
kubectl version --client 2>/dev/null
jq --version 2>/dev/null
```

Si falta alguna herramienta, indicar cómo instalarla.

---

## Si $ARGUMENTS es "check-tf-key" → Verificar Terraform API Key

Verificar que `common.tfvars` existe y contiene una `np_api_key` válida.

### Flujo

1. **Verificar que el archivo existe**: `ls common.tfvars`. Si no existe, indicar crear desde `common.tfvars.example`.

2. **Validar la API Key**: ejecutar `${CLAUDE_PLUGIN_ROOT}/skills/np-setup-orchestrator/scripts/check-tf-api-key.sh`. Si OK, key válida. Si ERROR, key inválida: indicar verificar/recrear en UI.

3. **Verificar gitignore**: `grep -q "common.tfvars" .gitignore`. Si no está, advertir (riesgo de seguridad).

### Lógica de Recomendaciones

| Condición | Recomendación |
|-----------|---------------|
| Archivo no existe | Crear desde `common.tfvars.example` |
| Key inválida | Verificar/recrear API Key en UI |
| Sin permisos | Crear nueva key con rol Administrator |
| No está en gitignore | Agregar `common.tfvars` a `.gitignore` |
| Todo OK | Terraform API Key configurada correctamente |

---

## Si $ARGUMENTS es "check-cloud" → Verificar Cloud

Ver [references/check-cloud.md](references/check-cloud.md) para el flujo completo.

---

## Si $ARGUMENTS es "check-k8s" → Verificar Kubernetes

Ver [references/check-k8s.md](references/check-k8s.md) para el flujo completo.

---

## Si $ARGUMENTS es "check-np" → Verificar Nullplatform API

Ver [references/check-np.md](references/check-np.md) para el flujo completo.

---

## Si $ARGUMENTS es "check-telemetry" → Verificar Telemetría

Ver [references/check-telemetry.md](references/check-telemetry.md) para el flujo completo.

---

## Si $ARGUMENTS es "check-services" → Verificar Servicios

Ver [references/check-services.md](references/check-services.md) para el flujo completo.
