# Create Service Flow

## Path A: From Reference Example

Use the reference repository defined in `np-service-guide` (Reference Repository section).

1. **Clone/update reference repo**:
   ```bash
   git clone https://github.com/nullplatform/services /tmp/np-services-reference 2>/dev/null \
     || (cd /tmp/np-services-reference && git pull)
   ```
2. **List available examples** (dynamically):
   ```bash
   find /tmp/np-services-reference -name "service-spec.json.tpl" -not -path "*/.git/*" | \
     xargs -I{} sh -c 'echo "---"; dirname {} | sed "s|/tmp/np-services-reference/||"; jq "{name, slug, selectors}" {}'
   ```
3. **AskUserQuestion**: offer found examples + "Otro (crear servicio nuevo)"
4. **Copy structure** from reference to local repo:
   ```bash
   cp -r /tmp/np-services-reference/<path-to-example>/ services/<new-slug>/
   ```
5. **Adapt files**:
   - `specs/service-spec.json.tpl`: change name, slug, adjust schema
   - `specs/links/connect.json.tpl`: adjust selectors
   - `values.yaml`: update config values
   - `entrypoint/service` and `entrypoint/link`: verify provider path
   - `deployment/main.tf`: adjust resources for chosen variants
6. **Show summary** and suggest `/np-service-craft register <slug>`

## Path B: New Service (Research-First Guided Discovery)

El flujo investiga primero y propone defaults inteligentes. El usuario confirma o ajusta en vez de diseñar desde cero.

### Phase 1: What is the service?

AskUserQuestion: "Describe what service you want to create" (free text)

### Phase 2: Research

**ANTES de hacer mas preguntas**, investigar:

1. **Clonar repo de referencia** (ver np-service-guide, Reference Repository) y buscar un servicio similar al que el usuario describió. Leer su spec, deployment, y workflows para entender el patrón.

2. **Buscar documentación del terraform provider** relevante (via web si es necesario) para entender qué recursos existen, qué parámetros tienen, y cuáles son los defaults razonables.

3. **Armar una propuesta** con:
   - Slug y nombre sugeridos
   - Provider y categoria inferidos
   - Lista de campos para el spec con tipos, defaults, y si son requeridos
   - Qué campos son output (post-provisioning) vs input (usuario elige)
   - Si tiene links, qué niveles de acceso y qué credenciales expone
   - Qué recursos terraform va a crear

### Phase 3: Propose and Confirm

Presentar la propuesta completa al usuario con AskUserQuestion. Cada pregunta debe tener un **default pre-investigado**. Ejemplo:

> Basándome en la documentación de AWS S3 y el servicio de referencia `azure-cosmos-db`, propongo:
>
> **Nombre**: AWS S3 Bucket | **Slug**: `aws-s3-bucket` | **Provider**: AWS | **Category**: Storage
>
> **Campos del spec (lo que el usuario ve al crear)**:
> - `bucket_name` (string, requerido) - Nombre del bucket
> - `region` (enum: us-east-1, us-west-2, eu-west-1, default: us-east-1)
> - `versioning` (boolean, default: true)
> - `encryption` (boolean, default: true)
>
> **Campos output (auto-populated post-creación)**:
> - `bucket_arn` (export: true)
> - `bucket_region` (export: true)
>
> **Link (connect)**: access levels read / write / read-write
> - Credenciales: `access_key_id` (export), `secret_access_key` (export secret)
>
> Querés ajustar algo?

El usuario solo dice "si" o tweakea lo que necesite. No tiene que diseñar nada desde cero.

### Phase 4: Generate Files

Con la propuesta confirmada, generar todos los archivos usando `np-service-specs` y `np-service-workflows` para las convenciones. Usar el servicio de referencia como base de los templates (workflows, scripts, entrypoint) adaptando al provider y recursos específicos.

### Phase 7: Validate

```bash
SLUG="<slug>"
# Schema in attributes.schema
jq -e '.attributes.schema.type' services/$SLUG/specs/service-spec.json.tpl
# No specification_schema
jq -e '.specification_schema' services/$SLUG/specs/service-spec.json.tpl && echo "ERROR" || echo "OK"
# Links use attributes.schema
for f in services/$SLUG/specs/links/*.json.tpl; do jq -e '.attributes.schema' "$f"; done
# Valid JSON
jq . services/$SLUG/specs/*.json.tpl services/$SLUG/specs/links/*.json.tpl
# Scripts executable
chmod +x services/$SLUG/entrypoint/* services/$SLUG/scripts/*/
# Entrypoint has bridge
grep -q "NULLPLATFORM_API_KEY" services/$SLUG/entrypoint/entrypoint || echo "ERROR: missing bridge"
# build_context merges parameters
grep -q 'parameters' services/$SLUG/scripts/*/build_context || echo "WARNING: missing parameters merge"
```

Show summary and suggest `/np-service-craft register <slug>`.
