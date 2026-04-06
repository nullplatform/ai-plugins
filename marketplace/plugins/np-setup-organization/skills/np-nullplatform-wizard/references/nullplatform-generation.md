# Nullplatform Layer Generation Guide

Guia de generacion de archivos para la capa **nullplatform/** de Nullplatform con OpenTofu.

> **IMPORTANTE**: No supongas valores ni configuraciones. Ante cualquier duda, divergencia o ambiguedad, **siempre pregunta al usuario** antes de generar codigo. Es mejor hacer preguntas adicionales que generar codigo incorrecto o con suposiciones erroneas.

> **MEJORA CONTINUA**: Despues de cada generacion, si se encuentran errores, divergencias o mejoras, **agregarlas automaticamente a la seccion "Lecciones aprendidas"** de este PROMPT para construir conocimiento estandarizado.

> **VALIDACION OBLIGATORIA**: Antes de generar o modificar cualquier codigo, **validar que cumple TODAS las reglas** de este documento. Checklist de validacion:
> 1. Lei el `variables.tf` del modulo para conocer las variables mandatorias (sin default)?
> 2. Estoy incluyendo SOLO variables sin default en los bloques module de main.tf?
> 3. Estoy infiriendo algun valor que deberia preguntar al usuario?
> 4. Estoy usando el modulo en lugar de crear recursos directamente?
> 5. Las variables del modulo son las correctas para la version actual?
> 6. Los bloques de modulos estan limpios, sin comentarios inline?
> 7. Si reutilizo un modulo, paso las variables que distinguen cada instancia? (Regla #16)

> **INSTRUCCIONES DE EJECUCION**: Flujo obligatorio para generar codigo correcto:
> 1. Seguir el flujo de preguntas usando `AskUserQuestion` - NO asumir configuraciones
> 2. Despues de generar, ejecutar `tofu init -backend=false && tofu validate`
> 3. Para verificar variables de modulos, leer desde `.terraform/modules/<nombre>/variables.tf` (version descargada), **NUNCA** desde la raiz del repositorio
> 4. Si validate falla, corregir ANTES de dar por terminado
> 5. **NO hacer cambios** al codigo ya generado sin confirmacion explicita del usuario
> 6. Al revertir cambios, verificar con `grep -r` que no quedan referencias residuales

## Estructura generada

```
nullplatform/
├── main.tf                 # GENERADO por este wizard
├── variables.tf
├── provider.tf
├── backend.tf
├── outputs.tf
└── terraform.tfvars
```

---

## Que modulos van en nullplatform/

La carpeta `nullplatform/` contiene **solo configuracion central de Nullplatform** a nivel organizacion. NO contiene modulos de cloud, code repository, ni bindings.

### Modulos disponibles

```hcl
# Scope definitions (a nivel organizacion)
module "scope_definition" { }                # nullplatform/scope_definition - SIEMPRE incluido
module "scope_definition_scheduled_task" { } # nullplatform/scope_definition - OPCIONAL

# Dimensions
module "dimensions" { }  # nullplatform/dimensions

# Service definitions (opcional)
module "service_definition_endpoint_exposer" { }  # nullplatform/service_definition - OPCIONAL
```

### Que NO va en nullplatform/

Los siguientes modulos van en `nullplatform-bindings/`, NO aqui:
- `code_repository` - conexion con GitLab/GitHub
- `asset_repository` - ECR o Docker Server
- `cloud_provider` - configuracion cloud (AWS/Azure/GCP)
- `scope_definition_agent_association` - asociacion con agentes
- `metrics` - monitoreo

---

## Flujo de preguntas

### Paso 1: Modulos Nullplatform opcionales

Pregunta que modulos adicionales incluir:

**Scope Definitions:**
- [x] Containers (scope_definition) - **Siempre incluido**
- [ ] Scheduled Tasks (scope_definition_scheduled_task) - Opcional

**Service Definitions:**
- [ ] Endpoint Exposer (service_definition) - Opcional

---

## Patron interactivo con AskUserQuestion

### Paso 1: Scope definitions

```json
{
  "questions": [
    {
      "question": "Que scope definitions incluir?",
      "header": "Scopes",
      "options": [
        {"label": "Containers (Recommended)", "description": "Scope definition para deployments K8s estandar"},
        {"label": "Scheduled Tasks", "description": "Scope definition para CronJobs/Jobs periodicos"},
        {"label": "Ambos", "description": "Containers + Scheduled Tasks"}
      ],
      "multiSelect": false
    },
    {
      "question": "Incluir service definitions adicionales?",
      "header": "Services",
      "options": [
        {"label": "Ninguno", "description": "Solo scope definitions basicos"},
        {"label": "Endpoint Exposer", "description": "Service definition para exponer endpoints"}
      ],
      "multiSelect": true
    }
  ]
}
```

### Mostrar resumen antes de generar

```markdown
| Aspecto | Valor |
|---------|-------|
| **Scope Definitions** | Containers + Scheduled Tasks |
| **Service Definitions** | Endpoint Exposer |
```

---

## Reglas de generacion

### IMPORTANTE: No suponer, siempre preguntar

1. **NUNCA suponer valores de variables** - Si no tenes informacion explicita del usuario, pregunta
2. **Ante cualquier duda o ambiguedad, pregunta** - Es mejor preguntar de mas que generar codigo incorrecto
3. **Si hay divergencias entre lo que dice el usuario y lo que ves en los modulos, pregunta** para clarificar
4. **Si un modulo requiere variables que no fueron mencionadas, pregunta** si deben incluirse
5. **Si no estas seguro de que componentes incluir, pregunta** - no asumas la configuracion "recomendada"

### Reglas tecnicas

1. **Usar la ultima version publicada** en todos los modulos
   - **Antes de generar**, ejecutar `git tag --sort=-v:refname | head -1` para obtener el ultimo release del repositorio
   - Usar esa version en todos los `?ref=vX.Y.Z` de los modulos

2. **Providers requeridos** - Consultar la ultima version del provider nullplatform antes de generar:
   ```bash
   curl -s "https://registry.terraform.io/v1/providers/nullplatform/nullplatform/versions" | jq -r '[.versions[].version] | sort_by(split(".") | map(tonumber)) | last'
   ```
   - Usar `~> 0.0.X` con la version obtenida (ej: si la ultima es `0.0.77`, usar `~> 0.0.77`)
   - NO hardcodear una version fija en este documento

3. **Variables sensitive** marcadas correctamente

4. **Formatear con `terraform fmt`** despues de generar

5. **Leer los READMEs de los modulos** antes de generar para verificar variables y dependencias actuales

6. **NUNCA transformar outputs entre modulos** - Pasar outputs tal cual (sin `replace`, `regex`, `split`, etc.). Si hay duda sobre el formato que espera una variable, leer el codigo interno del modulo (main.tf, iam.tf, locals.tf) para ver como se usa, no inferir por el nombre de la variable

7. **Orden alfabetico en main.tf** - Los bloques `module` en main.tf deben estar ordenados alfabeticamente por nombre

8. **Orden dentro de cada bloque module** - `source` va primero, luego las variables ordenadas alfabeticamente, y `depends_on` va ultimo separado por una linea en blanco del resto:
    ```hcl
    module "example" {
      source = "git::https://..."

      alpha_var = "a"
      beta_var  = "b"
      zeta_var  = "z"

      depends_on = [module.other]
    }
    ```

7. **Verificar action_spec_names contra el repo de scopes** - NO confiar en el default del modulo ni en los patrones de este documento. Antes de generar, consultar las actions reales disponibles en `github.com/nullplatform/scopes`:
   ```bash
   gh api repos/nullplatform/scopes/contents/{service_path}/specs/actions --jq '.[].name'
   ```
   - El `{service_path}` corresponde al scope (ej: `k8s`, `scheduled_task`)
   - Usar la lista completa del repo como valor de `action_spec_names`
   - El default del modulo `tofu-modules` puede estar desactualizado respecto al repo de scopes

---

## Reglas de tfvars

### Separacion de variables comunes y especificas

1. **`common.tfvars`** (en raiz): Variables compartidas entre todos los modulos
   - `np_api_key`, `nrn`

2. **`terraform.tfvars`** (en nullplatform/): Solo variables especificas de la capa
   - `service_path`, `service_path_scheduled_task`, `environments`
   - NO duplicar variables que estan en common.tfvars

### Patron de uso

```hcl
#
# Nullplatform - Specific Variables
#
# Usage: tofu plan -var-file=../common.tfvars -var-file=./terraform.tfvars
#
```

---

---

## Outputs obligatorios para consumo de nullplatform-bindings

La capa `nullplatform/` DEBE exportar outputs en `outputs.tf` para que `nullplatform-bindings/` los consuma via `terraform_remote_state`.

### Regla: 2 outputs por cada scope definition, 2 outputs por cada service definition

Por cada `scope_definition` incluido, generar **2 outputs**:
- `scope_specification_id` (o con sufijo si hay mas de uno: `_scheduled_task`)
- `scope_specification_slug` (idem sufijo)

Por cada `service_definition` incluido, generar **2 outputs**:
- `service_specification_id_{nombre}` (ej: `_endpoint_exposer`)
- `service_specification_slug_{nombre}`

Cada output toma su valor del modulo que creo ese scope o service en el `main.tf` generado. Leer `outputs.tf` del modulo descargado en `.terraform/modules/` para conocer los nombres reales de los outputs del modulo y mapearlos a los nombres de contrato de arriba.

**IMPORTANTE**: Estos nombres de output son un contrato con `nullplatform-bindings/`. Si cambian, bindings se rompe.

---

## Lecciones aprendidas

### 1. nullplatform/ NO debe contener modulos de cloud/repository
- **Error**: Poner code_repository, asset_repository (ECR), o cloud_provider en la carpeta nullplatform/
- **Solucion**: La carpeta `nullplatform/` solo debe contener:
  - `scope_definition` - definiciones de scope a nivel organizacion
  - `dimensions` - configuracion de environments
  - `service_definition` - definiciones de servicios (opcional)
- **Los siguientes modulos van en nullplatform-bindings/**:
  - `code_repository`, `asset_repository`, `cloud_provider`

### 2. nullplatform/ folder es mas simple y no requiere data sources de infrastructure
- **Error**: Incluir data sources de infrastructure (cluster, VPC, DNS zones) en nullplatform/
- **Solucion**: Los modulos de `nullplatform/` (scope_definition, dimensions) solo necesitan:
  - `nrn` - Nullplatform Resource Name
  - `np_api_key` - API key
  - Variables especificas del modulo (service_path, environments, etc.)
- **NO necesitan**: cluster_name, vpc_id, zone_ids, etc.

---

### 4. No agregar comentarios inline dentro de bloques de modulos

Los bloques de modulos deben ser limpios, sin comentarios inline. Solo usar comentarios de separacion ANTES del bloque del modulo.

**Correcto**: Comentario de separacion ANTES del bloque, sin comentarios dentro.
```hcl
# =============================================================================
# Nombre del modulo
# =============================================================================
module "nombre" {
  source = "..."

  variable_1 = var.x
  variable_2 = local.y
}
```

---

### 5. NUNCA hardcodear valores - siempre usar variables

Cada valor en un modulo debe venir de una variable o local. NO asignar valores directamente (strings, listas). Declarar la variable en `variables.tf`.

### 6. Estructura de variables consistente

Para cada variable usada en main.tf:
1. Declararla en `variables.tf` con tipo, descripcion y default (si aplica)
2. Si es compartida entre layers, verificar que este en `common.tfvars`

---

### 7. tags_selectors es una variable comun

La variable `tags_selectors` se usa en `nullplatform/` (service_definition) y `nullplatform-bindings/` (scope_definition_agent_association). Como siempre deben tener los **mismos valores**, esta variable debe estar en `common.tfvars`.

---

### 8. Usar OpenTofu (tofu) en lugar de Terraform

Los comandos de IaC deben usar `tofu` en lugar de `terraform`.

---

### 9. Variables especificas de un layer van en su terraform.tfvars, no en common.tfvars

- Solo poner en `common.tfvars` variables que se usan en **mas de un** layer:
  - `common.tfvars`: np_api_key, nrn, tags_selectors
  - `nullplatform/terraform.tfvars`: service_path, environments, service_spec_name, etc.

---

### 10. API key del provider vs CLI `np` pueden tener permisos diferentes

- Verificar que la API key tenga los roles necesarios para **todas** las operaciones del modulo
- **Debug**: Probar manualmente: `NP_API_KEY="<key>" np nrn patch --nrn "<nrn>" --body '{}'`

---

### 11. Leer variables del modulo DESCARGADO, no del working directory

- Ejecutar `tofu init -backend=false` en cada capa ANTES de leer variables
- Leer desde `.terraform/modules/<nombre>/variables.tf` (version real descargada)
- **NUNCA** leer desde la raiz del repositorio para verificar variables de modulos

---

### 12. Confirmar SIEMPRE antes de modificar codigo ya generado

Despues de generar codigo, cualquier modificacion debe:
1. Explicar que se va a cambiar y por que
2. Esperar confirmacion explicita del usuario

---

### 13. Verificar reverts con grep

Despues de revertir, ejecutar `grep -r "<termino_viejo>"` para verificar que no quedan referencias residuales.

---

### 14. Validar cada capa inmediatamente despues de generarla

Despues de generar:
1. `tofu init -backend=false`
2. `tofu validate`
3. Corregir errores antes de dar por terminado

---

### 15. Mostrar resumen de variables antes de tofu apply

**OBLIGATORIO** antes de ejecutar `tofu apply`: mostrar una tabla con TODAS las variables que usan los modulos, indicando:

| Variable | Modulo(s) | Origen | Valor |
|----------|-----------|--------|-------|
| `var_name` | modulo que la usa | `common.tfvars` / `terraform.tfvars` / `default en variables.tf` | valor actual |

- Incluir variables con valores default (no solo las de tfvars)
- Marcar variables sensitive como `(sensitive)`
- Indicar si alguna variable esta declarada pero no se usa en ningun modulo
- Esperar confirmacion del usuario antes de ejecutar el apply

---

### 16. Modulo reutilizado con configuraciones distintas

Cuando el mismo modulo se usa multiples veces con configuraciones diferentes (ej: `scope_definition` para Containers y para Scheduled Tasks), es necesario pasar variables con default que difieren del valor original. Esto es una excepcion a la regla general de omitir variables con default.

**Ejemplo**: El modulo `scope_definition` tiene `service_path = "k8s"` por default. La primera instancia usa el default, pero la segunda necesita `service_path = "scheduled_task"`, `service_spec_name = "Scheduled Tasks"`, `action_spec_names = [...]`, etc.

**Regla**: Cuando se reutiliza un modulo, pasar explicitamente todas las variables que distinguen una instancia de otra, aunque tengan default en el modulo.

---

### 17. Scope definitions deben tener descripcion explicita

Cada scope definition debe incluir `service_spec_name` y `service_spec_description` con valores claros. Si el modulo tiene defaults razonables para la primera instancia (ej: `"Containers"` / `"Docker containers on pods"`), se pueden usar. Para instancias adicionales, siempre pasar valores explícitos via variables.

**Regla**: Verificar que cada scope definition tenga nombre y descripcion definidos, ya sea por default del modulo o por variable explicita.
