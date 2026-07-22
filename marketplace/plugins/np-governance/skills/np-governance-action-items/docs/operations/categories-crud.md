# Categories CRUD

Scripts para gestionar action item categories. Endpoints bajo `/governance/action_item_category`.

## list_categories.sh

```bash
list_categories.sh \
  --nrn "organization=1" \
  [--name "Security Vulnerability"] \
  [--parent-id <id>] \
  [--status active|inactive] \
  [--offset 0] [--limit 25]
```

El backend soporta wildcards en NRN: `organization=1:account=*` lista todas. También resuelve herencia: pasar un NRN específico devuelve sus propias categorías + todas las heredadas de ancestros.

## get_category.sh

```bash
get_category.sh --id <category_id>
```

Incluye `parent` y `children` en la respuesta.

## ensure_category.sh ⭐

Search-or-create idempotent. Es el script clave para inicialización de agentes.

```bash
ensure_category.sh \
  --nrn "organization=1" \
  --name "Security Vulnerability" \
  [--slug "security-vulnerability"] \
  [--description "..."] \
  [--color "#DC2626"] \
  [--icon "shield"] \
  [--unit-name "Risk Score"] \
  [--unit-symbol "R"] \
  [--config '{"max_deferral_days":90,"max_deferral_count":3}'] \
  [--parent-id <id>]
```

Output: `{id, slug, was_created}` donde `was_created=true` si recién la creó, `false` si ya existía.

La idempotencia se basa en `--name`, que es la clave de unicidad real de la API: las categorías son únicas por `(name, nrn)`. `--slug` es opcional y **no** se usa para buscar — la API genera el slug desde el name (un contador global puede agregar `-N`), así que el slug guardado puede diferir del que pases; el slug real viene en el output.

Comportamiento:
1. Hace `GET /governance/action_item_category?nrn=...&name=<name>` y matchea el name exacto (el endpoint no filtra por slug; ese param se ignora).
2. Si existe, retorna esa categoría con `was_created=false`.
3. Si no, hace POST con los args restantes. Si el POST choca con un `(name, nrn)` ya existente (carrera o corrida previa), re-consulta por name y devuelve la existente en vez de fallar.

## create_category.sh

```bash
create_category.sh \
  --nrn "organization=1" \
  --name "Security Vulnerability" \
  [--description "..."] \
  [--color "#DC2626"] \
  [--icon "shield"] \
  [--unit-name "Risk Score"] \
  [--unit-symbol "R"] \
  [--config '{...}'] \
  [--parent-id <id>]
```

Failure modes:
- 409 si ya existe `(name, nrn)` — usar `ensure_category.sh` en su lugar
- 400 si `parent_id` apunta a una categoría que ya tiene parent (max 2 niveles)

## update_category.sh

```bash
update_category.sh --id <id> \
  [--name "..."] \
  [--description "..."] \
  [--color "..."] \
  [--icon "..."] \
  [--unit-name "..."] \
  [--unit-symbol "..."] \
  [--config '{...}']
```

PATCH parcial. No se puede cambiar `nrn` ni `parent_id` después de crear.

## delete_category.sh

```bash
delete_category.sh --id <id>
```

Failure modes:
- 400 si la categoría tiene action items asociados
- 400 si tiene children (jerarquía)

Para "deshabilitar" sin borrar, usar `update_category.sh` con un campo `status=inactive` (si está soportado en tu deployment).

## Pattern: setup categories en startup del agente

```bash
#!/bin/bash
set -e
NRN="organization=1"

# Cada agente declara las categorías que necesita
SECURITY_CAT=$(ensure_category.sh \
  --nrn "$NRN" \
  --slug "security-vulnerability" \
  --name "Security Vulnerability" \
  --description "CVEs and security issues" \
  --color "#DC2626" --icon "shield" \
  --unit-name "Risk Score" --unit-symbol "R" \
  --config '{"max_deferral_days":90}' | jq -r .id)

COST_CAT=$(ensure_category.sh \
  --nrn "$NRN" \
  --slug "cost-optimization" \
  --name "Cost Optimization" \
  --color "#059669" --icon "dollar" \
  --unit-name "Dollars per Month" --unit-symbol "\$" \
  --config '{"max_deferral_count":3}' | jq -r .id)

echo "Categories ready: security=$SECURITY_CAT cost=$COST_CAT"
```

Esto se corre **una vez** al inicio del agente y los IDs se cachean. Es seguro re-ejecutar.
