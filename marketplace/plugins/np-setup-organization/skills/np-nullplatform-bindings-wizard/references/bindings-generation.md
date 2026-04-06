# Nullplatform Bindings Layer Generation Guide

Guia de generacion de archivos para la capa **nullplatform-bindings/** de Nullplatform con OpenTofu.

> **IMPORTANTE**: No supongas valores ni configuraciones. Ante cualquier duda, divergencia o ambiguedad, **siempre pregunta al usuario** antes de generar codigo. Es mejor hacer preguntas adicionales que generar codigo incorrecto o con suposiciones erroneas.

> **MEJORA CONTINUA**: Despues de cada generacion, si se encuentran errores, divergencias o mejoras, **agregarlas automaticamente a la seccion "Lecciones aprendidas"** de este PROMPT para construir conocimiento estandarizado.

> **VALIDACION OBLIGATORIA**: Antes de generar o modificar cualquier codigo, **validar que cumple TODAS las reglas** de este documento. Checklist de validacion:
> 1. Lei el `variables.tf` del modulo descargado para conocer las variables requeridas? (Regla tecnica #7)
> 2. Solo estoy incluyendo variables sin default (mandatorias)?
> 3. Estoy infiriendo algun valor que deberia preguntar al usuario?
> 4. Estoy usando el modulo en lugar de crear recursos directamente?
> 5. Los bloques de modulos estan limpios, sin comentarios inline? (Regla #6)
> 6. Los bloques module en main.tf estan en orden alfabetico por nombre?
> 7. Los valores de infrastructure usan `local.*` con fallback? Los de nullplatform usan `local.*` desde remote state? (Patron data.tf/locals.tf)
> 8. No hay variables de scope/service specification en variables.tf ni terraform.tfvars?

> **INSTRUCCIONES DE EJECUCION**: Flujo obligatorio para generar codigo correcto:
> 1. Seguir el flujo de preguntas usando `AskUserQuestion` - NO asumir configuraciones
> 2. Despues de generar, ejecutar `tofu init -backend=false && tofu validate`
> 3. Para verificar variables de modulos, leer desde `.terraform/modules/<nombre>/variables.tf` (version descargada), **NUNCA** desde la raiz del repositorio
> 4. Si validate falla, corregir ANTES de dar por terminado
> 5. **NO hacer cambios** al codigo ya generado sin confirmacion explicita del usuario
> 6. Al revertir cambios, verificar con `grep -r` que no quedan referencias residuales

## Estructura generada

```
nullplatform-bindings/
├── main.tf                 # GENERADO por este wizard
├── variables.tf
├── provider.tf
├── backend.tf
├── data.tf                 # Data sources (remote state de infrastructure y nullplatform)
├── locals.tf
└── terraform.tfvars
```

---

## Que modulos van en nullplatform-bindings/

La carpeta `nullplatform-bindings/` conecta Nullplatform con cloud y code repository. Contiene los bindings entre la plataforma y servicios externos.

### Modulos disponibles

```hcl
# Code repository
module "code_repository" { }  # nullplatform/code_repository

# Asset repository (segun cloud)
module "asset_repository" { }  # nullplatform/asset/ecr (AWS) o nullplatform/asset/docker_server

# Cloud provider config
module "cloud_provider" { }  # nullplatform/cloud/aws/cloud (o azure/gcp)

# Asociaciones scope-agent
module "scope_definition_channel_association" { }  # nullplatform/scope_definition_agent_association

# Service definition associations (opcional)
module "service_definition_channel_association" { }  # nullplatform/service_definition_agent_association

# Monitoring
module "monitoring_provider" { }  # nullplatform/metrics

# API Keys para notifications
module "scope_notification_api_key" { }    # nullplatform/api_key
module "service_notification_api_key" { }  # nullplatform/api_key (opcional, si hay service definitions)
```

---

## Flujo de preguntas

### Paso 1: Componentes
- **Que code repository?**: github | gitlab | azure
- **Asset repository**: ECR (AWS) | Docker Server (cualquier cloud)
- **Cloud provider**: Se determina automaticamente segun el cloud elegido en infrastructure

### Paso 2: Variables especificas del code repository

Despues de elegir el code repository, pedir las variables requeridas. Estas se determinan leyendo `variables.tf` del modulo descargado (`code_repository`), filtrando las variables Nivel 2 que aplican al provider elegido (tienen `validation` condicional con `var.git_provider != "provider"`).

**IMPORTANTE**: No hardcodear la lista de variables aqui. Siempre leer del modulo descargado. A modo de guia:

- **GitHub**: Variables que empiezan con `github_`
- **GitLab**: Variables que empiezan con `gitlab_` (atencion: algunas son sensitive, otras son objetos complejos)
- **Azure**: Variables que empiezan con `azure_` (verificar cuales tienen default)

Para cada variable requerida del provider elegido:
1. Declararla en `variables.tf` de bindings (con `sensitive = true` si corresponde)
2. Si la variable tiene `default` en el modulo, ofrecer ese default como opcion al usuario (muchas veces el default es suficiente)
3. Si la variable NO tiene default o el usuario quiere cambiar el default, pedir el valor

### Paso 3: Resumen antes de generar

Mostrar tabla con todos los componentes y variables capturadas. Esperar confirmacion antes de generar.

---

## Reglas de generacion

### IMPORTANTE: No suponer, siempre preguntar

1. **NUNCA suponer valores de variables** - Si no tenes informacion explicita del usuario, pregunta
2. **Ante cualquier duda o ambiguedad, pregunta**
3. **Si hay divergencias entre lo que dice el usuario y lo que ves en los modulos, pregunta**
4. **Si un modulo requiere variables que no fueron mencionadas, pregunta**

### Reglas tecnicas

1. **Usar la ultima version publicada** en todos los modulos
   - **Antes de generar**, ejecutar `git tag --sort=-v:refname | head -1` para obtener el ultimo release

2. **Providers requeridos**:
   - AWS: `hashicorp/aws ~> 6.0`
   - `nullplatform/nullplatform` - Consultar la ultima version antes de generar:
     ```bash
     curl -s "https://registry.terraform.io/v1/providers/nullplatform/nullplatform/versions" | jq -r '[.versions[].version] | sort_by(split(".") | map(tonumber)) | last'
     ```
     Usar `~> 0.0.X` con la version obtenida. NO hardcodear una version fija.

3. **Variables sensitive** marcadas correctamente

4. **Formatear con `terraform fmt`** despues de generar

5. **Leer los READMEs de los modulos** antes de generar

6. **Orden alfabetico en main.tf** - Los bloques `module` en main.tf deben estar ordenados alfabeticamente por nombre

7. **NUNCA transformar outputs entre modulos** - Pasar outputs tal cual (sin `replace`, `regex`, `split`, etc.). Si hay duda sobre el formato que espera una variable, leer el codigo interno del modulo (main.tf, iam.tf, locals.tf) para ver como se usa, no inferir por el nombre de la variable

8. **OBLIGATORIO: Leer variables.tf de CADA modulo antes de generar main.tf** - Despues de `tofu init -backend=false`, leer el `variables.tf` descargado de cada modulo en `.terraform/modules/<nombre>/`. Solo incluir variables sin default (mandatorias) y solo entonces generar los bloques de modulos. No confiar en los patrones de este documento - pueden estar desactualizados respecto a la version del modulo.

9. **Generar una api_key por cada scope definido en nullplatform** - Por cada scope que exista (containers, scheduled_task, etc.), crear un modulo `api_key` con `type = "scope_notification"` y un nombre distintivo. Luego pasar esa api_key al channel association correspondiente:
   ```hcl
   module "scope_notification_api_key" {
     source             = "...//nullplatform/api_key?ref=vX.Y.Z"
     type               = "scope_notification"
     nrn                = var.nrn
     specification_slug = local.scope_specification_slug
   }

   module "scope_notification_api_key_scheduled_task" {
     source             = "...//nullplatform/api_key?ref=vX.Y.Z"
     type               = "scope_notification"
     nrn                = var.nrn
     specification_slug = local.scope_specification_slug_scheduled_task
   }

   module "scope_definition_channel_association" {
     api_key = module.scope_notification_api_key.api_key
   }

   module "scope_definition_channel_association_scheduled_task" {
     api_key = module.scope_notification_api_key_scheduled_task.api_key
   }
   ```
   Lo mismo aplica para service_definitions si existen (con `type = "service_notification"`).

---

## Reglas de tfvars

### Separacion de variables comunes y especificas

1. **`common.tfvars`** (en raiz): Variables compartidas
   - `np_api_key`, `nrn`, `tags_selectors`

2. **`terraform.tfvars`** (en nullplatform-bindings/): Solo variables especificas
   - Variables de code repository (github_*, gitlab_*, azure_*)
   - NO duplicar variables que estan en common.tfvars

### Patron de uso

```hcl
#
# Nullplatform Bindings - Specific Variables
#
# Usage: tofu plan -var-file=../common.tfvars -var-file=./terraform.tfvars
#
```

---

## Patron de data.tf y locals.tf (Remote State + Locals Fallback)

La capa `nullplatform-bindings/` consume outputs de las capas anteriores via `terraform_remote_state`. Esta es la unica forma de obtener valores de scope/service definitions - **NUNCA se declaran como variables ni se hardcodean en tfvars**.

### Regla: Clasificacion de valores por origen

| Origen | Patron | Ejemplo |
|--------|--------|---------|
| **Infrastructure** | Fallback condicional: variable `default = null` + ternario | `cluster_name`, `domain_name`, zone IDs |
| **Nullplatform** | Siempre desde remote state, sin fallback ni variable | `scope_specification_id`, `scope_specification_slug` |
| **Propios de bindings** | Variable directa en `variables.tf` + tfvars | `github_organization`, `git_provider` |

### 1. data.tf - Remote state references

Dos bloques de `terraform_remote_state`:

**Infrastructure (condicional con count):**
```hcl
data "terraform_remote_state" "infrastructure" {
  count   = (var.cluster_name == null || var.domain_name == null || ...) ? 1 : 0
  backend = "local"  # o "s3", segun backend.tf de infrastructure
  config = {
    path = "../infrastructure/{cloud}/terraform.tfstate"
  }
}
```
- El `count` evalua si ALGUNA variable de infrastructure es `null`. Si todas fueron proporcionadas via tfvars, no se lee el remote state.
- La condicion del count debe incluir TODAS las variables de infrastructure que se consumen.

**Nullplatform (siempre, sin count):**
```hcl
data "terraform_remote_state" "nullplatform" {
  backend = "local"  # o "s3", segun backend.tf de nullplatform
  config = {
    path = "../nullplatform/terraform.tfstate"
  }
}
```
- Sin `count` porque es dependencia fuerte. Los scope/service IDs y slugs siempre vienen de aca.

### 2. locals.tf - Resolucion de valores

```hcl
locals {
  # Infrastructure - variable overrides remote state
  cluster_name    = var.cluster_name != null ? var.cluster_name : data.terraform_remote_state.infrastructure[0].outputs.cluster_name
  domain_name     = var.domain_name != null ? var.domain_name : data.terraform_remote_state.infrastructure[0].outputs.domain_name

  # Nullplatform - always from remote state
  scope_specification_id   = data.terraform_remote_state.nullplatform.outputs.scope_specification_id
  scope_specification_slug = data.terraform_remote_state.nullplatform.outputs.scope_specification_slug
}
```

**Reglas de locals.tf:**
- Infrastructure: ternario `var.x != null ? var.x : data.terraform_remote_state.infrastructure[0].outputs.x`
- Nullplatform: asignacion directa `data.terraform_remote_state.nullplatform.outputs.x`
- Los nombres de los locals deben coincidir con los nombres de los outputs de cada capa

### 3. variables.tf - Solo infrastructure con default = null

Las variables de infrastructure se declaran con `default = null` para permitir override:

```hcl
variable "cluster_name" {
  type    = string
  default = null
}
```

**NO declarar variables para valores de nullplatform** (scope_specification_id, scope_specification_slug, etc.). Estos solo existen en locals.tf via remote state.

### 4. main.tf - Siempre usar local.*

Los modulos referencian `local.*` para valores de infrastructure y nullplatform:

```hcl
module "cloud_provider" {
  domain_name = local.domain_name        # NO var.domain_name
}

module "scope_definition_channel_association" {
  scope_specification_id = local.scope_specification_id  # NO var.scope_specification_id
}
```

Las unicas variables que se pasan directo con `var.*` son las propias de bindings (code repo, np_api_key, nrn, tags_selectors).

### 5. terraform.tfvars - Sin scope/service values

Los scope/service specification IDs y slugs **NUNCA van en terraform.tfvars**. Los valores de infrastructure son opcionales (override).

### Config del backend

Los datos de conexion del remote state (bucket, key, region, profile) se leen del `backend.tf` de cada capa (`infrastructure/backend.tf` y `nullplatform/backend.tf`). NO inventar estos valores.

### Outputs que se consumen

**De infrastructure/outputs.tf:**

| Variable local | Descripcion | Donde se usa |
|---------------|-------------|-------------|
| `cluster_name` | Nombre del cluster K8s | asset_repository |
| `domain_name` | Dominio de aplicaciones | cloud_provider |
| `public_zone_id` | Zone ID DNS publica | cloud_provider |
| `private_zone_id` | Zone ID DNS privada | cloud_provider |

**De nullplatform/outputs.tf:**

Por cada scope definition: 2 outputs (id + slug). Por cada service definition: 2 outputs (id + slug). Los nombres exactos se determinan leyendo `nullplatform/outputs.tf`.

---

## Lecciones aprendidas

### 1. NO usar depends_on con modulo ECR
El modulo `nullplatform/asset/ecr` tiene configuraciones de provider locales. NO usar `depends_on`.

### 2. Mapeo de outputs entre scope_definition y scope_definition_agent_association
Los modulos usan nombres diferentes: `service_specification_id` -> `scope_specification_id`, `service_slug` -> `scope_specification_slug`. El mapeo se resuelve en `nullplatform/outputs.tf`.

### 3. `np_api_key` vs `api_key` - son cosas distintas
- `np_api_key`: Autenticacion del provider de nullplatform. La usan modulos que solo necesitan auth (code_repository, asset, cloud, metrics).
- `api_key`: Generada en runtime por el modulo `nullplatform/api_key`. La usa `scope_definition_agent_association` y `service_definition_agent_association`. Tipos disponibles: agent, scope_notification, service_notification, custom.

---

## Regla de variables

### 5. Como determinar si una variable es requerida

Al leer `variables.tf` de un modulo, aplicar una regla simple:

- **Sin `default`** → MANDATORIA. Incluir siempre en main.tf, preguntar valor al usuario.
- **Con `default`** → NO incluir en main.tf, NO preguntar al usuario. Solo incluir si este documento lo indica explicitamente o si el usuario lo pide.

### Flujo de lectura de modulos

1. **Leer `variables.tf`** del modulo descargado (`.terraform/modules/<nombre>/variables.tf`)
2. **Identificar variables sin default** → incluir siempre, preguntar valor al usuario
3. **Variables con default** → NO incluir, NO preguntar

---

### 6. No agregar comentarios inline dentro de bloques de modulos

Los bloques de modulos deben ser limpios, sin comentarios inline. Solo usar comentarios de separacion ANTES del bloque del modulo.

---

### 6b. Orden dentro de cada bloque module

`source` va primero, luego las variables ordenadas alfabeticamente, y `depends_on` va ultimo separado por una linea en blanco del resto:

```hcl
module "example" {
  source = "git::https://..."

  alpha_var = "a"
  beta_var  = "b"
  zeta_var  = "z"

  depends_on = [module.other]
}
```

---

### 7. NUNCA hardcodear valores - siempre usar variables

- **Regla**: Cada valor en un modulo debe venir de una variable con su correspondiente declaracion en `variables.tf`

### 8. Estructura de variables consistente

Para cada variable usada en main.tf:
1. Declararla en `variables.tf` con tipo, descripcion y default (si aplica)
2. Si es compartida entre layers, verificar que este en `common.tfvars`

---

### 9. tags_selectors es una variable comun

La variable `tags_selectors` se usa en:
- `infrastructure/` -> modulo agent (`tags_selectors`)
- `nullplatform-bindings/` -> modulo scope_definition_agent_association (`tags_selectors`)

Como siempre deben tener los **mismos valores**, esta variable debe estar en `common.tfvars`.

**En nullplatform-bindings/variables.tf:**
```hcl
variable "tags_selectors" {
  type        = map(string)
  description = "Tags selectors for agent channel filtering"
}
```

---

### 10. Usar OpenTofu (tofu) en lugar de Terraform

Los comandos de IaC deben usar `tofu` en lugar de `terraform`.

---

### 11. Variables especificas de un layer van en su terraform.tfvars, no en common.tfvars

- Solo poner en `common.tfvars` variables que se usan en **mas de un** layer:
  - `common.tfvars`: np_api_key, nrn, tags_selectors, aws_region, domain_name
  - `nullplatform-bindings/terraform.tfvars`: gitlab_*, github_*, azure_* (code repository config)

---

### 12. API key del provider vs CLI `np` pueden tener permisos diferentes

- Verificar que la API key tenga los roles necesarios para **todas** las operaciones del modulo

---

### 13. Leer variables del modulo DESCARGADO, no del working directory

- Ejecutar `tofu init -backend=false` ANTES de leer variables
- Leer desde `.terraform/modules/<nombre>/variables.tf`
- **NUNCA** leer desde la raiz del repositorio

---

### 14. Confirmar SIEMPRE antes de modificar codigo ya generado

Despues de generar codigo, cualquier modificacion debe:
1. Explicar que se va a cambiar y por que
2. Esperar confirmacion explicita del usuario

---

### 15. Verificar reverts con grep

Despues de revertir, ejecutar `grep -r "<termino_viejo>"` para verificar que no quedan referencias residuales.

---

### 16. Validar cada capa inmediatamente despues de generarla

Despues de generar:
1. `tofu init -backend=false`
2. `tofu validate`
3. Corregir errores antes de dar por terminado

---

### 17. Mostrar resumen de variables antes de tofu apply

**OBLIGATORIO** antes de ejecutar `tofu apply`: mostrar una tabla con TODAS las variables que usan los modulos, indicando:

| Variable | Modulo(s) | Origen | Valor |
|----------|-----------|--------|-------|
| `var_name` | modulo que la usa | `common.tfvars` / `terraform.tfvars` / `default en variables.tf` | valor actual |

- Incluir variables con valores default (no solo las de tfvars)
- Marcar variables sensitive como `(sensitive)`
- Indicar si alguna variable esta declarada pero no se usa en ningun modulo
- Esperar confirmacion del usuario antes de ejecutar el apply
