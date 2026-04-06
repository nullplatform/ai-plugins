---
name: np-nullplatform-bindings-wizard
description: This skill should be used when the user asks to "connect GitHub", "setup container registry", "bind cloud provider", "configure bindings", "link external service", or needs to connect nullplatform with external services like GitHub, container registries (ECR, ACR, GCR), and cloud providers.
---

# Nullplatform Bindings Wizard

Conecta Nullplatform con servicios externos: GitHub, container registry, cloud provider.

## Cuando Usar

- Configurando integracion con GitHub
- Conectando container registry (ECR/ACR/Artifact Registry)
- Configurando cloud provider en Nullplatform
- Creando channel associations para routear a agentes

## Prerequisitos

> **IMPORTANTE**: Este wizard REQUIERE que `/np-nullplatform-wizard` se haya ejecutado primero.
> Los channel associations dependen de los scopes y dimensions creados en ese paso.

1. Verificar que `organization.properties` existe y tiene el organization_id
2. Invocar `/np-api check-auth` para verificar autenticacion
3. Invocar `/np-api` para verificar que existen scopes (si no hay, ejecutar `/np-nullplatform-wizard` primero):
   - Consultar service_specifications de la organization

## Templates de Referencia

Los templates estan en `nullplatform-bindings/example/` - **NO SE APLICAN DIRECTAMENTE**.

```text
nullplatform-bindings/
├── example/                    # Templates de referencia
│   ├── main.tf
│   ├── data.tf
│   ├── locals.tf
│   └── variables.tf
└── *.tf                        # Tu implementacion real (cuando se cree)
```

## Que Se Crea

### Code Repository

Conexion con GitHub para source code:

| Configuracion | Descripcion |
| ------------- | ----------- |
| `git_provider` | `github` |
| `github_organization` | Nombre de tu org en GitHub |
| `github_installation_id` | ID de la GitHub App instalada |

### Asset Repository (ECR/ACR/Artifact Registry)

Storage de imagenes Docker. El modulo `asset_repository` crea:

**En AWS (ECR):**

| Recurso AWS | Nombre | Proposito |
| ----------- | ------ | --------- |
| IAM Role | `nullplatform-{cluster}-application-role` | Permite a Nullplatform asumir rol para crear repos |
| IAM Policy | `nullplatform-{cluster}-ecr-manager-policy` | Permisos ECR: create/delete repo, push/pull images |
| IAM User | `nullplatform-{cluster}-build-workflow-user` | Usuario para CI/CD pipelines |
| IAM Access Key | (generada) | Credenciales para el usuario de build |

**En Nullplatform:**

| Recurso | Tipo | Proposito |
| ------- | ---- | --------- |
| Provider Config | `ecr` | Registra credenciales AWS para crear repos automaticamente |

**Resumen por cloud:**

| Cloud | Registry | Variables |
| ----- | -------- | --------- |
| AWS | ECR | Automatico via IAM |
| Azure | ACR | `login_server`, `username`, `password` |
| GCP | Artifact Registry | `login_server`, `username`, `password` |

### Cloud Provider Binding

Vincula Nullplatform con tu cloud. El modulo `cloud_provider` crea:

**En Nullplatform:**

| Recurso | Tipo | Proposito |
| ------- | ---- | --------- |
| Provider Config | `aws-configuration` / `azure-configuration` / `gcp-configuration` | Configura dominio, DNS zones, region |

**Configuracion:**

| Configuracion | Descripcion |
| ------------- | ----------- |
| `domain_name` | Dominio para las aplicaciones |
| `hosted_public_zone_id` | Zone ID de Route53 publica (AWS) |
| `hosted_private_zone_id` | Zone ID de Route53 privada (AWS) |
| `resource_group` | Resource group (Azure) |
| `dimensions` | Mapeo de dimensions |

### Channel Associations

Routea deployments al cluster correcto:

| Association | Descripcion |
| ----------- | ----------- |
| K8s Containers | Asocia scope k8s con agente |
| Scheduled Tasks | Asocia scheduled tasks con agente |
| Endpoint Exposer | Asocia endpoint exposer con agente |

### Metrics

Conexion con Prometheus para metricas:

| Configuracion | Descripcion |
| ------------- | ----------- |
| `prometheus_url` | URL del Prometheus server |
| `dimensions` | Dimensions para metricas |

## Workflow del Wizard

### 1. Verificar que no existe configuracion

```bash
ls nullplatform-bindings/*.tf 2>/dev/null || echo "No hay configuracion - proceder"
```

### 2. Copiar templates (excepto main.tf)

```bash
# Copiar todos los templates EXCEPTO main.tf (se genera dinamicamente)
for f in nullplatform-bindings/example/*.tf; do
  [ "$(basename "$f")" = "main.tf" ] && continue
  cp "$f" nullplatform-bindings/
done
```

### 2b. Generar o customizar main.tf

El `main.tf` de nullplatform-bindings se genera dinamicamente siguiendo [references/bindings-generation.md](references/bindings-generation.md).

1. **Verificar si existe `nullplatform-bindings/main.tf`**

   ```bash
   ls nullplatform-bindings/main.tf 2>/dev/null
   ```

   - **Si NO existe** -> Leer [references/bindings-generation.md](references/bindings-generation.md) y seguir su flujo completo (preguntas al usuario, patrones de modulos, validacion). Esta capa no tiene outputs obligatorios ya que no hay capas downstream que la consuman.
   - **Si existe** -> Preguntar con AskUserQuestion:
     - **Regenerar desde cero** -> Eliminar el actual, leer [references/bindings-generation.md](references/bindings-generation.md) y seguir su flujo
     - **Customizar el existente** -> Leer el main.tf actual y preguntar que cambios hacer
     - **Dejarlo como esta** -> Ir al paso 3

2. Despues de generar/modificar, validar:

   ```bash
   cd nullplatform-bindings
   tofu init -backend=false
   tofu validate
   ```

3. Si `tofu validate` falla, corregir ANTES de continuar con el paso 3.

### 3. Configurar Code Repository

Segun el code repository elegido en el paso 2b (flujo del bindings-generation):

**GitHub:**
1. Instalar la GitHub App: **https://github.com/apps/nullplatform-github-integration**
2. Seleccionar la organizacion y repositorios
3. Obtener el Installation ID desde: `https://github.com/organizations/TU-ORG/settings/installations/XXXXX`

**GitLab:**
1. Obtener un access token con permisos de API
2. Configurar group path, installation URL, collaborators, repository prefix y slug

**Azure DevOps:**
1. Obtener un personal access token
2. Configurar project name y agent pool

### 4. Aplicar

```bash
cd nullplatform-bindings
tofu init
tofu apply
```

### 5. Validación Post-Apply (REQUERIDO)

Después de `tofu apply`, verificar que los bindings funcionan correctamente.

#### 5.1 Verificar Providers

```bash
# Obtener organization_id de organization.properties
ORG_ID=$(grep organization_id organization.properties | cut -d= -f2)

# Verificar provider de código (GitHub)
/np-api fetch-api "/provider?nrn=organization%3D${ORG_ID}&specification_slug=code_repository"

# Verificar provider de registry (ECR)
/np-api fetch-api "/provider?nrn=organization%3D${ORG_ID}&specification_slug=ecr"
```

#### 5.2 Verificar Notification Channels

```bash
# Listar canales creados
/np-api fetch-api "/notification/channel?nrn=organization%3D${ORG_ID}&showDescendants=true"
```

#### 5.3 Verificar API Keys de Canales

Para cada canal de tipo `agent`, verificar que la API key tiene los roles correctos:

```bash
# 1. Obtener detalles del canal
/np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"

# 2. Buscar la API key por nombre (ej: SCOPE_DEFINITION_AGENT_ASSOCIATION)
/np-api fetch-api "/api-key?name=SCOPE_DEFINITION_AGENT_ASSOCIATION"

# 3. Ver los grants de la API key
/np-api fetch-api "/api-key/{api_key_id}"
```

**Roles requeridos para notification channels:**

| Rol | Propósito |
|-----|-----------|
| `controlplane:agent` | Comunicación con control plane |
| `ops` | Ejecutar comandos en el agente |

#### 5.4 Checklist de Validación

| Check | Comando | Esperado |
|-------|---------|----------|
| Provider GitHub existe | `/provider?specification_slug=code_repository` | 1+ resultado |
| Provider ECR existe | `/provider?specification_slug=ecr` | 1+ resultado |
| Channel existe | `/notification/channel?nrn=...` | 1+ resultado |
| API key tiene `controlplane:agent` | `/api-key/{id}` → grants | Presente |
| API key tiene `ops` | `/api-key/{id}` → grants | Presente |

## Variables Requeridas

| Variable | Descripcion | Origen |
| -------- | ----------- | ------ |
| `organization_id` | ID de la organizacion | organization.properties |
| `np_api_key` | API key de Nullplatform | NP_API_KEY/np-api-skill.key (recomendado) |
| Variables del code repo | Dependen del provider elegido (github_*, gitlab_*, azure_*) | terraform.tfvars |

## Validacion

```bash
# Leer organization_id
Invocar `/np-api` para consultar:

| Informacion requerida | Entidad a consultar |
|-----------------------|---------------------|
| Providers de GitHub | providers de tipo `code_repository` de la organization |
| Providers de Registry | providers de tipo `docker_server` de la organization |
| Notification channels | notification channels de la organization |

## Troubleshooting

### GitHub Connection Fails

- Verificar que la GitHub App esta instalada en la org
- Verificar installation_id es correcto
- Verificar que la App tiene permisos en los repos

### Registry Auth Fails

- Verificar credenciales no expiraron
- Para Azure: regenerar password si es necesario
- Para GCP: verificar service account tiene permisos

### Agent No Recibe Notificaciones

- Verificar `tags_selectors` coinciden entre channel y agent
- Verificar agent esta corriendo: `kubectl get pods -n nullplatform-tools`
- Revisar logs del agent

### Aplicacion Falla con "Error creating ECR repository"

Este error ocurre cuando una aplicacion se crea **ANTES** de que el binding de container registry este configurado.

> **IMPORTANTE**: Las aplicaciones fallidas por este motivo **NO se recuperan automaticamente**
> cuando se agregan los bindings despues. Hay que eliminarlas y recrearlas.

**Para resolver:**

1. Verificar que `module "asset_repository"` esta habilitado en `nullplatform-bindings/main.tf`
2. Ejecutar `tofu apply` en `nullplatform-bindings/`
3. Verificar que el provider ECR existe via API:

   ```bash
   np-api fetch "/provider?nrn=organization=XXX:account=YYY&show_descendants=true"
   ```

4. **ELIMINAR** la aplicacion fallida desde la UI de Nullplatform
5. **Recrear** la aplicacion - ahora funcionara correctamente

## Siguiente Paso

Con los bindings configurados, tu cuenta Nullplatform esta lista para deployar aplicaciones.

**Opciones:**

1. Crear tu primera aplicacion en la UI de Nullplatform
2. Debuggear o explorar: `/np-api`
