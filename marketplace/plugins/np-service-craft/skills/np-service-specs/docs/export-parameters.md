# Export de Parametros (Env Vars para Apps)

Cuando un link se activa, NP lee los `attributes` del service y link, y crea env vars (parameters) en la aplicacion linkeada. Solo se exportan campos marcados con `export: true` o `export: {secret: true}`.

## Como Funciona

1. **Service spec** define campos output con `"export": true` (ej: `bucket_arn`, `bucket_region`)
2. **Workflow create/update** ejecuta `write_service_outputs` post-tofu → actualiza `service.attributes` via `np service patch`
3. **Link spec** define campos de credenciales con `"export": true` o `"export": {"type": "environment_variable", "secret": true}`
4. **Workflow link** ejecuta `write_link_outputs` post-tofu → actualiza `link.attributes` via `np link patch`
5. **Al activar link**, NP combina los atributos exportados y crea parameters en la app

## Naming de Env Vars

Patron: `{LINK_SLUG_UPPER}_{ATTRIBUTE_NAME_UPPER}`

| Link slug | Attribute | Env var |
|-----------|-----------|---------|
| `my-connection` | `bucket_name` | `MYCONNECTION_BUCKET_NAME` |
| `test-con-params` | `bucket_arn` | `TESTCONPARAMS_BUCKET_ARN` |
| `linktest` | `secret_access_key` | `LINKTEST_SECRET_ACCESS_KEY` |

> El guion del slug se **elimina** al convertir a upper case (no se reemplaza por `_`).

## Comportamientos Clave

- **Campos vacios no generan parameters**: Si `kms_key_arn` queda vacio, no se crea `MYLINK_KMS_KEY_ARN`
- **Secrets ocultos en API**: `export: {secret: true}` hace que el valor sea `null` en respuestas de API. Esto es normal.
- **Parameters read-only**: Los parameters generados por export son inmutables desde la UI

## Verificacion E2E

```bash
# 1. Verificar service attributes (post create)
/np-api fetch-api "/service/<service_id>"
# .attributes debe contener campos output (bucket_arn, etc)

# 2. Verificar link attributes (post link)
/np-api fetch-api "/link/<link_id>"
# .attributes debe contener credenciales
# Campos con export:{secret:true} aparecen como null (normal)

# 3. Verificar parameters en la app
# UI: App → Parameters → buscar env vars con patron {LINK_SLUG_UPPER}_{FIELD_UPPER}
```
