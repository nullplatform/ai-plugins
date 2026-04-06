# Infrastructure Layer Generator

Generador del `main.tf` para la capa **infrastructure/** de Nullplatform con OpenTofu.

> **IMPORTANTE**: No supongas valores ni configuraciones. Ante cualquier duda, divergencia o ambiguedad, **siempre pregunta al usuario** antes de generar codigo.

> **VALIDACION OBLIGATORIA**: Antes de generar o modificar cualquier codigo, checklist:
> 1. Lei el `variables.tf` del modulo descargado? (Regla tecnica #7)
> 2. Incluí todas las variables requeridas y verifique los bloques `validation` de las opcionales?
> 3. Estoy infiriendo algun valor que deberia preguntar al usuario?
> 4. El `dns_type` coincide con el esquema de networking elegido? (Regla dns_type)
> 5. Estoy usando el modulo en lugar de crear recursos directamente?
> 6. Los bloques de modulos estan limpios, sin comentarios inline?
> 7. Las variables dependientes del esquema se incluyen con placeholders, sin preguntar?

> **INSTRUCCIONES DE EJECUCION**:
> 1. Seguir el flujo de preguntas usando `AskUserQuestion` - NO asumir configuraciones
> 2. Ejecutar `tofu init -backend=false` para descargar los modulos
> 3. **OBLIGATORIO ANTES DE GENERAR**: Leer el `variables.tf` de CADA modulo desde `.terraform/modules/` (version descargada). NO generar main.tf sin haber leido TODOS los variables.tf primero. Los nombres de variables en este documento pueden estar desactualizados; la fuente de verdad es siempre el modulo descargado.
> 4. Generar el main.tf usando SOLO los nombres de variables leidos de los modulos descargados
> 5. Ejecutar `tofu validate` para verificar
> 6. Si validate falla, corregir ANTES de dar por terminado
> 7. **NO hacer cambios** al codigo ya generado sin confirmacion explicita del usuario

## Estructura generada

```
infrastructure/{cloud}/
├── main.tf                 # GENERADO por este wizard
├── variables.tf
├── provider.tf
├── backend.tf
├── locals.tf
├── data.tf                 # Data sources para recursos existentes
├── outputs.tf
└── terraform.tfvars.example
```

---

## Flujo de preguntas

### Paso 1: Configuracion base
1. **Cloud provider**: aws | azure | gcp
2. **Output directory**: donde generar (default: `./`)

### Paso 2: Backend
- **Crear backend nuevo o usar existente?**
  - **Crear nuevo** -> Genera carpeta `backend/` con modulo `infrastructure/{cloud}/backend`
  - **Usar existente** -> Pide datos del storage remoto existente

### Paso 3: Infraestructura base (crear o existente)

Para cada componente, pregunta si se debe crear o ya existe:

- **VPC/VNet**: Crear -> modulo `infrastructure/{cloud}/vpc` | Existente -> pide `vpc_id`, usa data sources
- **Cluster (EKS/AKS/GKE)**: Crear -> modulo `infrastructure/{cloud}/eks|aks|gke` | Existente -> pide `cluster_name`, usa data sources para endpoint, CA, OIDC
- **DNS Zones**: Crear -> modulo `infrastructure/{cloud}/route53|cloud-dns|azure-dns` | Existente -> pide `public_zone_id`, `private_zone_id`

**Cuando un recurso es existente**: declarar variable + data source en `data.tf`. Los modulos que dependen del recurso usan el data source en vez de `module.X.output`.

### Paso 4: Esquema de Networking

El ALB Controller es **siempre requerido**. Preguntar esquema:

**Esquema Istio (Recomendado):**
- ALB Controller, Istio, Cert Manager + IAM, External DNS + IAM, Prometheus, Agent + Agent IAM, Base

**Esquema ACM + Ingress (Alternativo):**
- ALB Controller, ACM, Ingress Controller, External DNS + IAM, Prometheus, Agent + Agent IAM, Base

---

## Providers Kubernetes/Helm

La configuracion del provider depende de si el cluster se CREA o es EXISTENTE:
- **Cluster creado**: usar outputs del modulo EKS/AKS/GKE (leer `outputs.tf` del modulo descargado)
- **Cluster existente**: usar data sources (`aws_eks_cluster`, `aws_eks_cluster_auth`)

**Helm v3.x**: Usar sintaxis `kubernetes = { ... }` con `=` (objeto), NO `kubernetes { }` (bloque). Referencia: Helm Provider v3 Upgrade Guide.

**AWS Profile**: Si se soporta `aws_profile`, usar condicional en exec args para agregar `--profile` solo si no es null.

---

## Reglas de generacion

### No suponer, siempre preguntar

1. **NUNCA suponer valores de variables** - Siempre preguntar
2. **Ante cualquier duda, pregunta** - Es mejor preguntar de mas que generar codigo incorrecto
3. **Si un modulo requiere variables no mencionadas, pregunta**
4. **Si no estas seguro de que componentes incluir, pregunta**

### Reglas tecnicas

1. **Solo incluir codigo del cloud seleccionado**
2. **Version de modulos**: ejecutar `git fetch --tags && git tag --sort=-v:refname | head -1` en el repo `tofu-modules` para obtener el ultimo release. El `git fetch --tags` es obligatorio para no usar tags desactualizados del clone local.
3. **Providers requeridos**:
   - AWS: `hashicorp/aws ~> 6.0`, `hashicorp/kubernetes ~> 2.0`, `hashicorp/helm ~> 3.0`
   - Azure: `hashicorp/azurerm ~> 4.0`, `hashicorp/kubernetes ~> 2.0`, `hashicorp/helm ~> 3.0`
   - GCP: `hashicorp/google ~> 5.0`, `hashicorp/kubernetes ~> 2.0`, `hashicorp/helm ~> 3.0`
   - Todos: `nullplatform/nullplatform` - Consultar la ultima version antes de generar:
     ```bash
     curl -s "https://registry.terraform.io/v1/providers/nullplatform/nullplatform/versions" | jq -r '[.versions[].version] | sort_by(split(".") | map(tonumber)) | last'
     ```
     Usar `~> 0.0.X` con la version obtenida. NO hardcodear una version fija.
4. **Variables sensitive** marcadas correctamente
5. **Data sources** para recursos existentes (no variables redundantes)
6. **Formatear con `terraform fmt`** despues de generar
7. **Leer READMEs y variables.tf** de cada modulo desde `.terraform/modules/` antes de generar
8. **NUNCA transformar outputs entre modulos** - Pasar outputs tal cual (sin `replace`, `regex`, `split`, etc.). Si hay duda sobre el formato que espera una variable, leer el codigo interno del modulo (main.tf, iam.tf, locals.tf) para ver como se usa, no inferir por el nombre de la variable

---

## Patron interactivo con AskUserQuestion

### Paso 1: Configuracion base

```json
{
  "questions": [
    {
      "question": "Que cloud provider vas a usar?",
      "header": "Cloud",
      "options": [
        {"label": "AWS (Recommended)", "description": "Amazon Web Services - EKS, Route53, ECR"},
        {"label": "Azure", "description": "Microsoft Azure - AKS, Azure DNS"},
        {"label": "GCP", "description": "Google Cloud Platform - GKE, Cloud DNS"}
      ],
      "multiSelect": false
    }
  ]
}
```

### Paso 2: Infraestructura base

```json
{
  "questions": [
    {
      "question": "Backend para Terraform state?",
      "header": "Backend",
      "options": [
        {"label": "Crear nuevo (Recommended)", "description": "Crea storage + locking para state"},
        {"label": "Usar existente", "description": "Ya tengo storage configurado"}
      ],
      "multiSelect": false
    },
    {
      "question": "VPC/Red?",
      "header": "VPC",
      "options": [
        {"label": "Crear nueva (Recommended)", "description": "Crea VPC con subnets publicas y privadas"},
        {"label": "Usar existente", "description": "Ya tengo una VPC configurada"}
      ],
      "multiSelect": false
    },
    {
      "question": "Cluster Kubernetes?",
      "header": "K8s",
      "options": [
        {"label": "Crear nuevo (Recommended)", "description": "Crea cluster con node groups"},
        {"label": "Usar existente", "description": "Ya tengo un cluster"}
      ],
      "multiSelect": false
    },
    {
      "question": "DNS Zones?",
      "header": "DNS",
      "options": [
        {"label": "Crear nuevas (Recommended)", "description": "Crea hosted zones publica y privada"},
        {"label": "Usar existentes", "description": "Ya tengo hosted zones configuradas"}
      ],
      "multiSelect": false
    }
  ]
}
```

### Paso 3: Esquema de Networking

```json
{
  "questions": [
    {
      "question": "Que esquema de networking usar?",
      "header": "Networking",
      "options": [
        {"label": "Istio (Recommended)", "description": "Service mesh + Cert Manager + External DNS"},
        {"label": "ACM + Ingress", "description": "AWS Certificate Manager + Ingress Controller - Mas simple"}
      ],
      "multiSelect": false
    }
  ]
}
```

### Paso 4: Valores especificos

```json
{
  "questions": [
    {
      "question": "Que region?",
      "header": "Region",
      "options": [
        {"label": "us-east-1 (Recommended)", "description": "N. Virginia"},
        {"label": "us-west-2", "description": "Oregon"},
        {"label": "eu-west-1", "description": "Ireland"},
        {"label": "Otra region", "description": "Especificar manualmente"}
      ],
      "multiSelect": false
    },
    {
      "question": "Usar valores de ejemplo o reales?",
      "header": "Values",
      "options": [
        {"label": "Valores de ejemplo", "description": "Genera con placeholders"},
        {"label": "Valores reales", "description": "Te pido los valores especificos"}
      ],
      "multiSelect": false
    }
  ]
}
```

### Mostrar resumen antes de generar

```markdown
| Aspecto | Valor |
|---------|-------|
| **Cloud** | AWS |
| **Backend** | Crear nuevo |
| **VPC** | Crear nueva |
| **K8s** | Crear nuevo |
| **DNS** | Crear nuevas |
| **Networking** | Istio |
| **Region** | us-east-1 |
```

---

## Reglas de tfvars

1. **`common.tfvars`** (en raiz): Variables compartidas entre capas
   - `aws_region`, `organization`, `account`, `domain_name`, `np_api_key`, `nrn`, `tags_selectors`, `backend_bucket`
2. **`terraform.tfvars.example`** (en infrastructure/{cloud}/): Solo variables especificas de infrastructure
   - Incluir header: `# Usage: tofu plan -var-file=../../common.tfvars -var-file=./terraform.tfvars`
   - NO duplicar variables de common.tfvars

---

## Estructura correcta de modulos en infrastructure/

```hcl
# Infraestructura cloud
module "vpc" { }           # infrastructure/{cloud}/vpc
module "eks" { }           # infrastructure/{cloud}/eks (o aks/gke)
module "dns" { }           # infrastructure/{cloud}/route53 (o cloud-dns/azure-dns)

# ALB Controller
module "alb_controller" { }                    # infrastructure/{cloud}/aws_load_balancer_controller

# Componentes K8s (dependen de module.alb_controller)
module "istio" { }           # infrastructure/commons/istio
module "prometheus" { }      # infrastructure/commons/prometheus

# IAM (sin depends_on, recursos AWS puros)
module "alb_controller_iam" { }  # infrastructure/{cloud}/iam/aws_load_balancer_controller_iam (crea IAM role + K8s service account)
module "external_dns_iam" { }    # infrastructure/{cloud}/iam/external_dns
module "cert_manager_iam" { }    # infrastructure/{cloud}/iam/cert_manager
module "agent_iam" { }           # infrastructure/{cloud}/iam/agent

# Componentes que usan IAM
module "external_dns_public" { }   # infrastructure/commons/external_dns (type = "public")
module "external_dns_private" { }  # infrastructure/commons/external_dns (type = "private", create_namespace = false)
module "cert_manager" { }          # infrastructure/commons/cert_manager

# Security + Nullplatform (VAN EN INFRASTRUCTURE, NO EN BINDINGS)
module "security" { }  # infrastructure/{cloud}/security
module "agent_api_key" { }  # nullplatform/api_key (type = "agent")
module "base" { }            # nullplatform/base (recibe security_group_ids de security)
module "agent" { }           # nullplatform/agent

# Opcional (sin Istio)
module "acm" { }     # infrastructure/{cloud}/acm
module "ingress" { } # infrastructure/{cloud}/ingress
```

**IMPORTANTE**: Para cada modulo, leer su README y `variables.tf` desde `.terraform/modules/` despues de `tofu init -backend=false`. NO copiar variables de este documento - pueden estar desactualizadas.

**Referencia**: La fuente de verdad para modulos y variables es `nullplatform/tofu-modules` (branch `main`). Siempre leer los modulos descargados en `.terraform/modules/`.

---

## Cadena de dependencias (depends_on)

Los modulos que despliegan Helm charts dependen de `module.alb_controller`.

### Grafo de dependencias

```
vpc
 ├──► eks ──► alb_controller_iam ──► alb_controller
 ├──► dns                                  │
 │                    ┌────────────────────┼──────────────────┐
 │                    ▼                    ▼                  ▼
 │              istio              external_dns_public   cert_manager
 │                                      │
 │                                external_dns_private
 │
 ├──► security
 │         │
 │         ▼
 │       base (recibe security_group_ids de security)
 │         │
 │         ▼
 │       agent
 │
 └──► (esquema sin Istio)
       dns ──► acm ──► ingress
```

### Tabla de depends_on

| Modulo | depends_on |
|--------|------------|
| `eks` | `[module.vpc]` |
| `dns` | `[module.vpc]` |
| `alb_controller_iam` | `[module.eks]` |
| `alb_controller` | `[module.alb_controller_iam]` |
| `istio` | `[module.alb_controller]` |
| `external_dns_public` | `[module.alb_controller]` |
| `external_dns_private` | `[module.alb_controller, module.external_dns_public]` |
| `cert_manager` | `[module.alb_controller]` |
| `security` | `[module.eks]` |
| `base` | `[module.alb_controller]` |
| `agent` | `[module.base]` |
| `prometheus` | (sin depends_on explicito) |
| `agent_iam`, `external_dns_iam`, `cert_manager_iam` | (sin depends_on, son recursos IAM puros) |
| `acm` (sin Istio) | `[module.dns]` |
| `ingress` (sin Istio) | `[module.alb_controller, module.acm]` |

### Modulo security

El modulo `infrastructure/{cloud}/security` crea security groups para los gateways. Sus outputs se pasan al modulo `base`. Leer `outputs.tf` de security y `variables.tf` de base desde los modulos descargados para conocer los nombres exactos de outputs e inputs.

### Por que external_dns_private depende de external_dns_public?

Ambos intentan crear el namespace `external-dns`. Para evitar conflicto:
- `external_dns_public`: crea el namespace (default `create_namespace = true`)
- `external_dns_private`: usa `create_namespace = false` y depende del publico

### Por que NO usar depends_on en modulos IAM ni asset/ecr?

- Modulos IAM son recursos AWS puros (no Helm charts), no dependen del webhook
- El modulo `nullplatform/asset/ecr` (en nullplatform-bindings/) tiene configuraciones de provider locales; `depends_on` genera errores

---

## Modulos IAM: usar los existentes, NO crear resources directamente

| Modulo | Path | Proposito |
|--------|------|-----------|
| External DNS IAM | `infrastructure/{cloud}/iam/external_dns` | Rol IAM para External DNS |
| Cert Manager IAM | `infrastructure/{cloud}/iam/cert_manager` | Rol IAM para Cert Manager |
| Agent IAM | `infrastructure/{cloud}/iam/agent` | Rol IAM para Nullplatform Agent |

Leer el README y `variables.tf` de cada modulo IAM para conocer las variables requeridas.

---

## Regla de dns_type segun esquema de networking

### 30. dns_type del agent depende del esquema de networking

La variable `dns_type` del modulo agent **NO tiene valor default**, y su valor debe coincidir con el esquema:

| Esquema | dns_type | Variables adicionales del agent |
|---------|----------|---------------------------------|
| **Istio** | `external_dns` | `use_account_slug`, `image_pull_secrets`, `service_template`, `initial_ingress_path`, `blue_green_ingress_path` |
| **ACM + Ingress** | `route53` | Ninguna |

- No mezclar esquemas
- NO inferir valores para las variables de Istio - SIEMPRE preguntar al usuario

### 33. Variables dependientes del esquema NO se preguntan

Cuando el usuario selecciona Istio, las variables derivadas (`agent_use_account_slug`, `agent_service_template`, etc.) se agregan automaticamente en `variables.tf` y `terraform.tfvars.example` con placeholders. El generador pregunta la CONFIGURACION (esquema), pero las VARIABLES derivadas se incluyen para que el usuario las complete al desplegar.

### 34. agent_image_tag depende del cloud provider

| Cloud | agent_image_tag |
|-------|-----------------|
| **AWS** | `"aws"` |
| **Azure/GCP/OCI** | `"latest"` |

Se determina automaticamente, NO se pregunta al usuario.

---

## Provider stubs para nullplatform/base

Los provider stubs **solo son necesarios si `gateway_security_enabled = true`**. Por defecto es `false`:
- **gateway_security_enabled = false (default)**: NO necesitas stubs ni bloque `providers`
- **gateway_security_enabled = true**: Agregar stubs de Azure y GCP en provider.tf y bloque `providers` en el modulo base

Leer `variables.tf` del modulo `nullplatform/base` para la lista completa de variables.

---

## Como leer variables de un modulo

Al leer `variables.tf` de un modulo descargado:

1. **Variables sin `default`**: incluirlas siempre, son requeridas
2. **Variables con `default` que tienen bloque `validation`**: leer el `error_message` del validation para entender en que contexto son requeridas. Si el contexto aplica (ej: `cloud_provider = "aws"`), incluirlas
3. **Variables con `default` sin `validation`**: incluirlas solo si se necesita cambiar el default

**IMPORTANTE**: No saltear el paso 2. Las variables con `validation` condicional son la causa mas comun de errores en `tofu plan`. Siempre revisar todos los bloques `validation` de cada modulo antes de generar codigo.

---

## Wiring entre modulos: api_key

### 43. Usar modulo api_key para generar API keys en runtime

NO pasar `var.np_api_key` directamente a modulos runtime (agent, base). Usar el modulo `nullplatform/api_key`:

- En infrastructure/: crear `module "agent_api_key"` con `type = "agent"`, luego pasar `module.agent_api_key.api_key` a `module.base` y `module.agent`
- `var.np_api_key` sigue usandose para autenticar el provider nullplatform y modulos que solo necesitan auth

Tipos disponibles: `agent`, `scope_notification`, `service_notification`, `custom`.

---

## Lecciones aprendidas (gotchas)

### 1. Variables duplicadas en tfvars
Variables compartidas (`aws_region`, `np_api_key`, etc.) van solo en `common.tfvars`, no en cada `terraform.tfvars.example`.

### 2. Outputs de modulos pueden cambiar entre versiones
Siempre verificar `outputs.tf` del modulo descargado. NO asumir nombres de outputs.

### 3. Variables no declaradas
Cada capa debe declarar TODAS las variables que usa en `variables.tf`, incluso las de common.tfvars.

### 4. Backend bucket en remote state
Usar variable `backend_bucket` que viene de common.tfvars, NO hardcodear.

### 5. AWS Profile opcional
Agregar variable `aws_profile` opcional (default = null). Usar condicional en exec args de providers kubernetes/helm para agregar `--profile` solo si no es null.

### 6. Backend module
Usar el modulo `infrastructure/{cloud}/backend` directamente. NO crear recursos S3 manualmente. Leer el modulo descargado para conocer variables/outputs reales.

### 7. Variables de modulos cambian entre versiones
Leer `variables.tf` del modulo descargado para conocer variables actuales. NO asumir que variables de una version existen en otra.

### 8. Namespace gateways
El namespace `gateways` debe existir antes de aplicar cert_manager. El orden de apply es: infrastructure -> nullplatform -> nullplatform-bindings.

### 9. Provider stubs no requieren autenticacion
Para Azure stub: usar `resource_provider_registrations = "none"` (no `skip_provider_registration`).

### 10. Usar modulos IAM existentes
NUNCA crear `aws_iam_policy` o `aws_iam_role` directamente. Usar modulos de `infrastructure/{cloud}/iam/`.

### 11. NUNCA hardcodear valores
Cada valor en un modulo debe venir de una variable. `dns_type = var.dns_type`, NO `dns_type = "route53"`.

### 12. Estructura de variables consistente
Para cada variable en main.tf: declararla en `variables.tf` + agregarla en `terraform.tfvars.example` + si es compartida, en `common.tfvars.example`.

### 13. Ubicacion de modulos
`base`, `agent` y `agent_api_key` van en `infrastructure/`, NO en `nullplatform-bindings/`.

### 14. tags_selectors es variable comun
Misma variable `tags_selectors` en infrastructure/ y nullplatform-bindings/. Definirla una vez en `common.tfvars`. NO crear `agent_tags_selectors`.

### 15. Usar OpenTofu
Comandos: `tofu`, no `terraform`.

### 16. Backend S3 con profile
El bloque `backend "s3"` debe incluir `profile` si se usa AWS profile.

### 17. Dependencias y External DNS
Ver seccion "Cadena de dependencias (depends_on)" arriba. Puntos clave:
- Modulos Helm dependen de `module.alb_controller`
- External DNS: `type` y `zone_type` son variables separadas - siempre pasar ambas
- External DNS privado: `create_namespace = false`, depende del publico

### 18. Variables layer-specific
Solo poner en `common.tfvars` variables usadas en mas de un layer. Variables de infrastructure van en `infrastructure/terraform.tfvars`.

### 19. Backend module - verificar version
Leer variables.tf y outputs.tf del modulo descargado. El modulo puede no tener variables en ciertas versiones.

### 20. Orden de destroy
Inverso a creacion: nullplatform-bindings -> nullplatform -> infrastructure -> backend.

### 21. Helm releases huerfanos
Si destroy falla por cluster eliminado, remover recursos K8s del state con `tofu state rm` y re-ejecutar destroy.

### 22. Credenciales expiran en destroys largos
Si `AuthFailure`, renovar credenciales y re-ejecutar `tofu destroy`.

### 23. S3 Object Lock COMPLIANCE
No se puede bypassear. Esperar que expire la retencion.

### 24. Permisos de API key
Verificar que la API key tenga roles para todas las operaciones del modulo (provider + CLI `np`).

### 25. Leer modulos descargados
Ejecutar `tofu init -backend=false` PRIMERO. Leer desde `.terraform/modules/`, NUNCA desde la raiz del repo.

### 26. Confirmar antes de modificar
No modificar codigo ya generado sin confirmacion explicita del usuario.

### 27. Verificar reverts
Despues de revertir, `grep -r` para verificar que no quedan referencias residuales.

### 28. Validar inmediatamente
Despues de generar: `tofu init -backend=false && tofu validate`. Corregir antes de dar por terminado.

### 29. Outputs obligatorios para consumo de capas downstream

La capa `infrastructure/` DEBE exportar estos outputs en `outputs.tf` para que `nullplatform-bindings/` los consuma via remote state:

| Output requerido | Descripcion | Consumidor en bindings |
|-----------------|-------------|----------------------|
| `cluster_name` | Nombre del cluster K8s | asset_repository |
| `domain_name` | Dominio de aplicaciones | cloud_provider |
| `public_zone_id` | Zone ID DNS publica | cloud_provider |
| `private_zone_id` | Zone ID DNS privada | cloud_provider |

Los valores de cada output dependen de los modulos usados. Leer `outputs.tf` de cada modulo descargado para conocer los nombres reales. Si se agrega un recurso que otras capas necesitan, siempre exportarlo como output.

### 30. Mostrar resumen de variables antes de tofu apply

**OBLIGATORIO** antes de ejecutar `tofu apply`: mostrar una tabla con TODAS las variables que usan los modulos, indicando:

| Variable | Modulo(s) | Origen | Valor |
|----------|-----------|--------|-------|
| `var_name` | modulo que la usa | `common.tfvars` / `terraform.tfvars` / `default en variables.tf` | valor actual |

- Incluir variables con valores default (no solo las de tfvars)
- Marcar variables sensitive como `(sensitive)`
- Indicar si alguna variable esta declarada pero no se usa en ningun modulo
- Esperar confirmacion del usuario antes de ejecutar el apply
