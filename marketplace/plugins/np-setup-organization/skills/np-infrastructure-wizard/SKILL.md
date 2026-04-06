---
name: np-infrastructure-wizard
description: Crea infraestructura cloud para Nullplatform. Usar cuando se necesite configurar VPC/VNet, clusters Kubernetes (EKS/AKS/GKE/OKE/ARO), ingress (Istio/ALB), DNS zones, backend de tfstate, y desplegar el agente de Nullplatform. Soporta AWS, Azure, Azure ARO, GCP y OCI.
---

# Nullplatform Infrastructure Wizard

## Prerequisitos

1. Verificar que `organization.properties` existe y tiene el `organization_id`
2. Invocar `/np-api check-auth` para verificar autenticacion
3. Verificar credenciales cloud segun provider (ver [references/variables.md](references/variables.md))

## Estructura del Proyecto

La carpeta `infrastructure/{cloud}/` se crea durante `/np-setup-orchestrator init` (paso 3). El `main.tf` NO se crea en ese paso: se genera dinamicamente en el paso 4 de este wizard usando [references/infrastructure-generation.md](references/infrastructure-generation.md).

La fuente de verdad para los modulos y sus variables es el repo `nullplatform/tofu-modules` (branch `main`). Para patrones generales de OpenTofu (source de modulos, Helm v3) ver [references/tofu-modules-patterns.md](references/tofu-modules-patterns.md).

`common.tfvars` vive en la raiz del proyecto (no dentro de `infrastructure/`). Lo genera `/np-setup-orchestrator init` y contiene variables compartidas: `nrn`, `np_api_key`, `organization_slug`, `tags_selectors`. Se pasa a tofu con `-var-file="../../common.tfvars"`.

Para detalle de recursos por cloud ver [references/resources-by-cloud.md](references/resources-by-cloud.md).

## Workflow

### 1. Seleccionar Account de Nullplatform

1. Usar `/np-api` para listar los accounts existentes
2. Mostrar las opciones con ID y nombre
3. Si no hay accounts, indicar que lo cree via `np` CLI

El NRN resultante tendra formato: `organization={org_id}:account={account_id}`

### 2. Detectar estructura existente

```bash
ls -d infrastructure/*/ 2>/dev/null
```

- **Si existe** → Detectar el cloud provider, continuar con paso 3
- **Si NO existe** → Indicar que ejecute `/np-setup-orchestrator init` primero

### 3. Configurar Backend (tfstate)

Configurar ANTES de cualquier `tofu init`.

1. Leer `infrastructure/{cloud}/backend.tf`
2. Preguntar: **"Queres guardar el tfstate en la nube o local?"**
   - **Local** → Comentar todo el contenido de `backend.tf` (dejar el archivo pero con todo comentado). Tofu usara state local por defecto.
   - **Nube** → Continuar con 3.3
3. Preguntar: **"Ya tenes un storage remoto o necesitas crear uno?"**
   - **Ya tengo** → Pedir los valores segun cloud (ver tabla en [references/resources-by-cloud.md](references/resources-by-cloud.md)) y completar `backend.tf`
   - **No tengo** →
     - **Si es AWS**: Preguntar: "Queres que lo cree con tofu usando el modulo backend de tofu-modules, o lo creas manualmente?"
       - **Con tofu**: Clonar `nullplatform/tofu-modules` modulo `infrastructure/aws/backend/`, ejecutar `tofu init` y `tofu apply` (crea bucket S3 con versioning, encryption y object lock). Luego completar `backend.tf` con los valores del output.
       - **Manual**: Indicar que cree el bucket S3 (con versioning y encryption) y vuelva cuando este listo.
     - **Otros clouds**: Indicar que lo cree via consola del cloud o CLI y vuelva cuando este listo.
     - El storage del tfstate NO se gestiona con el mismo Terraform que lo usa (chicken-and-egg problem).
4. Si es Azure ARO y no tiene `backend.tf`, crear uno con backend `azurerm`

### 4. Generar o Customizar main.tf

El `main.tf` de infrastructure se genera dinamicamente siguiendo [references/infrastructure-generation.md](references/infrastructure-generation.md).

1. **Verificar si existe `infrastructure/{cloud}/main.tf`**

   ```bash
   ls infrastructure/{cloud}/main.tf 2>/dev/null
   ```

   - **Si NO existe** → Leer [references/infrastructure-generation.md](references/infrastructure-generation.md) y seguir su flujo completo (preguntas al usuario, wiring entre modulos, validacion)
   - **Si existe** → Preguntar con AskUserQuestion:
     - **Regenerar desde cero** → Eliminar el actual, leer [references/infrastructure-generation.md](references/infrastructure-generation.md) y seguir su flujo
     - **Customizar el existente** → Leer el arbol de decision del cloud detectado:
       - [references/azure.md](references/azure.md)
       - [references/aws.md](references/aws.md)
       - [references/azure-aro.md](references/azure-aro.md)
       - [references/gcp.md](references/gcp.md)
       - [references/oci.md](references/oci.md)
     - **Dejarlo como esta** → Ir al paso 5

2. Despues de generar/modificar, validar:

   ```bash
   cd infrastructure/{cloud}
   tofu init -backend=false
   tofu validate
   ```

3. Si `tofu validate` falla, corregir ANTES de continuar con el paso 5.

Los modulos de Nullplatform (`agent_api_key`, `agent`, `base`) siempre se incluyen. Eliminar siempre `scope_notification_api_key` y `service_notification_api_key`.

### 5. Crear DNS Zone y Verificar Delegacion

Completar ANTES del apply general. Sin delegacion DNS, el certificado SSL queda en PENDING_VALIDATION (timeout de 1h+).

#### 5.1 Verificar delegacion existente

```bash
dig NS {slug}.nullapps.io +short
```

- **Si devuelve NS records** → Continuar con paso 6
- **Si vacio** → Seguir con 5.2

#### 5.2 Crear solo la DNS Zone

Buscar el nombre del modulo DNS en `infrastructure/{cloud}/main.tf` (puede ser `module.dns`, `module.route53`, `module.cloud_dns`, etc. segun el cloud).

```bash
cd infrastructure/{cloud}
tofu init
tofu apply -target=module.{nombre_modulo_dns}
```

#### 5.3 Obtener NS records

Usar el comando correspondiente al cloud (AWS: `aws route53`, Azure: `az network dns zone show`, GCP: `gcloud dns`, OCI: `oci dns zone get`).

#### 5.4 Solicitar delegacion a Nullplatform

Generar mensaje con: subzona (`{slug}.nullapps.io`), cuenta destino, NS records a agregar.

#### 5.5 Verificar delegacion

```bash
dig NS {slug}.nullapps.io +short
```

- **Si devuelve NS records** → Continuar con paso 6
- **Si vacio** → Esperar propagacion DNS (usualmente minutos, max 48h)

### 6. Validar sesion cloud

Sin sesion valida, el `tofu apply` fallara.

1. Leer `terraform.tfvars` para extraer la cuenta configurada
2. Verificar sesion activa con el comando del cloud (ver [references/variables.md](references/variables.md))
3. Comparar cuenta activa vs requerida:
   - **Coinciden** → Continuar con paso 7
   - **No coinciden** → Advertir y ofrecer autenticarse
   - **Sin sesion** → DETENERSE. No continuar sin sesion cloud valida.

### 7. Plan y Apply de infraestructura

#### 7.1 Plan

```bash
cd infrastructure/{cloud}
tofu plan -var-file="../../common.tfvars" -var-file="terraform.tfvars"
```

Mostrar resumen al usuario: cantidad de recursos a crear/modificar/destruir. Pedir confirmacion.

#### 7.2 Apply (con confirmacion)

```bash
tofu apply -var-file="../../common.tfvars" -var-file="terraform.tfvars"
```

## Post-Apply

Validacion y troubleshooting: ver [references/troubleshooting.md](references/troubleshooting.md).

## Siguiente Paso

Invocar `/np-nullplatform-wizard` para configurar Nullplatform.
