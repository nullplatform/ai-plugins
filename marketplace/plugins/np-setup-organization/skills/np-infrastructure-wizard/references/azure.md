# Arbol de Decision - Azure Infrastructure

> Invocado desde el paso 4 del wizard principal (`SKILL.md`).
> **Input global**: `infrastructure/azure/` con archivos .tf originales
> **Output global**: Archivos .tf customizados, `existing-resources.properties` (si aplica), variables nuevas en `terraform.tfvars`

## Contenido

1. [Clasificacion de Modulos](#paso-1-clasificacion-de-modulos)
2. [Preguntar por componentes Cloud](#paso-2-preguntar-por-cada-componente-cloud)
3. [Resolver dependencias de excluidos](#paso-3-resolver-dependencias-de-modulos-excluidos)
4. [Preguntar por componentes Commons](#paso-4-preguntar-por-componentes-commons)
5. [Aplicar cambios a .tf](#paso-5-aplicar-cambios-a-los-archivos-tf)
6. [Validar archivos .tf](#paso-6-validar-archivos-tf)

## Paso 1: Clasificacion de Modulos

> **Input**: `infrastructure/azure/main.tf`
> **Output**: Modulos clasificados por categoria

Leer `main.tf` dinamicamente y clasificar:

### Cloud (preguntables)

| Modulo | Pregunta |
|--------|----------|
| `resource_group` | Ya tenes un Resource Group? |
| `vnet` | Ya tenes una VNet? |
| `aks` | Ya tenes un cluster AKS? |
| `acr` | Ya tenes un Azure Container Registry? |
| `dns` | Ya tenes una DNS Zone publica? |
| `private_dns` | Ya tenes una DNS Zone privada? |
| `base_security` | Ya tenes NSGs para los gateways? |

### Nullplatform (siempre incluidos, no preguntar)

- `agent_api_key`, `agent`, `base`

Eliminar siempre: `scope_notification_api_key`, `service_notification_api_key`

### Commons (preguntables)

| Modulo | Pregunta |
|--------|----------|
| `cert_manager` | Ya tenes cert-manager instalado? |
| `istio` | Ya tenes Istio instalado? |
| `external_dns` | Ya tenes external-dns configurado? |
| `prometheus` | Ya tenes Prometheus instalado? |

## Paso 2: Preguntar por cada componente Cloud

> **Input**: Lista de modulos Cloud
> **Output**: Lista de modulos a mantener vs excluir

Para cada modulo Cloud, preguntar: **"Ya tenes un {recurso} o necesitas que lo cree?"**

- **Crear nuevo** → Mantener el bloque module
- **Ya tengo uno** → Agregar a lista de excluidos, resolver dependencias en paso 3

### Orden de preguntas (respetar dependencias)

1. `resource_group` (muchos dependen de este)
2. `vnet` (depende de resource_group)
3. `aks` (depende de resource_group, vnet)
4. `acr` (depende de resource_group)
5. `dns` (depende de resource_group)
6. `private_dns` (depende de resource_group, vnet)
7. `base_security` (depende de resource_group)

> Si el usuario crea `resource_group`, no preguntar por sus dependencias en otros modulos.

## Paso 3: Resolver dependencias de modulos excluidos

> **Input**: Lista de modulos excluidos, `main.tf`
> **Output**: Valores de reemplazo para cada output referenciado

Cuando el usuario dice "ya tengo" un recurso:

1. Buscar todas las referencias `module.{modulo_excluido}.{output}` en modulos que se mantienen
2. Pedir al usuario el valor real de cada referencia encontrada
3. Guardar los valores (se usan en paso 5)

### Deteccion dinamica

```bash
grep -oP 'module\.{modulo_excluido}\.\w+' infrastructure/azure/main.tf | sort -u
```

### Ejemplos

**Resource Group excluido** → preguntar: nombre del RG, location (si referenciada)

**VNet excluida** → preguntar: ID de subnet para AKS, ID de VNet

**base_security excluido** → preguntar: ID del NSG publico, ID del NSG privado

## Paso 4: Preguntar por componentes Commons

> **Input**: Lista de modulos Commons
> **Output**: Lista de modulos Commons a mantener vs excluir

Para cada modulo Commons: **"Ya tenes {componente} instalado o lo instalamos?"**

- **Instalar** → Mantener el bloque module
- **Ya tengo** → Eliminar (generalmente sin outputs referenciados por otros modulos)

## Paso 5: Aplicar cambios a los archivos .tf

> **Input**: Modulos a excluir (pasos 2+4), valores de reemplazo (paso 3), todos los `.tf`
> **Output**: Archivos `.tf` limpios, `terraform.tfvars` actualizado, `existing-resources.properties`

Limpiar **todos** los archivos `.tf`, no solo `main.tf`:

### 5.1 main.tf
- Eliminar bloques `module` de recursos excluidos
- Eliminar siempre `scope_notification_api_key` y `service_notification_api_key`
- Eliminar `depends_on` que referencien modulos eliminados
- Reemplazar `module.{excluido}.{output}` con `var.existing_{output}`

### 5.2 variables.tf
- Eliminar variables huerfanas (buscar `var.{nombre}` en todos los `.tf`, si no aparece → eliminar)
- Agregar variables nuevas para recursos existentes (`var.existing_*`)

### 5.3 locals.tf
- Eliminar locals huerfanos (buscar `local.{nombre}` en todos los `.tf`, si no aparece → eliminar)

### 5.4 outputs.tf
- Eliminar outputs que referencian modulos eliminados

### 5.5 data blocks
- Eliminar bloques `data` huerfanos en cualquier `.tf`

### 5.6 terraform.tfvars
- Agregar valores de recursos existentes: `existing_resource_group_name = "mi-rg"`

### 5.7 existing-resources.properties
- Guardar como documentacion: `resource_group_name=mi-rg-existente`

> `existing-resources.properties` es documentacion. Los valores reales van en `terraform.tfvars`.

## Paso 6: Validar archivos .tf

> **Input**: Archivos `.tf` modificados, `terraform.tfvars`
> **Output**: Archivos validados, listos para `tofu plan`/`tofu apply`

```bash
cd infrastructure/azure
tofu fmt
tofu init
tofu validate
```

- **Si pasa** → Continuar con paso 5 de SKILL.md (DNS)
- **Si falla** → Leer error, corregir, repetir. Causas comunes:
  - Referencia a modulo eliminado sin reemplazo
  - Variable sin definir o sin valor en tfvars
  - `depends_on` apuntando a modulo eliminado
  - Output referenciando modulo eliminado
  - Local huerfano
