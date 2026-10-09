#!/usr/bin/env bash
# Desarma el caso nonprod_sizing, en orden inverso a apply.sh:
#
#   1. desvincula la checklist y borra las approval actions scope:create / scope:write
#      de los ambientes no productivos
#   2. soft-delete de todas las versiones activas de la checklist specification
#
# Uso:  ./destroy.sh [--yes]      (sin --yes, muestra lo que va a borrar y pregunta)
#       NP_API_KEY / NP_NRN igual que apply.sh.
set -euo pipefail
cd "$(dirname "$0")"

API=https://api.nullplatform.com
SPEC_NAME=poc-nonprod-sizing
# Dimension que separa los ambientes y sus valores no productivos. Si el cliente usa
# otros nombres, cambiarlos aca y en apply.sh (ver governance-cases.md).
DIMENSION=environment
NONPROD_ENVS="development staging"
ACTIONS="scope:create scope:write"

tfvar() { sed -nE "s/^$1[[:space:]]*=[[:space:]]*\"(.*)\".*/\1/p" ../../../common.tfvars 2>/dev/null | head -1; }
NP_API_KEY="${NP_API_KEY:-$(tfvar np_api_key)}"
NP_NRN="${NP_NRN:-$(tfvar nrn)}"
: "${NP_API_KEY:?falta NP_API_KEY}" "${NP_NRN:?falta NP_NRN}"
NRN_Q="$(jq -rn --arg v "$NP_NRN" '$v | @uri')"

TOKEN="$(curl -sS --fail-with-body -X POST "$API/token" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg k "$NP_API_KEY" '{api_key: $k}')" | jq -r .access_token)"

api() { # api METHOD PATH [JSON]  -- si falla, muestra la respuesta del server en stderr
  local out rc=0
  if [ $# -ge 3 ]; then
    out="$(curl -sS --fail-with-body -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d "$3")" || rc=$?
  else
    out="$(curl -sS --fail-with-body -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN")" || rc=$?
  fi
  [ "$rc" -eq 0 ] || { echo "ERROR $1 $2 -> $out" >&2; return "$rc"; }
  printf '%s\n' "$out"
}

# Solo se borran actions de este caso (vinculadas a una checklist llamada SPEC_NAME).
# Una action ajena que matchee (nrn, action, dimensiones) no se toca.
own_action() { # own_action <action-json>: 0 si es del caso, 1 si no; corta si no puede leer
  local sid name
  sid="$(jq -r '.checklist_specification_id // empty' <<<"$1")"
  [ -n "$sid" ] || return 1
  # Un error de API no es "ajena": se corta aca, con la causa, en vez de clasificarla mal.
  name="$(api GET "/approval/checklist/specification/$sid" | jq -r .name)" \
    || { echo "ERROR: no se pudo leer la checklist $sid de la approval action $(jq -r .id <<<"$1"); reintentar." >&2; exit 1; }
  [ "$name" = "$SPEC_NAME" ]
}

# --- Que hay ----------------------------------------------------------------
CANDIDATES="$(api GET "/approval/action?nrn=$NRN_Q&entity=scope&limit=200" | jq -c \
  --arg nrn "$NP_NRN" --arg actions "$ACTIONS" --arg envs "$NONPROD_ENVS" --arg d "$DIMENSION" '
  .results[] | select(.status == "active" and .nrn == $nrn
    and (.action as $a | $actions | split(" ") | index($a))
    and (.dimensions | keys == [$d])
    and (.dimensions[$d] as $e | $envs | split(" ") | index($e)))')"
ACTION_IDS=""; FOREIGN_IDS=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  if own_action "$a"; then ACTION_IDS="$ACTION_IDS $(jq -r .id <<<"$a")"; else FOREIGN_IDS="$FOREIGN_IDS $(jq -r .id <<<"$a")"; fi
done <<<"$CANDIDATES"
SPEC_IDS="$(api GET "/approval/checklist/specification?nrn=$NRN_Q&status=active&limit=100&name:contains=$SPEC_NAME" \
  | jq -r --arg n "$SPEC_NAME" '.results[] | select(.name == $n) | .id')"

echo "Se va a borrar en $NP_NRN:"
echo "  approval actions: $(echo ${ACTION_IDS:-(no existen)})"
[ -n "$FOREIGN_IDS" ] && echo "  (no son de este caso, no se tocan:$FOREIGN_IDS)"
echo "  specifications:   $(echo ${SPEC_IDS:-(no existen)})"
if [ "${1:-}" != "--yes" ]; then
  read -r -p "Confirmas? [y/N] " ans
  [[ "$ans" =~ ^[yYsS]$ ]] || { echo "Cancelado."; exit 1; }
fi

# --- Borrado ----------------------------------------------------------------
for id in $ACTION_IDS; do
  api DELETE "/approval/action/$id/checklist_specification" >/dev/null
  api DELETE "/approval/action/$id" >/dev/null
  echo "==> approval action $id desvinculada y borrada"
done

for id in $SPEC_IDS; do
  api DELETE "/approval/checklist/specification/$id" >/dev/null
  echo "==> specification $id -> deleted"
done

echo
echo "Listo."
