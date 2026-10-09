#!/usr/bin/env bash
# Desarma el caso prod_deploy_gate, en orden inverso a apply.sh:
#
#   1. desvincula la checklist de la approval action y borra la action
#   2. soft-delete de todas las versiones activas de la checklist specification
#   3. desactiva el alias live del workflow y borra sus notification channels
#      (el deactivate no siempre los borra, y un canal vivo sigue disparando el workflow)
#   4. borra el secreto NP_API_KEY del workflow
#
# La definicion del workflow NO se puede borrar por API: queda sin alias activo,
# asi que no recibe nada. Si despues corres apply.sh, la reusa.
#
# Uso:  ./destroy.sh [--yes]      (sin --yes, muestra lo que va a borrar y pregunta)
#       NP_API_KEY / NP_NRN igual que apply.sh.
set -euo pipefail
cd "$(dirname "$0")"

API=https://api.nullplatform.com
SPEC_NAME=poc-prod-deploy-gate
# Dimension que separa los ambientes y su valor protegido. Si el cliente usa otros
# nombres, cambiarlos aca, en apply.sh y en checklist.json (ver governance-cases.md).
DIMENSION=environment
GATED_VALUE=production

tfvar() { sed -nE "s/^$1[[:space:]]*=[[:space:]]*\"(.*)\".*/\1/p" ../../../common.tfvars 2>/dev/null | head -1; }
NP_API_KEY="${NP_API_KEY:-$(tfvar np_api_key)}"
NP_NRN="${NP_NRN:-$(tfvar nrn)}"
: "${NP_API_KEY:?falta NP_API_KEY}" "${NP_NRN:?falta NP_NRN}"
NRN_Q="$(jq -rn --arg v "$NP_NRN" '$v | @uri')"
# Un workflow por NRN: la key (y el pathPrefix del trigger) llevan el ultimo tramo
# del NRN, p.ej. namespace-3. Asi dos governance_nrn de la misma org no se pisan.
NRN_LAST="${NP_NRN##*:}"
WF_KEY="poc-release-in-lower-env-${NRN_LAST/=/-}"

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
ACTION="$(api GET "/approval/action?nrn=$NRN_Q&entity=deployment&limit=200" | jq -c --arg nrn "$NP_NRN" \
  --arg d "$DIMENSION" --arg v "$GATED_VALUE" '
  [.results[] | select(.status == "active" and .nrn == $nrn and .action == "deployment:create"
                       and .dimensions == {($d): $v})] | first // empty')"
ACTION_ID=""; FOREIGN_ID=""
if [ -n "$ACTION" ]; then
  if own_action "$ACTION"; then ACTION_ID="$(jq -r .id <<<"$ACTION")"; else FOREIGN_ID="$(jq -r .id <<<"$ACTION")"; fi
fi
SPEC_IDS="$(api GET "/approval/checklist/specification?nrn=$NRN_Q&status=active&limit=100&name:contains=$SPEC_NAME" \
  | jq -r --arg n "$SPEC_NAME" '.results[] | select(.name == $n) | .id')"
WF_ID="$(api GET "/workflows/definitions/$WF_KEY" 2>/dev/null | jq -r '.workflow.id // empty' || true)"
SECRET_ID=""; CHANNEL_IDS=""
[ -n "$WF_ID" ] && CHANNEL_IDS="$(api GET "/notification/channel?nrn=$NRN_Q&limit=200" \
  | jq -r --arg wf "$WF_ID" '.results[] | select(.status == "active" and ((.configuration.url // "") | contains($wf))) | .id')"
[ -n "$WF_ID" ] && SECRET_ID="$(api GET "/workflows/config?workflow=$WF_ID" \
  | jq -r '.data[] | select(.name == "NP_API_KEY") | .id')"

echo "Se va a borrar en $NP_NRN:"
echo "  approval action:   ${ACTION_ID:-(no existe)}"
[ -n "$FOREIGN_ID" ] && echo "  (la approval action $FOREIGN_ID no es de este caso: no se toca)"
echo "  specifications:    $(echo ${SPEC_IDS:-(no existen)})"
echo "  workflow:          ${WF_ID:-(no existe)}  -> desactivar alias live"
echo "  canales:           $(echo ${CHANNEL_IDS:-(no existen)})"
echo "  secreto NP_API_KEY: ${SECRET_ID:-(no existe)}"
if [ "${1:-}" != "--yes" ]; then
  read -r -p "Confirmas? [y/N] " ans
  [[ "$ans" =~ ^[yYsS]$ ]] || { echo "Cancelado."; exit 1; }
fi

# --- Borrado ----------------------------------------------------------------
if [ -n "$ACTION_ID" ]; then
  api DELETE "/approval/action/$ACTION_ID/checklist_specification" >/dev/null
  api DELETE "/approval/action/$ACTION_ID" >/dev/null
  echo "==> approval action $ACTION_ID desvinculada y borrada"
fi

for id in $SPEC_IDS; do
  api DELETE "/approval/checklist/specification/$id" >/dev/null
  echo "==> specification $id -> deleted"
done

if [ -n "$WF_ID" ]; then
  api POST "/workflows/definitions/$WF_ID/aliases/live/deactivate" '{}' >/dev/null
  echo "==> workflow $WF_ID: alias live desactivado"
  for ch in $CHANNEL_IDS; do
    api DELETE "/notification/channel/$ch" >/dev/null 2>&1 || true
    echo "==> notification channel $ch borrado"
  done
fi

if [ -n "$SECRET_ID" ]; then
  api DELETE "/workflows/config/$SECRET_ID" >/dev/null
  echo "==> secreto NP_API_KEY borrado"
fi

echo
echo "Listo."
