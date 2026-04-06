# Azure Gotchas

## Credentials para Testing Local

Antes de correr el agente localmente con servicios Azure:

```bash
az login
az account set --subscription <subscription-id>
```

El subscription ID se configura en `values.yaml` y `build_context` lo exporta como `ARM_SUBSCRIPTION_ID`.

## Cosmos DB

- El throughput mode (provisioned vs serverless) no se puede cambiar despues de crear la cuenta
- Los containers se crean dentro de databases, no directamente en la cuenta
- Para serverless, no especificar `throughput` en el container
