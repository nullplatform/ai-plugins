# check-cloud: Verificar Cloud

## Flujo con Detección Automática

### Paso 1: Detectar Cloud Provider

```bash
ls -d infrastructure/*/ 2>/dev/null | grep -v example
```

Si no se detecta ninguna carpeta, preguntar cuál usar.

### Paso 2: Extraer Configuración de Cuenta desde Terraform

#### AWS

Buscar en archivos de Terraform (orden de prioridad):

```bash
# 1. Profile en terraform.tfvars
grep -E '^aws_profile\s*=' infrastructure/aws/terraform.tfvars 2>/dev/null

# 2. Profile en backend.tf
grep -E 'profile\s*=' infrastructure/aws/backend.tf 2>/dev/null

# 3. Account ID en comentarios o NRN
grep -E 'account.*=.*[0-9]{12}|arn:aws:.*:[0-9]{12}:' infrastructure/aws/*.tf infrastructure/aws/*.tfvars 2>/dev/null

# 4. Bucket de S3 del backend
grep -E 'bucket\s*=' infrastructure/aws/backend.tf 2>/dev/null
```

#### Azure

```bash
grep -E 'subscription_id|tenant_id' infrastructure/azure/*.tf infrastructure/azure/*.tfvars 2>/dev/null
```

#### GCP

```bash
grep -E 'project\s*=' infrastructure/gcp/*.tf infrastructure/gcp/*.tfvars 2>/dev/null
```

### Paso 3: Mapear Perfil a Account ID

Si se detectó un profile de AWS:

```bash
grep -A10 "\[profile {PROFILE_NAME}\]" ~/.aws/config | grep -E 'sso_account_id|role_arn' | head -1
```

### Paso 4: Mostrar Información Detectada

Mostrar tabla con lo detectado (provider, profile, region, account ID).

### Paso 5: Verificar Acceso Actual

```bash
aws sts get-caller-identity 2>&1
```

- **Si acceso exitoso**: comparar account ID actual vs requerido. Si coinciden, mostrar éxito. Si no coinciden, advertir mismatch.
- **Si acceso falla**: ir al flujo de autenticación guiada.

### Flujo de Autenticación Guiada

**Si se detectó un profile en Terraform:**

Ofrecer con AskUserQuestion:
- **Sí, autenticar con {PROFILE_NAME}** → `aws sso login --profile {PROFILE_NAME}`
- **Usar otro profile** → Listar profiles que matcheen el account ID
- **Continuar sin acceso cloud** → Omitir verificación

**Si hay múltiples profiles válidos para el mismo account:** mostrar lista y preguntar cuál usar.

**Si NO hay profiles compatibles:** mostrar perfiles disponibles con sus accounts y ofrecer: configurar nuevo profile SSO, usar Access Keys, o continuar sin acceso.

### Autenticación por Provider

#### AWS
```bash
aws sso login --profile {PROFILE_NAME}
aws sts get-caller-identity --profile {PROFILE_NAME}
export AWS_PROFILE={PROFILE_NAME}
```

#### Azure
```bash
az login
az account set --subscription {SUBSCRIPTION_ID}
```

#### GCP
```bash
gcloud auth login
gcloud config set project {PROJECT_ID}
```

### Si elige "Continuar sin acceso cloud"

Informar que no se podrá verificar infra cloud, K8s puede funcionar si ya tiene kubeconfig, y la API funciona normalmente. Marcar check-cloud como "skipped" y continuar con check-k8s.
