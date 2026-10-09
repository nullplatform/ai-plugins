#!/usr/bin/env bash
# Crea en nullplatform el caso prod_deploy_gate: una checklist sobre los deploys a produccion
# con los chequeos que eligio el wizard (checklist.json, armado desde items/*.json):
#
#   1. workflow poc-release-in-lower-env-<ultimo tramo del NRN> + alias live activo (su trigger
#      crea el notification channel) -- solo si checklist.json incluye release_in_lower_env
#   2. secreto NP_API_KEY de ese workflow (lee scopes, deployments y releases)
#   3. checklist specification poc-prod-deploy-gate
#   4. approval action deployment:create {DIMENSION: GATED_VALUE}
#   5. vinculo action -> checklist
#
# Se puede re-ejecutar: actualiza lo que existe en vez de duplicarlo.
#
# Uso:  NP_API_KEY=... NP_NRN='organization=1:account=2' ./apply.sh
#       (si no estan exportadas, se leen de common.tfvars en la raiz del repo)
# Requiere: curl, jq.
set -euo pipefail
cd "$(dirname "$0")"

API=https://api.nullplatform.com
SPEC_NAME=poc-prod-deploy-gate
KIND=poc-release-in-lower-env   # external.kind del item release_in_lower_env
# Dimension que separa los ambientes y su valor protegido. Si el cliente usa otros
# nombres, cambiarlos aca, en destroy.sh y en checklist.json (ver governance-cases.md).
DIMENSION=environment
GATED_VALUE=production

tfvar() { sed -nE "s/^$1[[:space:]]*=[[:space:]]*\"(.*)\".*/\1/p" ../../../common.tfvars 2>/dev/null | head -1; }
NP_API_KEY="${NP_API_KEY:-$(tfvar np_api_key)}"
NP_NRN="${NP_NRN:-$(tfvar nrn)}"
: "${NP_API_KEY:?falta NP_API_KEY}" "${NP_NRN:?falta NP_NRN}"
ORG_ID="${NP_NRN#organization=}"; ORG_ID="${ORG_ID%%:*}"
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

[ -f checklist.json ] || { echo "falta checklist.json: lo arma el wizard con items/*.json (ver governance-cases.md)" >&2; exit 1; }

WF_ID="(no aplica)"
if jq -e --arg k "$KIND" '[.. | objects | select(.kind? == $k)] | length > 0' checklist.json >/dev/null; then
echo "==> 1/5 Workflow"
# PUT por key: crea el workflow la primera vez, despues agrega una revision.
DEF="$(jq --arg nrn "$NP_NRN" --arg key "$WF_KEY" --arg suffix "${NRN_LAST/=/-}" --arg path "/np/checklist/$ORG_ID/$WF_KEY" '
  .id = $key
  | .name = "\(.name) - \($suffix)"
  | .steps.trigger.config.nrn = $nrn
  | .steps.trigger.config.pathPrefix = $path' workflow.json)"
api PUT "/workflows/definitions/$WF_KEY" "$(jq -n --argjson d "$DEF" '{definition: $d}')" >/dev/null
WF="$(api GET "/workflows/definitions/$WF_KEY")"
WF_ID="$(jq -r .workflow.id <<<"$WF")"; REV="$(jq -r .revision.revision <<<"$WF")"
# El engine no hace upsert de aliases: PUT solo re-apunta uno existente, POST lo crea.
api PUT "/workflows/definitions/$WF_ID/aliases/live" "{\"revision\": $REV}" >/dev/null 2>&1 \
  || api POST "/workflows/definitions/$WF_ID/aliases" "{\"name\": \"live\", \"revision\": $REV}" >/dev/null
api POST "/workflows/definitions/$WF_ID/aliases/live/activate" '{}' >/dev/null
CHANNEL="$(api GET "/workflows/definitions/$WF_ID/aliases" \
  | jq -r '.data[] | select(.name == "live" and .active) | .triggerStates.trigger | select(.status == "live") | .pluginState.channelId')"
[ -n "$CHANNEL" ] || { echo "el trigger no quedo live: no van a llegar los dispatch del checklist" >&2; exit 1; }
echo "    $WF_ID rev $REV, alias live, notification channel $CHANNEL"

echo "==> 2/5 Secreto NP_API_KEY del workflow"
api POST /workflows/config "$(jq -n --arg v "$NP_API_KEY" --arg wf "$WF_ID" \
  '{name: "NP_API_KEY", value: $v, secret: true, workflow: $wf}')" >/dev/null
echo "    ok"

else
  echo "==> 1/5 Workflow: no aplica (checklist.json no incluye release_in_lower_env)"
  echo "==> 2/5 Secreto: no aplica"
fi

echo "==> 3/5 Checklist specification"
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

echo "==> 4/5 Approval action deployment:create {$DIMENSION: $GATED_VALUE}"
ACTION_BODY="$(jq -n --arg nrn "$NP_NRN" --arg d "$DIMENSION" --arg v "$GATED_VALUE" '{nrn: $nrn,
  entity: "deployment", action: "deployment:create", dimensions: {($d): $v}, on_policy_success: "approve",
  on_policy_fail: "manual", on_checklist_fail: "pending"}')"
# on_checklist_fail es lo que lee el modo checklist: "pending" = fallo resumible (quien
# deployo arregla y reintenta, o pide review manual). on_policy_* queda por compatibilidad.
ACTION="$(api GET "/approval/action?nrn=$NRN_Q&entity=deployment&limit=200" | jq -c --argjson w "$ACTION_BODY" '
  [.results[] | select(.status == "active" and .nrn == $w.nrn and .action == $w.action and .dimensions == $w.dimensions)]
  | first // empty')"
if [ -z "$ACTION" ]; then
  ACTION_ID="$(api POST /approval/action "$ACTION_BODY" | jq -r .id)"; CREATED=1
  echo "    creada $ACTION_ID"
else
  ACTION_ID="$(jq -r .id <<<"$ACTION")"
  own_action "$ACTION" || { echo "ERROR: ya existe la approval action $ACTION_ID (deployment:create {$DIMENSION: $GATED_VALUE}) y no es de este caso. Borrala o desvinculala de su checklist antes de aplicar." >&2; exit 1; }
  if [ "$(jq -r '.on_checklist_fail // empty' <<<"$ACTION")" != "pending" ]; then
    api PATCH "/approval/action/$ACTION_ID" '{"on_checklist_fail": "pending"}' >/dev/null
    echo "    ya existe $ACTION_ID (on_checklist_fail -> pending)"
  else
    echo "    ya existe $ACTION_ID"
  fi
fi

echo "==> 5/5 Vinculo action -> checklist"
# Si el vinculo falla con una action recien creada, se borra: sin checklist, la corrida
# siguiente la veria como ajena y el caso quedaria trabado.
api POST "/approval/action/$ACTION_ID/checklist_specification" \
  "{\"checklist_specification_id\": \"$SPEC_ID\"}" >/dev/null || {
  [ "${CREATED:-0}" = 1 ] && api DELETE "/approval/action/$ACTION_ID" >/dev/null \
    && echo "    se borro la action $ACTION_ID recien creada (fallo el vinculo)" >&2
  exit 1
}
echo "    $ACTION_ID -> $SPEC_ID"

echo
echo "Listo: workflow $WF_ID, checklist $SPEC_ID, approval action $ACTION_ID"
