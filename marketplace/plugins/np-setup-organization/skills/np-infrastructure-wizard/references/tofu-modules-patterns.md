# Patrones Generales de OpenTofu

> Aplica a todos los clouds. Los archivos por cloud (`aws.md`, `azure.md`, etc.) referencian este documento para patrones compartidos.

## Contenido

1. [Como leer variables de un modulo](#como-leer-variables-de-un-modulo)
2. [Flujo de lectura de modulos](#flujo-de-lectura-de-modulos)
3. [Source de modulos (git ref)](#source-de-modulos-git-ref)
4. [Provider versions genericas](#provider-versions-genericas)
5. [Helm v3 syntax](#helm-v3-syntax)
6. [Modulo Agent API Key](#modulo-agent-api-key)

## Como leer variables de un modulo

Al leer `variables.tf` de cualquier modulo:

1. **Variables sin `default`**: incluirlas siempre, son requeridas
2. **Variables con `default` que tienen bloque `validation`**: leer el `error_message` para entender en que contexto son requeridas. Si el contexto aplica, incluirlas
3. **Variables con `default` sin `validation`**: incluirlas solo si se necesita cambiar el default

**IMPORTANTE**: No saltear el paso 2. Las variables con `validation` condicional son la causa mas comun de errores en `tofu plan`. Siempre revisar todos los bloques `validation` antes de generar codigo.

## Flujo de lectura de modulos

Antes de usar cualquier modulo:
1. Leer `variables.tf` del modulo (preferir `.terraform/modules/{nombre}/variables.tf` despues de `tofu init`)
2. Incluir todas las variables sin default
3. Revisar los bloques `validation` de las variables con default y agregar las que apliquen al contexto
4. Variables con default sin validation: agregar solo si se necesita cambiar el default

> Tip: Usar `tofu init -backend=false` para descargar modulos sin necesitar credenciales del backend, luego inspeccionar `.terraform/modules/`.

## Source de modulos (git ref)

Todos los modulos de nullplatform se referencian con git ref:

```hcl
source = "git::https://github.com/nullplatform/tofu-modules.git//{path}?ref={version}"
```

Obtener la ultima version:
```bash
git ls-remote --tags https://github.com/nullplatform/tofu-modules.git | sort -t/ -k3 -V | tail -1
```

## Provider versions genericas

Providers compartidos por todos los clouds:

```hcl
kubernetes = { source = "hashicorp/kubernetes",  version = "~> 2.0" }
helm       = { source = "hashicorp/helm",        version = "~> 3.0" }
nullplatform = { source = "nullplatform/nullplatform", version = "~> 0.0.74" }
```

Cada cloud agrega su provider especifico (ej: `aws ~> 6.0`, `azurerm ~> 4.0`).

## Helm v3 syntax

Helm provider v3 cambia la sintaxis del bloque `kubernetes`:

```hcl
# Correcto (Helm v3): con "="
provider "helm" {
  kubernetes = {
    host = "..."
  }
}

# Incorrecto (Helm v2): sin "="
provider "helm" {
  kubernetes {
    host = "..."
  }
}
```

## Modulo Agent API Key

El modulo `agent_api_key` genera una API key en runtime para el modulo `agent`. Se usa en todos los clouds:

```hcl
module "agent_api_key" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref={version}"
  type   = "agent"
  nrn    = var.nrn
}
```

Luego usar `module.agent_api_key.api_key` solo en el modulo `agent` (en vez de `var.np_api_key` directo). El modulo `base` sigue usando `var.np_api_key`.
