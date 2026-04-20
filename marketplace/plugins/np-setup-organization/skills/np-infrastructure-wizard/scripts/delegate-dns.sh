#!/bin/bash
# delegate-dns.sh
# Automatiza la delegación de una zona hija en la zona padre de Route 53
#
# Uso: ./delegate-dns.sh <subdomain> [--child-profile profile1] [--parent-profile profile2]
# Ejemplo: ./delegate-dns.sh grupo-4.playground.nullapps.io --child-profile training-account-1

set -euo pipefail

SUBDOMAIN="${1:?Uso: $0 <subdomain> [--child-profile X] [--parent-profile Y]}"
CHILD_PROFILE=""
PARENT_PROFILE=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --child-profile)  CHILD_PROFILE="--profile $2"; shift 2 ;;
    --parent-profile) PARENT_PROFILE="--profile $2"; shift 2 ;;
    *) echo "Argumento desconocido: $1"; exit 1 ;;
  esac
done

[[ "$SUBDOMAIN" == *. ]] || SUBDOMAIN="${SUBDOMAIN}."

PARENT_ZONE=$(echo "$SUBDOMAIN" | cut -d. -f2-)

echo "Zona hija:  $SUBDOMAIN"
echo "Zona padre: $PARENT_ZONE"

# 1. Obtener el Hosted Zone ID de la zona hija
CHILD_ZONE_ID=$(aws route53 list-hosted-zones $CHILD_PROFILE \
  --query "HostedZones[?Name=='${SUBDOMAIN}' && Config.PrivateZone==\`false\`].Id" \
  --output text | head -1 | sed 's|/hostedzone/||')

if [[ -z "$CHILD_ZONE_ID" ]]; then
  echo "ERROR: No se encontró la zona pública: $SUBDOMAIN"
  exit 1
fi
echo "Child Zone ID: $CHILD_ZONE_ID"

# 2. Obtener los nameservers de la zona hija
NS_RECORDS=$(aws route53 list-resource-record-sets $CHILD_PROFILE \
  --hosted-zone-id "$CHILD_ZONE_ID" \
  --query "ResourceRecordSets[?Type=='NS' && Name=='${SUBDOMAIN}'].ResourceRecords[].Value" \
  --output json)

echo "Nameservers: $NS_RECORDS"

# 3. Encontrar el Hosted Zone ID de la zona padre
PARENT_ZONE_ID=$(aws route53 list-hosted-zones $PARENT_PROFILE \
  --query "HostedZones[?Name=='${PARENT_ZONE}' && Config.PrivateZone==\`false\`].Id" \
  --output text | head -1 | sed 's|/hostedzone/||')

if [[ -z "$PARENT_ZONE_ID" ]]; then
  echo "ERROR: No se encontró la zona padre: $PARENT_ZONE"
  exit 1
fi
echo "Parent Zone ID: $PARENT_ZONE_ID"

# 4. Crear el NS record en la zona padre (UPSERT = crea o actualiza)
CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${SUBDOMAIN}",
      "Type": "NS",
      "TTL": 300,
      "ResourceRecords": $(echo "$NS_RECORDS" | python3 -c "
import json,sys
ns = json.load(sys.stdin)
print(json.dumps([{'Value': v} for v in ns]))
")
    }
  }]
}
EOF
)

echo ""
echo "Creando NS record en zona padre..."
aws route53 change-resource-record-sets $PARENT_PROFILE \
  --hosted-zone-id "$PARENT_ZONE_ID" \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Status' --output text

echo "Delegación completada."
