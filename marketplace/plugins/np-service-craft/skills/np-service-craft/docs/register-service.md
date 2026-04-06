# Register Service in Terraform

## Prerequisites

- `services/<name>/specs/service-spec.json.tpl` must exist and be valid JSON
- Los directorios `nullplatform/` y `nullplatform-bindings/` deben existir con terraform configurado

## Terraform Base Structure

El registro usa dos directorios de terraform separados en la raiz del repo:

- **`nullplatform/`** — Service definitions. Contiene los modules `service_definition` (uno por servicio), outputs, variables (`nrn`, `np_api_key`), provider nullplatform, y `common.tfvars` con los valores.
- **`nullplatform-bindings/`** — Agent associations. Contiene los modules `service_definition_agent_association` (uno por servicio), variables (`nrn`, `np_api_key`, `tags_selectors`), provider nullplatform, y un `data.tf` que lee el state de `nullplatform/` via `terraform_remote_state` para acceder a los outputs (slug, id).

Son dos directorios separados porque el binding necesita el `service_specification_slug` como output del service_definition. Se aplican en orden: primero `nullplatform/`, despues `nullplatform-bindings/`.

Si los directorios no existen, crearlos con los archivos base (providers.tf, variables.tf, common.tfvars, data.tf). Preguntar al usuario por el `nrn` y `np_api_key` si no los tiene.

## Module Source of Truth

Los modulos viven en `https://github.com/nullplatform/tofu-modules`:
- `nullplatform/service_definition` — creates service_specification + link_specification
- `nullplatform/service_definition_agent_association` — creates notification_channel

**ANTES de generar terraform**, clonar el repo y leer los `variables.tf` de cada modulo para determinar variables mandatorias y opcionales:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Leer tambien `main.tf` y `locals.tf` para entender como se construyen los recursos internamente.

## Flow

### 1. Read service spec

```bash
jq '{name, slug, selectors}' services/<name>/specs/service-spec.json.tpl
```

### 2. Check not already registered

```bash
grep -c "service_definition_<slug>" nullplatform/main.tf
```

### 3. Ask user: local or remote

**ANTES de generar terraform**, preguntar al usuario con AskUserQuestion:

> Como queres registrar el servicio?
>
> **Local (recomendado para testing)**: Lee los specs directo del filesystem. No necesitas subir nada a GitHub, podes iterar rapido.
>
> **Remoto (para produccion)**: Lee los specs desde un repositorio GitHub/GitLab. Requiere que el repo exista y los specs esten pusheados.

Esta decision determina el `git_provider` del modulo:
- **Local** → `git_provider = "local"` + `local_specs_path` apuntando al directorio del servicio
- **Remoto** → `git_provider = "github"` (default) + `repository_org`, `repository_name`, `repository_branch`. Si el repo es privado, tambien `repository_token`.

Para el binding (`service_definition_agent_association`):
- **Local** → `base_clone_path = pathexpand("~/.np")` (apunta al symlink local)
- **Remoto** → omitir `base_clone_path` (usa el default `/root/.np` del agente en k8s)

### 4. Generate terraform

Leer las variables de los modulos de `/tmp/tofu-modules-ref/` y generar:

1. **nullplatform/main.tf**: module `service_definition_<slug>` con las variables mandatorias del modulo + `git_provider = "local"` y `local_specs_path` si es modo local.
2. **nullplatform/outputs.tf**: outputs para `service_specification_slug` y `service_specification_id`.
3. **nullplatform-bindings/main.tf**: module `service_definition_agent_association` con las variables mandatorias. Para dev local, setear `base_clone_path = pathexpand("~/.np")`.

Para el binding, el modulo construye el cmdline internamente — leer `main.tf` del modulo para entender el patron.

### 5. Apply

```bash
cd nullplatform && tofu init && tofu apply -var-file=common.tfvars
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../nullplatform/common.tfvars
```

Verify: `/np-api fetch-api "/service_specification?nrn=<nrn>&show_descendants=true"`

For the pre-registration checklist, see `np-service-creator` skill.
