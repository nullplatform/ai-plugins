#!/bin/bash
# delegate-dns.sh
# Delega una zona hija en la zona padre de Route 53.
#
# La zona hija puede vivir en AWS (Route 53), GCP (Cloud DNS) o Azure (Azure DNS).
# La zona padre (nullapps.io y cualquiera de sus subzonas) vive SIEMPRE en Route 53,
# asi que el NS record se crea siempre con `aws route53`, en la cuenta que gobierna
# el dominio padre.
#
# Uso:
#   ./delegate-dns.sh <subdomain> [opciones]
#
# Opciones:
#   --cloud aws|gcp|azure   Cloud de la zona hija. Si se omite, se infiere de
#                           infrastructure/{aws,gcp,azure}/ en el directorio actual.
#   --parent-profile NAME   Profile AWS de la cuenta con la zona padre.
#   --parent-zone NAME      Zona padre explicita. Por defecto se deriva del subdominio
#                           quitandole la primera etiqueta.
#   --child-profile NAME    Profile AWS de la cuenta con la zona hija (solo --cloud aws).
#   --gcp-project ID        Proyecto GCP de la zona hija (solo --cloud gcp).
#   --subscription ID       Suscripcion Azure de la zona hija (solo --cloud azure).
#   --dry-run               Imprime el change-batch y NO escribe nada.
#
# Ejemplos:
#   ./delegate-dns.sh grupo-4.<zona-padre> --child-profile training-1 --parent-profile parent-aws
#   ./delegate-dns.sh acme.<zona-padre> --cloud gcp --parent-profile parent-aws --dry-run

set -euo pipefail

TTL=300

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  # Imprime el bloque de comentarios de la cabecera, saltando el shebang y el
  # nombre del archivo, y cortando en la primera linea que no es comentario.
  awk 'NR>2 { if (/^#/) { sub(/^# ?/, ""); print; next } exit }' "$0"
  exit "${1:-1}"
}

# ---------------------------------------------------------------- argumentos

[[ $# -gt 0 ]] || usage 1
case "$1" in -h|--help) usage 0 ;; esac

SUBDOMAIN="$1"; shift
CLOUD=""
PARENT_PROFILE=""
PARENT_ZONE=""
CHILD_PROFILE=""
GCP_PROJECT=""
SUBSCRIPTION=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)           CLOUD="$2"; shift 2 ;;
    --parent-profile)  PARENT_PROFILE="$2"; shift 2 ;;
    --parent-zone)     PARENT_ZONE="$2"; shift 2 ;;
    --child-profile)   CHILD_PROFILE="$2"; shift 2 ;;
    --gcp-project)     GCP_PROJECT="$2"; shift 2 ;;
    --subscription)    SUBSCRIPTION="$2"; shift 2 ;;
    --dry-run)         DRY_RUN="true"; shift ;;
    -h|--help)         usage 0 ;;
    *) die "Argumento desconocido: $1 (--help para el uso)" ;;
  esac
done

# Nombres con punto final (FQDN) para Route 53 y Cloud DNS; sin punto para Azure.
[[ "$SUBDOMAIN" == *. ]] || SUBDOMAIN="${SUBDOMAIN}."
SUBDOMAIN_NODOT="${SUBDOMAIN%.}"

if [[ -z "$PARENT_ZONE" ]]; then
  PARENT_ZONE=$(echo "$SUBDOMAIN" | cut -d. -f2-)
  [[ "$PARENT_ZONE" == *.* ]] || die "No se pudo derivar la zona padre de '$SUBDOMAIN'. Pasala con --parent-zone."
else
  [[ "$PARENT_ZONE" == *. ]] || PARENT_ZONE="${PARENT_ZONE}."
fi

# Wrappers de CLI: el flag se omite por completo cuando el valor esta vacio, para
# no pisar credenciales default (env vars, SSO sin profile, IAM role del host).
# Van como funciones y no como arrays de flags porque bash 3.2 -- el /bin/bash de
# macOS -- trata "${ARR[@]}" de un array vacio como unbound variable bajo `set -u`.
aws_parent() { if [[ -n "$PARENT_PROFILE" ]]; then aws --profile "$PARENT_PROFILE" "$@"; else aws "$@"; fi; }
aws_child()  { if [[ -n "$CHILD_PROFILE"  ]]; then aws --profile "$CHILD_PROFILE"  "$@"; else aws "$@"; fi; }
gcloud_c()   { if [[ -n "$GCP_PROJECT"    ]]; then gcloud "$@" --project "$GCP_PROJECT"; else gcloud "$@"; fi; }
az_c()       { if [[ -n "$SUBSCRIPTION"   ]]; then az "$@" --subscription "$SUBSCRIPTION"; else az "$@"; fi; }

# ------------------------------------------------------- deteccion del cloud

detect_cloud() {
  local found=() c
  for c in aws gcp azure; do
    [[ -d "infrastructure/$c" ]] && found+=("$c")
  done
  case "${#found[@]}" in
    1) echo "${found[0]}" ;;
    0) die "No encontre infrastructure/{aws,gcp,azure}/ en $(pwd). Corre el script desde la raiz del proyecto o pasa --cloud." ;;
    *) die "Hay mas de un infrastructure/{${found[*]}}/ en $(pwd). Elegi con --cloud." ;;
  esac
}

if [[ -z "$CLOUD" ]]; then
  CLOUD=$(detect_cloud)
  echo "Cloud detectado: $CLOUD (por infrastructure/$CLOUD/)"
else
  case "$CLOUD" in
    aws|gcp|azure) echo "Cloud: $CLOUD (explicito)" ;;
    aro) die "Para Azure ARO usa --cloud azure (la zona vive en Azure DNS igual)." ;;
    *) die "--cloud invalido: '$CLOUD'. Valores: aws, gcp, azure." ;;
  esac
fi

echo "Zona hija:  $SUBDOMAIN"
echo "Zona padre: $PARENT_ZONE  (Route 53)"

# -------------------------------------------------------------- preflight

need_cli() { command -v "$1" >/dev/null 2>&1 || die "Falta el CLI '$1', necesario para $2."; }

# El padre es SIEMPRE Route 53.
need_cli aws "escribir el NS record en la zona padre (Route 53)"
aws_parent sts get-caller-identity >/dev/null 2>&1 || die \
  "Sin credenciales AWS validas para la zona padre. Logueate y reintenta:
    aws sso login --profile ${PARENT_PROFILE:-<tu-profile>}
  o pasa otro profile con --parent-profile."

case "$CLOUD" in
  aws)
    aws_child sts get-caller-identity >/dev/null 2>&1 || die \
      "Sin credenciales AWS validas para la zona hija. Logueate y reintenta:
    aws sso login --profile ${CHILD_PROFILE:-<tu-profile>}"
    ;;
  gcp)
    need_cli gcloud "leer los nameservers de la zona hija en Cloud DNS"
    # print-access-token y no `gcloud auth list`: list muestra la cuenta configurada
    # aunque el token este vencido y haga falta reauth, y entonces el error real
    # aparece recien en el lookup de la zona, disfrazado de "zona no encontrada".
    gcloud auth print-access-token >/dev/null 2>&1 || die \
      "Sin sesion valida de gcloud (falta login o el token necesita reauth). Corre:
    gcloud auth login"
    ;;
  azure)
    need_cli az "leer los nameservers de la zona hija en Azure DNS"
    az_c account show >/dev/null 2>&1 || die \
      "Sin sesion activa de Azure CLI. Logueate y reintenta:
    az login"
    ;;
esac

# ------------------------------------------- nameservers de la zona hija

# Cada rama imprime un nameserver por linea. La zona hija debe existir ya:
# la crea el `tofu apply -target=module.vpc -target=module.dns` del step 5.3.
ns_from_aws() {
  local zone_id
  zone_id=$(aws_child route53 list-hosted-zones \
    --query "HostedZones[?Name=='${SUBDOMAIN}' && Config.PrivateZone==\`false\`].Id" \
    --output text | head -1 | sed 's|/hostedzone/||')
  [[ -n "$zone_id" ]] || die "No encontre la zona publica '$SUBDOMAIN' en Route 53 con esas credenciales.
  El apply del step 5.3 no dejo la zona donde apunta --child-profile."
  echo "Child Zone ID: $zone_id" >&2
  aws_child route53 list-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Type=='NS' && Name=='${SUBDOMAIN}'].ResourceRecords[].Value" \
    --output text | tr '\t' '\n'
}

ns_from_gcp() {
  local zone
  zone=$(gcloud_c dns managed-zones list \
    --filter="dnsName=${SUBDOMAIN} AND visibility=public" \
    --format="value(name)" 2>/dev/null | head -1)
  [[ -n "$zone" ]] || die "No encontre una managed zone publica para '$SUBDOMAIN' en Cloud DNS${GCP_PROJECT:+ (proyecto $GCP_PROJECT)}.
  Verifica el proyecto activo con 'gcloud config get-value project' o pasa --gcp-project."
  echo "Child managed zone: $zone" >&2
  # --format=json + python en vez de value[delimiter=...]: el escapeo del delimiter
  # de gcloud pasa por el shell y no es confiable; con JSON la salida es exacta.
  gcloud_c dns managed-zones describe "$zone" --format=json \
    | python3 -c 'import json,sys
for v in json.load(sys.stdin).get("nameServers", []): print(v)'
}

ns_from_azure() {
  local rg
  rg=$(az_c network dns zone list \
    --query "[?name=='${SUBDOMAIN_NODOT}'].resourceGroup | [0]" -o tsv 2>/dev/null)
  [[ -n "$rg" && "$rg" != "None" ]] || die "No encontre la zona '$SUBDOMAIN_NODOT' en Azure DNS en esta suscripcion.
  Verifica la suscripcion activa con 'az account show' o pasa --subscription."
  echo "Child zone resource group: $rg" >&2
  az_c network dns zone show -g "$rg" -n "$SUBDOMAIN_NODOT" \
    --query "nameServers[]" -o tsv
}

case "$CLOUD" in
  aws)   NS_LIST=$(ns_from_aws) ;;
  gcp)   NS_LIST=$(ns_from_gcp) ;;
  azure) NS_LIST=$(ns_from_azure) ;;
esac

NS_LIST=$(echo "$NS_LIST" | sed 's/[[:space:]]*$//' | grep -v '^$' || true)
NS_COUNT=$(echo "$NS_LIST" | grep -c '^' || true)
[[ "$NS_COUNT" -ge 2 ]] || die "Esperaba al menos 2 nameservers para '$SUBDOMAIN' y encontre $NS_COUNT.
  La zona existe pero no expone NS records; revisa el apply del step 5.3."

echo "Nameservers ($NS_COUNT):"
echo "$NS_LIST" | sed 's/^/  /'

# ------------------------------------------- zona padre en Route 53

PARENT_ZONE_ID=$(aws_parent route53 list-hosted-zones \
  --query "HostedZones[?Name=='${PARENT_ZONE}' && Config.PrivateZone==\`false\`].Id" \
  --output text | head -1 | sed 's|/hostedzone/||')

[[ -n "$PARENT_ZONE_ID" ]] || die "No encontre la zona padre publica '$PARENT_ZONE' en Route 53 con esas credenciales.
  Si la cuenta padre no es tuya, la delegacion la tiene que hacer Nullplatform (step 5.5.c del SKILL.md)."
echo "Parent Zone ID: $PARENT_ZONE_ID"

# UPSERT: crea el record o lo actualiza si ya existe (re-ejecutable).
CHANGE_BATCH=$(NS_LIST="$NS_LIST" SUBDOMAIN="$SUBDOMAIN" TTL="$TTL" python3 <<'PYEOF'
import json, os
ns = [l.strip() for l in os.environ["NS_LIST"].splitlines() if l.strip()]
print(json.dumps({"Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
        "Name": os.environ["SUBDOMAIN"],
        "Type": "NS",
        "TTL": int(os.environ["TTL"]),
        "ResourceRecords": [{"Value": v} for v in ns],
    },
}]}, indent=2))
PYEOF
)

if [[ "$DRY_RUN" == "true" ]]; then
  echo
  echo "--- DRY RUN: no se escribe nada ---"
  echo "aws route53 change-resource-record-sets ${PARENT_PROFILE:+--profile $PARENT_PROFILE} \\"
  echo "  --hosted-zone-id $PARENT_ZONE_ID --change-batch <lo de abajo>"
  echo "$CHANGE_BATCH"
  exit 0
fi

echo
echo "Creando NS record en la zona padre..."
aws_parent route53 change-resource-record-sets \
  --hosted-zone-id "$PARENT_ZONE_ID" \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Status' --output text

echo "Delegacion completada. Verifica con: dig NS ${SUBDOMAIN_NODOT} +short"
