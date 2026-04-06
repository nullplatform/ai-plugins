---
name: np-setup-troubleshooting
description: This skill should be used when the user asks "why did my scope fail", "why is my application broken", "diagnose setup failure", "troubleshoot permissions", "fix telemetry", or needs to diagnose why nullplatform entities (scopes, applications, telemetry, permissions) failed during setup.
---

# Nullplatform Setup Troubleshooting

Skill to diagnose why entities failed in Nullplatform.

## Available Commands

| Command | Purpose |
|---------|---------|
| `/np-setup-troubleshooting scope <id>` | Diagnose why a scope failed |
| `/np-setup-troubleshooting app <id>` | Diagnose why an application failed |

---

## Command: scope <id>

Diagnoses why a scope is in `failed` state.

### Flow

1. **Get the scope**:
   - Invoke `/np-api fetch-api "/scope/{id}"`
   - Extract `instance_id` from the response

2. **List service actions**:
   - Invoke `/np-api fetch-api "/service/{instance_id}/action"`
   - Search for actions with `status: failed`

3. **For each failed action**:
   - Invoke `/np-api fetch-api "/service/{instance_id}/action/{action_id}?include_messages=true"`
   - Extract error messages

4. **Generate report**:
   - Summarize the errors found
   - Interpret technical messages
   - Suggest possible solutions

### Usage example

```
User: Scope 1019650520 is in failed state, why?

Claude: I'll use /np-setup-troubleshooting scope 1019650520 to diagnose.
```

### Common errors

| Error | Probable cause | Solution |
|-------|----------------|----------|
| "You're not authorized to perform this operation" | API key without permissions | See **Permission Diagnosis** below |
| "Timeout waiting for ingress reconciliation" | K8s networking issues | Review ingress and certificate configuration |
| "ECR repository not found" | Missing ECR or permissions | Run `/np-infrastructure-wizard` |
| "Unsupported DNS type 'aws'" | Incorrect `dns_type` in terraform.tfvars | See **dns_type Diagnosis** below |

### Permission Diagnosis (for "not authorized")

When the error contains "not authorized", run extended API key diagnosis:

#### Additional Flow

1. **Identify the scope's notification channel**:
   - From the failed scope, get the `nrn`
   - Invoke `/np-api fetch-api "https://notifications.nullplatform.com/notification/channel?nrn={nrn}&showDescendants=true"`
   - Search for `agent` type channels

2. **Get the channel's API key**:
   - Invoke `/np-api fetch-api "https://notifications.nullplatform.com/notification/channel/{channel_id}"`
   - The API key name is in `configuration.agent.api_key` (partially visible)
   - Search for the complete API key: `/np-api fetch-api "/api-key?name={api_key_name}"`

3. **Compare API key roles**:
   - Invoke `/np-api fetch-api "/api-key/{api_key_id}"`
   - Extract `grants[].role_slug`
   - Verify against required roles

4. **Generate permissions report**:

   | Role | Required | Present |
   |------|----------|---------|
   | `controlplane:agent` | Yes | ✓/✗ |
   | `ops` | Yes | ✓/✗ |

#### Required Roles for Notification Channels

| Role | Purpose |
|------|---------|
| `controlplane:agent` | Communication with the control plane |
| `ops` | Execute commands on the agent |

#### Common Root Cause

If the `ops` role is missing, the problem is in the Terraform module `scope_definition_agent_association`.

**Problematic file:** `nullplatform/scope_definition_agent_association/auth.tf`

```hcl
# INCORRECT - only has controlplane:agent
resource "nullplatform_api_key" "nullplatform_agent_api_key" {
  grants {
    role_slug = "controlplane:agent"
  }
}

# CORRECT - also needs ops
resource "nullplatform_api_key" "nullplatform_agent_api_key" {
  grants {
    role_slug = "controlplane:agent"
  }
  grants {
    role_slug = "ops"
  }
}
```

**Solution:** Update the module and re-apply bindings with `tofu apply`

---

### Error 404 Diagnosis (Istio vs ALB mismatch)

When the scope deploys correctly but the service returns 404 from `istio-envoy`.

#### Symptom

- DNS resolves correctly
- Valid TLS certificate
- Pod running
- But curl returns: `upstream connect error` or 404 from istio-envoy

#### Diagnosis Flow

1. **Verify LB architecture**:

```bash
# If it returns something → Istio active
kubectl get svc -n istio-system istio-ingressgateway
```

2. **Verify resources created by agent**:

```bash
kubectl get httproute -A -l scope_id={scope_id}
kubectl get ingress -A -l scope_id={scope_id}
```

3. **Verify agent configuration**:

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent \
  -o jsonpath='{.data.INITIAL_INGRESS_PATH}' | base64 -d
```

- If it contains "istio" → Configured for Istio (HTTPRoute)
- If empty → Configured for ALB (Ingress)

4. **Generate mismatch table**:

| Component | Detected | Expected |
|-----------|----------|----------|
| Load Balancer | NLB (Istio) / ALB | - |
| Resources created | HTTPRoute / Ingress | - |
| Agent config | Istio / ALB | Must match LB |

#### Root Cause

| DNS points to | Agent creates | Result |
|---------------|---------------|--------|
| NLB (Istio) | HTTPRoute | OK |
| NLB (Istio) | Ingress | **404** |
| ALB | Ingress | OK |
| ALB | HTTPRoute | No routing |

#### Solution

If there's a mismatch, update `infrastructure/aws/main.tf`:

**For Istio** (if you have NLB/Istio Gateway):

```hcl
module "agent" {
  # Add these lines:
  initial_ingress_path    = "$SERVICE_PATH/deployment/templates/istio/initial-httproute.yaml.tpl"
  blue_green_ingress_path = "$SERVICE_PATH/deployment/templates/istio/blue-green-httproute.yaml.tpl"
}
```

And in terraform.tfvars:

```hcl
resources = ["service", "istio-gateway"]
```

**For ALB** (if you have ALB):

```hcl
module "agent" {
  # Do NOT include initial_ingress_path or blue_green_ingress_path
}
```

And in terraform.tfvars:

```hcl
resources = ["ingress", "service"]
```

Then:

1. `tofu apply`
2. `kubectl rollout restart deployment -n nullplatform-tools nullplatform-agent-nullplatform-agent`
3. Delete old resources: `kubectl delete ingress -n nullplatform -l scope_id={id}` or `kubectl delete httproute...`
4. Redeploy scope from Nullplatform UI

See full documentation: `infrastructure/aws/ISTIO_VS_ALB.md`

---

### dns_type Diagnosis (for "Unsupported DNS type")

When the error contains "Unsupported DNS type", the `dns_type` value in terraform.tfvars is not valid.

#### Valid values by cloud

| Cloud | Correct dns_type | Incorrect |
| ----- | ---------------- | --------- |
| AWS   | `route53`        | `aws`     |
| Azure | `azure`          | -         |
| GCP   | `gcp`            | -         |

#### Diagnosis flow

1. **Verify value in K8s:**

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d
```

2. **Verify value in terraform.tfvars:**

```bash
grep dns_type infrastructure/aws/terraform.tfvars
```

3. **If they don't match the table** → Fix tfvars:

```hcl
# Incorrect
dns_type = "aws"

# Correct
dns_type = "route53"
```

4. **Apply changes:**

```bash
cd infrastructure/aws && tofu apply
```

5. **Verify the agent picked up the change:**

```bash
kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d
# Should show: route53
```

---

## Command: app <id>

Diagnoses why an application is in `failed` state.

### Flow

1. **Get the application**:
   - Invoke `/np-api fetch-api "/application/{id}"`
   - Review status and messages

2. **Review failed builds**:
   - Invoke `/np-api fetch-api "/build?application_id={id}&status=failed&limit=5"`
   - For each failed build, review `error_message`

3. **Review failed scopes**:
   - Invoke `/np-api fetch-api "/scope?application_id={id}"`
   - For each scope in `failed`, run scope diagnosis

4. **Generate report**:
   - Consolidate build and scope errors
   - Identify the root cause

---

## Telemetry Diagnosis (Logs and Metrics via API)

When the Nullplatform telemetry API (`/telemetry/application/{id}/log` or `/telemetry/application/{id}/metric/{name}`) is not working.

### Symptoms

| Error | Resource | Cause |
|-------|----------|-------|
| `"Keys not present for NRN"` | Logs | No `global.logProvider` configured |
| `"Oops.. there was an internal error"` | Metrics | telemetry-api cannot connect to internal Prometheus |

### Diagnosis Flow

#### 1. Verify NRN configuration

```bash
np-api fetch-api "/nrn/organization={org_id}:account={account_id}?ids=global.logProvider,global.metricsProvider"
```

**Expected response:**
```json
{
  "namespaces": {
    "global": {
      "logProvider": "external",
      "metricsProvider": "externalmetrics"
    }
  }
}
```

**If `logProvider` doesn't exist:** The default is `cloudwatchlogs`, which fails if CloudWatch is not configured.

**If `metricsProvider` is `prometheusmetrics`:** It will fail because telemetry-api cannot connect to the cluster's internal Prometheus.

#### 2. For Service Specification scopes (containers-default, etc.)

Scopes created by service specifications have a known issue:

- The `k8slogs` provider exists in telemetry-api but **does NOT support** service specification scopes
- The code expects `scope.provider = "AWS:WEB_POOL:EKS"` but receives the service specification UUID
- See code: `telemetry-api/services/providers/commons/k8s_commons.js:20-31`

### Solution for Logs: Use "external" Provider

The `external` provider delegates log retrieval to the agent via notification channel.

#### Immediate Fix (via API)

```bash
# 1. Get token from secrets.tfvars
NP_KEY=$(grep 'np_api_key' secrets.tfvars | sed 's/.*= *"\(.*\)"/\1/')
TOKEN=$(curl -s -X POST "https://api.nullplatform.com/token" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$NP_KEY\"}" | jq -r '.access_token')

# 2. Configure logProvider as external
curl -X PATCH "https://api.nullplatform.com/nrn/organization={org_id}:account={account_id}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"global.logProvider": "external"}'
```

#### Verify it works

```bash
# Should return scope logs
np-api fetch-api "/telemetry/application/{app_id}/log?type=application&scope={scope_id}&limit=5"
```

### Solution for Metrics: Use "externalmetrics" Provider

The `externalmetrics` provider delegates metric retrieval to the agent via notification channel.

**Root cause of the problem:** The `prometheusmetrics` provider tries to connect directly to Prometheus using the configured URL (`prometheus.url`), but this URL is internal to the cluster and not accessible from telemetry-api.

#### Immediate Fix (via API)

```bash
# 1. Get token from secrets.tfvars
NP_KEY=$(grep 'np_api_key' secrets.tfvars | sed 's/.*= *"\(.*\)"/\1/')
TOKEN=$(curl -s -X POST "https://api.nullplatform.com/token" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$NP_KEY\"}" | jq -r '.access_token')

# 2. Configure metricsProvider as externalmetrics
curl -X PATCH "https://api.nullplatform.com/nrn/organization={org_id}:account={account_id}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"global.metricsProvider": "externalmetrics"}'
```

#### Verify it works

```bash
# Should return scope metrics
np-api fetch-api "/telemetry/application/{app_id}/metric/http.rpm?scope_id={scope_id}&minutes=30&period=300"
```

**Note:** The Prometheus provider is still needed to configure `prometheus.url` which the agent uses internally.

### Current Status and Pending Items

| Resource | Provider | Status | Notes |
|----------|----------|--------|-------|
| Logs | `external` | ✅ Works | Delegates to agent via notification channel |
| Metrics | `externalmetrics` | ✅ Works | Delegates to agent via notification channel |

### PENDING: Permanent Solution (Nullplatform Team)

**Problem:** There are no provider specifications to configure `global.logProvider` and `global.metricsProvider` via OpenTofu.

**Proposal:** Create provider specifications for logs and metrics:

```json
{
  "name": "Agent Logs (K8s)",
  "slug": "agent-logs-configuration",
  "icon": "mdi:kubernetes",
  "description": "Delegates log retrieval to the Nullplatform agent for K8s-based services",
  "visible_to": ["organization=*"],
  "schema": {
    "type": "object",
    "properties": {
      "log_provider": {
        "type": "string",
        "const": "external",
        "default": "external",
        "visible": false
      }
    }
  },
  "mapping": {
    "log_provider": "global.logProvider"
  },
  "categories": [{"slug": "logs"}]
}
```

**Benefits:**
1. Configuration via OpenTofu (no manual PATCH to NRN required)
2. Consistent with the Prometheus provider pattern
3. No changes required in telemetry-api

**References:**
- Prometheus provider spec: `/provider_specification/e88cbbd3-7df9-4985-9210-a075420b619e`
- External provider code: `telemetry-api/services/providers/logs/external_log_service.js`
- Agent entrypoint: `scopes/entrypoint:66-67` (handles `log:read`)

### Reference Files

| File | Purpose |
|------|---------|
| `telemetry-api/services/nrn_service.js:220-253` | `getLogProvider()` - determines which provider to use |
| `telemetry-api/services/nrn_service.js:9` | `DEFAULT_LOG_PROVIDER = "cloudwatchlogs"` |
| `telemetry-api/services/providers/commons/k8s_commons.js:20-31` | Switch that fails with service specs |
| `scopes/entrypoint:66-67` | Agent handles `log:read` action |

---

## Important Notes

- **ALWAYS use `include_messages=true`** when querying actions - without this parameter, messages come empty
- The scope's `instance_id` field is the UUID of the service that contains the actions
- Scope creation errors are in `/service/{instance_id}/action`, NOT in the scope directly
- This skill uses `/np-api` declaratively - it doesn't know implementation details

---

## Visual Diagnosis Flow

```
Scope failed
    │
    ▼
GET /scope/{id} → extract instance_id
    │
    ▼
GET /service/{instance_id}/action
    │
    ▼
GET action with ?include_messages=true
    │
    ▼
Analyze error in logs
    │
    ├─► "not authorized" → Permission Diagnosis
    ├─► "Unsupported DNS type" → dns_type Diagnosis
    ├─► "ECR repository not found" → /np-infrastructure-wizard
    └─► Other error → Review K8s and Terraform
```
