# AWS Gotchas

## S3 Lifecycle Rules

AWS provider requiere un bloque `filter {}` explicito en lifecycle rules, incluso si aplica a todos los objetos:

```hcl
rule {
  id     = "my-rule"
  status = "Enabled"
  filter {}
  transition { ... }
}
```

Sin el `filter {}`, las versiones actuales dan warning y futuras versiones daran error.

## Credentials para Testing Local

Antes de correr el agente localmente con servicios AWS:

```bash
aws sso login --profile <name>
aws sts get-caller-identity --profile <name>  # verificar
```

El profile se configura en `values.yaml` (`aws_profile`) y `build_context` lo exporta como `AWS_PROFILE`.

## ARNs en Permissions

Derivar ARNs de nombres en vez de leerlos de `service.attributes`:

```bash
# S3 (deterministico):
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

# RDS:
DB_ARN="arn:aws:rds:${REGION}:${ACCOUNT_ID}:db:${DB_INSTANCE_NAME}"
```

Motivo: `.service.attributes` puede no contener el ARN como campo directo.

## IAM Policy: MalformedPolicyDocument

Si ves `"Resource must be in ARN format"`, un ARN esta vacio. Verificar que `build_permissions_context` deriva los ARNs correctamente.
