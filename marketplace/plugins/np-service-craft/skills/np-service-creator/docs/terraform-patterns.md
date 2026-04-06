# Terraform Patterns Reference

## Source of Truth

Siempre clonar y leer los modulos antes de generar terraform:

```bash
git clone https://github.com/nullplatform/tofu-modules /tmp/tofu-modules-ref 2>/dev/null \
  || (cd /tmp/tofu-modules-ref && git pull)
```

Archivos a leer:
- `nullplatform/service_definition/variables.tf` — variables del modulo (las sin default son mandatorias)
- `nullplatform/service_definition/main.tf` — como crea los recursos
- `nullplatform/service_definition/locals.tf` — como resuelve los specs (HTTP vs file segun git_provider)
- `nullplatform/service_definition/data.tf` — data sources HTTP (desactivados cuando git_provider = "local")
- `nullplatform/service_definition_agent_association/variables.tf` — variables del binding
- `nullplatform/service_definition_agent_association/main.tf` — como construye el cmdline y el channel

No copiar ejemplos de este archivo como template — generar el terraform leyendo las variables del modulo y adaptando al servicio concreto.

## Local vs Remote

- **Local** (`git_provider = "local"`): usa `file()` para leer specs del filesystem. No requiere push.
- **Remote** (`git_provider = "github"` o `"gitlab"`): usa `data "http"` para leer specs del repo. Requiere push.

## Apply Order

```bash
cd nullplatform && tofu init && tofu apply -var-file=common.tfvars
cd ../nullplatform-bindings && tofu init && tofu apply -var-file=../nullplatform/common.tfvars
```
