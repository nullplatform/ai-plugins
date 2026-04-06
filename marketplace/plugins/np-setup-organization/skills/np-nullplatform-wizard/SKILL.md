---
name: np-nullplatform-wizard
description: This skill should be used when the user asks to "configure nullplatform resources", "setup dimensions", "create service definitions", "configure scope types", or needs to configure core nullplatform resources including scopes, dimensions, and service definitions via Terraform.
---

# Nullplatform Config Wizard

Configura los recursos de Nullplatform: scopes, dimensions y service definitions.

## Cuando Usar

- Configurando scope definitions (deployment targets)
- Creando dimensions de ambiente (dev/staging/prod)
- Registrando service definitions
- Configurando metadata schemas y policies

## Prerequisitos

1. Verificar que `organization.properties` existe y tiene el organization_id
2. Invocar `/np-api check-auth` para verificar autenticacion

## Templates de Referencia

Los templates estan en `nullplatform/example/` - **NO SE APLICAN DIRECTAMENTE**.

```text
nullplatform/
├── example/                    # Templates de referencia
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── *.tf                        # Tu implementacion real (cuando se cree)
```

## Que Se Crea

### Scope Definitions

Define como las aplicaciones se despliegan en Kubernetes:

| Scope | Descripcion | Acciones |
| ----- | ----------- | -------- |
| **K8s Containers** | Containers standard | create, delete, deploy, rollback |
| **Scheduled Tasks** | Jobs periodicos | create, delete, deploy, trigger |

### Dimensions

Clasificacion de ambientes para scopes:

| Dimension | Descripcion |
| --------- | ----------- |
| `development` | Ambientes de desarrollo |
| `staging` | Pre-produccion |
| `production` | Trafico real |

### Service Definitions

Templates para crear servicios cloud:

| Servicio | Tipo | Descripcion |
| -------- | ---- | ----------- |
| Endpoint Exposer | dependency | Expone endpoints de aplicaciones |
| (Custom services) | dependency | Se pueden agregar mas en segunda iteracion |

### Metadata Schemas (Opcional)

Schemas para trackear atributos de aplicaciones:

- Code coverage
- Security vulnerabilities
- FinOps costs
- Custom metadata

## Workflow del Wizard

### 1. Verificar que no existe configuracion

```bash
ls nullplatform/*.tf 2>/dev/null || echo "No hay configuracion - proceder"
```

### 2. Copiar templates (excepto main.tf)

```bash
# Copiar todos los templates EXCEPTO main.tf (se genera dinamicamente)
for f in nullplatform/example/*.tf; do
  [ "$(basename "$f")" = "main.tf" ] && continue
  cp "$f" nullplatform/
done
```

> **Nota**: Los templates incluyen archivos opcionales:
> - `metadata.tf` - Schemas de metadata (requiere `nrn_namespace`)
> - `policies.tf` - Approval policies (requiere `nrn_namespace`)
>
> Estos archivos son **opcionales** y requieren un NRN de namespace (no account).
> Si no los necesitas o dan error, renombralos a `.tf.disabled`:
> ```bash
> mv nullplatform/metadata.tf nullplatform/metadata.tf.disabled
> mv nullplatform/policies.tf nullplatform/policies.tf.disabled
> ```

### 3. Generar o customizar main.tf

El `main.tf` de nullplatform se genera dinamicamente siguiendo [references/nullplatform-generation.md](references/nullplatform-generation.md).

1. **Verificar si existe `nullplatform/main.tf`**

   ```bash
   ls nullplatform/main.tf 2>/dev/null
   ```

   - **Si NO existe** -> Leer [references/nullplatform-generation.md](references/nullplatform-generation.md) y seguir su flujo completo (preguntas al usuario, patrones de modulos, outputs mapping, validacion)
   - **Si existe** -> Preguntar con AskUserQuestion:
     - **Regenerar desde cero** -> Eliminar el actual, leer [references/nullplatform-generation.md](references/nullplatform-generation.md) y seguir su flujo
     - **Customizar el existente** -> Leer el main.tf actual y preguntar que cambios hacer
     - **Dejarlo como esta** -> Ir al paso 4

2. Despues de generar/modificar, validar:

   ```bash
   cd nullplatform
   tofu init -backend=false
   tofu validate
   ```

3. Si `tofu validate` falla, corregir ANTES de continuar con el paso 4.

### 4. Personalizar variables

El wizard te ayuda a configurar:

- `organization_id` (desde organization.properties)
- `environments` (lista de dimensions)
- `tags_selectors` (para matching)

### 5. Aplicar

```bash
cd nullplatform
tofu init
tofu apply
```

## Variables Requeridas

| Variable | Descripcion | Origen |
| -------- | ----------- | ------ |
| `organization_id` | ID de la organizacion | organization.properties |
| `np_api_key` | API key de Nullplatform | NP_API_KEY/np-api-skill.key (recomendado) |
| `environments` | Lista de dimensions | terraform.tfvars |
| `tags_selectors` | Tags para matching | terraform.tfvars |

## Outputs

Despues de aplicar, estos valores se exportan para usar en bindings:

```hcl
# Scope K8s
service_specification_id           # ID del service spec
service_slug                       # Slug del service spec

# Scope Scheduled Task
service_specification_id_scheduled_task
service_slug_scheduled_task

# Endpoint Exposer
service_specification_slug_endpoint_exposer
service_specification_id_endpoint_exposer
```

## Validacion

Verificar que los recursos se crearon:

Invocar `/np-api` para consultar:

| Informacion requerida | Entidad a consultar |
|-----------------------|---------------------|
| Service specifications | service_specifications de la organization |
| Dimensions configuradas | dimensions de la organization |

## Troubleshooting

### Service Spec no aparece

- Verificar `organization_id` en organization.properties
- Verificar autenticacion con check_auth.sh

### Dimension no se crea

- Verificar que no existe una dimension con el mismo nombre
- Revisar logs de terraform

## Siguiente Paso

Una vez configurado Nullplatform, conectar con servicios externos:

**Decile a Claude**: "Configuremos los bindings"

O invoca directamente: `/np-nullplatform-bindings-wizard`
