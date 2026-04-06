#!/bin/bash
# Script para validar np_api_key desde common.tfvars
# Uso: ./check-tf-api-key.sh [ruta_al_archivo]
# Si no se especifica archivo, usa common.tfvars en el directorio actual

set -e

SECRETS_FILE="${1:-common.tfvars}"

if [ ! -f "$SECRETS_FILE" ]; then
    echo "ERROR: Archivo no encontrado: $SECRETS_FILE"
    exit 1
fi

# Extraer np_api_key del archivo tfvars
TF_API_KEY=$(grep 'np_api_key' "$SECRETS_FILE" | sed 's/.*= *"\(.*\)"/\1/' | tr -d '[:space:]')

if [ -z "$TF_API_KEY" ]; then
    echo "ERROR: No se encontro np_api_key en $SECRETS_FILE"
    exit 1
fi

# Intentar obtener token
RESPONSE=$(curl -s -X POST "https://api.nullplatform.com/token" \
    -H "Content-Type: application/json" \
    -d "{\"api_key\": \"$TF_API_KEY\"}")

# Verificar si la respuesta contiene access_token
if echo "$RESPONSE" | grep -q "access_token"; then
    echo "OK"
    # Extraer organization_id si está disponible
    ORG_ID=$(echo "$RESPONSE" | grep -o '"organization_id":[0-9]*' | cut -d: -f2)
    if [ -n "$ORG_ID" ]; then
        echo "organization_id=$ORG_ID"
    fi
    exit 0
else
    echo "ERROR: API Key inválida"
    echo "$RESPONSE"
    exit 1
fi
