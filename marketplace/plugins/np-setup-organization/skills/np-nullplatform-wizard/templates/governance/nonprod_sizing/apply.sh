#!/usr/bin/env bash
# Crea en nullplatform todo lo que hace andar el caso nonprod_sizing
# ("scopes de NON-PROD: autoscaling deshabilitado, 128 MB de memoria como maximo, 1 instancia"):
#
#   1. checklist specification poc-nonprod-sizing (3 conditions, sin workflow)
#   2. approval actions scope:create y scope:write por cada ambiente no productivo
#      (scope:write cubre editar un scope ya creado para subirle recursos)
#   3. vinculo de cada action -> checklist
#
# Si una condicion falla, la creacion/edicion del scope se rechaza (on_policy_fail: deny).
# Se puede re-ejecutar: actualiza lo que existe en vez de duplicarlo.
#
# Uso:  NP_API_KEY=... NP_NRN='organization=1:account=2[:namespace=3]' ./apply.sh
#       (si no estan exportadas, se leen de common.tfvars en la raiz del repo)
# Requiere: curl, jq.
set -euo pipefail
cd "$(dirname "$0")"

API=https://api.nullplatform.com
SPEC_NAME=poc-nonprod-sizing
# Dimension que separa los ambientes y sus valores no productivos. Si el cliente usa
# otros nombres, cambiarlos aca y en destroy.sh (ver governance-cases.md).
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

# Una action que ya existe solo se reusa si es de este caso: vinculada a una
# checklist llamada SPEC_NAME. Si es de otro, destroy.sh la borraria, asi que no se adopta.
own_action() { # own_action <action-json>: 0 si es del caso, 1 si no; corta si no puede leer
  local sid name
  sid="$(jq -r '.checklist_specification_id // empty' <<<"$1")"
  [ -n "$sid" ] || return 1
  # Un error de API no es "ajena": se corta aca, con la causa, en vez de clasificarla mal.
  name="$(api GET "/approval/checklist/specification/$sid" | jq -r .name)" \
    || { echo "ERROR: no se pudo leer la checklist $sid de la approval action $(jq -r .id <<<"$1"); reintentar." >&2; exit 1; }
  [ "$name" = "$SPEC_NAME" ]
}

echo "==> 1/2 Checklist specification"
# Un nombre borrado no se puede volver a crear (POST da 400 "already exists",
# aunque se pase otra version). Se revive con PATCH sobre la ultima version
# borrada, que genera una version nueva activa.
SPECS="$(for st in active deleted; do
  api GET "/approval/checklist/specification?nrn=$NRN_Q&status=$st&limit=100&name:contains=$SPEC_NAME"
done | jq -sc --arg n "$SPEC_NAME" '[.[].results[] | select(.name == $n)]')"
SPEC="$(jq -c '[.[] | select(.status == "active")] | max_by(.version) // empty' <<<"$SPECS")"
DELETED_ID="$(jq -r '[.[] | select(.status == "deleted")] | max_by(.version) | .id // empty' <<<"$SPECS")"
if [ -z "$SPEC" ] && [ -n "$DELETED_ID" ]; then
  SPEC_ID="$(api PATCH "/approval/checklist/specification/$DELETED_ID" \
    "$(jq -n --slurpfile d checklist.json '{definition: $d[0]}')" | jq -r .id)"
  echo "    recreada $SPEC_ID (a partir de la version borrada $DELETED_ID)"
elif [ -z "$SPEC" ]; then
  SPEC_ID="$(api POST /approval/checklist/specification "$(jq -n --arg nrn "$NP_NRN" --arg n "$SPEC_NAME" \
    --slurpfile d checklist.json '{nrn: $nrn, name: $n, created_by: "poc-automation", definition: $d[0]}')" | jq -r .id)"
  echo "    creada $SPEC_ID"
else
  SPEC_ID="$(jq -r .id <<<"$SPEC")"
  if [ "$(api GET "/approval/checklist/specification/$SPEC_ID" | jq -S .definition)" != "$(jq -S . checklist.json)" ]; then
    # Cada update crea una version nueva con otro id.
    SPEC_ID="$(api PATCH "/approval/checklist/specification/$SPEC_ID" \
      "$(jq -n --slurpfile d checklist.json '{definition: $d[0]}')" | jq -r .id)"
    echo "    nueva version $SPEC_ID"
  else
    echo "    sin cambios $SPEC_ID"
  fi
fi

echo "==> 2/2 Approval actions + vinculo"
EXISTING="$(api GET "/approval/action?nrn=$NRN_Q&entity=scope&limit=200")"
for action in $ACTIONS; do
  for env in $NONPROD_ENVS; do
    BODY="$(jq -n --arg nrn "$NP_NRN" --arg a "$action" --arg d "$DIMENSION" --arg e "$env" '{nrn: $nrn,
      entity: "scope", action: $a, dimensions: {($d): $e}, on_policy_success: "approve",
      on_policy_fail: "deny", on_checklist_fail: "deny"}')"
    # on_checklist_fail es lo que lee el modo checklist: "deny" = el pedido queda auto_denied.
    ACTION="$(jq -c --argjson w "$BODY" '[.results[] | select(.status == "active" and .nrn == $w.nrn
      and .action == $w.action and .dimensions == $w.dimensions)] | first // empty' <<<"$EXISTING")"
    if [ -z "$ACTION" ]; then
      ID="$(api POST /approval/action "$BODY" | jq -r .id)"; what=creada; created=1
    else
      ID="$(jq -r .id <<<"$ACTION")"; what="ya existe"; created=0
      own_action "$ACTION" || { echo "ERROR: ya existe la approval action $ID ($action {$DIMENSION: $env}) y no es de este caso. Borrala o desvinculala de su checklist antes de aplicar." >&2; exit 1; }
      if [ "$(jq -r '.on_checklist_fail // empty' <<<"$ACTION")" != "deny" ]; then
        api PATCH "/approval/action/$ID" '{"on_checklist_fail": "deny"}' >/dev/null
        what="ya existe (on_checklist_fail -> deny)"
      fi
    fi
    # Si el vinculo falla con una action recien creada, se borra (si no, quedaria como ajena).
    api POST "/approval/action/$ID/checklist_specification" "{\"checklist_specification_id\": \"$SPEC_ID\"}" >/dev/null || {
      [ "$created" = 1 ] && api DELETE "/approval/action/$ID" >/dev/null \
        && echo "    se borro la action $ID recien creada (fallo el vinculo)" >&2
      exit 1
    }
    echo "    $action {$DIMENSION: $env}: $what $ID -> $SPEC_ID"
  done
done

echo
echo "Listo: checklist $SPEC_ID"
