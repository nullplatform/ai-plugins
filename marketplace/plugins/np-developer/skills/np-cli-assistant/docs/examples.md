# CLI Assistant — Examples

## Example 1: List deployments by NRN

- **User says**: "List deployments for this NRN: `organization=1:account=2:namespace=3:application=4`"
- **Result**:
  ```bash
  np deployment list --nrn organization=1:account=2:namespace=3:application=4
  ```
  - `--nrn` — filter by NRN (specific to `deployment list`, do not assume it exists in other resources)

  Docs: https://docs.nullplatform.com/docs/api/deployment-list

## Example 1b: List applications by namespace

- **User says**: "List applications in namespace 123"
- **Result**:
  ```bash
  np application list --namespace_id 123
  ```
  - `--namespace_id` — filter by namespace ID

  Docs: https://docs.nullplatform.com/docs/api/application-list

## Example 1c: List links for an application

- **User says**: "I want to see links for my application with NRN `organization=1:account=2:namespace=3:application=4`"
- **Result**:
  ```bash
  np link list --nrn organization=1:account=2:namespace=3:application=4 --show_descendants
  ```
  - `--nrn` — filter by NRN
  - `--show_descendants` — include links from scopes under this application. **Without this flag, results will likely be empty** because links are typically attached to scopes, not directly to the application.

  Docs: https://docs.nullplatform.com/docs/api/link-list

> **Why `--show_descendants`?** The NRN hierarchy is `organization > account > namespace > application > scope`. Links are almost always associated with scopes. Querying at the application level without `--show_descendants` only returns links attached *directly* to the application — which is rarely what users expect.

## Example 2: Mutating command with body

- **User says**: "How do I update the asset name of a scope?"
- **Result**:
  ```bash
  np scope patch --id 123 \
    --body '{"asset_name": "new-asset-name"}'
  ```
  - `--id` — the scope ID
  - `--body` — JSON payload with fields to update

  Docs: https://docs.nullplatform.com/docs/api/scope-patch

  Review the parameters before running — this command modifies a real resource.

## Example 3: Command not in reference — verify via CLI

- **User says**: "I want to create an API key"
- **Result**:
  ```bash
  np api-key create \
    --name "descriptive-name" \
    --grants '[{"nrn": "organization=1:account=1:namespace=1:application=4", "role_slug": "machine:ci"}]'
  ```
  Review the parameters before running — this command creates a real resource.

  Docs: https://docs.nullplatform.com/docs/api/api-key-create

> **Key principle**: If a command is not listed in the supported or unsupported list, the user can run `np <resource> --help` to check if it exists.

## Example 4: Unsupported GET via API

- **User says**: "Read notification event `<notification-id>`"
- **Result**: "This operation is not currently supported by the `np` CLI. You can use the REST API instead:"
  ```bash
  curl -L -H "Authorization: Bearer $NP_TOKEN" \
    "https://api.nullplatform.com/notification/<notification-id>"
  ```
  Docs: https://docs.nullplatform.com/docs/api/notification-event-read

## Example 5: Unsupported mutating operation

- **User says**: "How do I list notifications with the CLI?"
- **Result**: "This operation is not currently supported by the `np` CLI. You can use the REST API instead:"
  ```bash
  curl -L -H "Authorization: Bearer $NP_TOKEN" \
    "https://api.nullplatform.com/notification"
  ```
  Docs: https://docs.nullplatform.com/docs/api/notification-list

## Example 6: CI/CD workflow script

- **User says**: "Generate a script to build and deploy a Docker image with np"
- **Result**: Numbered, commented script:
  ```bash
  #!/bin/bash
  set -euo pipefail

  # Requires: NULLPLATFORM_API_KEY env var

  # Step 1: Start a new build
  np build start \
    --application-id "$APPLICATION_ID"

  # Step 2: Push the Docker image asset
  np asset push \
    --type docker-image \
    --source ./Dockerfile

  # Step 3: Mark build as successful
  np build update \
    --status successful
  ```
  Each of these commands is mutating — review parameters before running in production.

## Example 7: Chunked iteration when filter limits are exceeded

- **User says**: "List all applications in account 95118862"
- **Result**: `np application list` only accepts `--namespace_id` (not `--account_id`), and `--namespace_id` accepts up to 10 values. Script that iterates namespaces in chunks:
  ```bash
  #!/bin/bash
  set -euo pipefail
  # Requires: NULLPLATFORM_API_KEY env var

  ACCOUNT_ID="${1:?Usage: $0 <account_id>}"

  # Step 1: Get all namespace IDs
  NS_IDS=$(np namespace list --account_id "$ACCOUNT_ID" --format json --limit 200 \
    --query '.results[].id' | tr '\n' ' ')
  read -ra NS_ARRAY <<< "$NS_IDS"

  # Step 2: Iterate in chunks of 10 (--namespace_id limit)
  for ((i=0; i<${#NS_ARRAY[@]}; i+=10)); do
    CHUNK=$(IFS=,; echo "${NS_ARRAY[*]:i:10}")
    np application list --namespace_id "$CHUNK" --format json --limit 200
  done
  ```
  - `--namespace_id` accepts up to 10 comma-separated values; exceeding this silently truncates results
  - The script batches in groups of 10 to cover all namespaces

  Docs: https://docs.nullplatform.com/docs/api/application-list, https://docs.nullplatform.com/docs/api/namespace-list
