# Azure Gotchas

## Credentials for Local Testing

Before running the agent locally with Azure services:

```bash
az login
az account set --subscription <subscription-id>
```

The subscription ID is configured in `values.yaml` and `build_context` exports it as `ARM_SUBSCRIPTION_ID`.

## Cosmos DB

- The throughput mode (provisioned vs serverless) cannot be changed after creating the account
- Containers are created inside databases, not directly in the account
- For serverless, do not specify `throughput` on the container
