# Post-Apply Validation

After `tofu apply` completes successfully, run these validations to confirm the infrastructure is healthy at the cluster level.

## Pre-checks

Before running any validation, verify that the required tools are available and the cluster is accessible.

### 1. kubectl installed

```bash
kubectl version --client 2>&1 || echo "NOT INSTALLED"
```

- **If not installed** → Guide the user to install it:
  - macOS: `brew install kubectl`
  - Linux: see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- **STOP** — do not continue without kubectl.

### 2. kubeconfig configured

First, extract the cluster connection values from the infrastructure:

1. Read `infrastructure/{cloud}/terraform.tfvars` to find cluster name, region, profile/resource group
2. If not found in tfvars, try the tofu state:
   ```bash
   cd infrastructure/{cloud}
   tofu output -json | grep -i cluster
   ```
3. Show the detected values to the user and **ask for confirmation before proceeding** (e.g., "I detected cluster_name=X, region=Y, profile=Z. Are these correct?")

Then update kubeconfig with the confirmed values:

```bash
# AWS
aws eks update-kubeconfig --name {cluster_name} --region {region} --profile {profile}

# Azure
az aks get-credentials --name {cluster_name} --resource-group {resource_group}

# GCP
gcloud container clusters get-credentials {cluster_name} --region {region}

# OCI
oci ce cluster create-kubeconfig --cluster-id {cluster_ocid} --region {region}
```

### 3. Cluster accessible

```bash
kubectl cluster-info
```

- **If it fails** → Verify cloud session (step 6 of SKILL.md), VPN/firewall, and that the cluster endpoint is reachable.
- **STOP** — do not continue without cluster access.

---

## Schema detection

Before running validations, detect the networking schema to know which components to check:

```bash
# Try reading from agent secret first
DNS_TYPE_RAW=$(kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}')
if [ -n "$DNS_TYPE_RAW" ]; then
  DNS_TYPE=$(echo "$DNS_TYPE_RAW" | base64 -d)
  echo "Detected schema from cluster: $DNS_TYPE"
else
  # Fallback: read from terraform.tfvars
  DNS_TYPE=$(grep 'dns_type' infrastructure/*/terraform.tfvars | grep -o '"[^"]*"' | tr -d '"')
  if [ -n "$DNS_TYPE" ]; then
    echo "Agent secret not found. Detected schema from terraform.tfvars: $DNS_TYPE"
  else
    echo "ERROR: Could not detect DNS_TYPE from cluster or terraform.tfvars" >&2
    echo "WARNING: Skipping schema-conditional validations. Only running generic checks." >&2
    DNS_TYPE=""
  fi
fi
```

- `external_dns` → Istio schema (check all validations)
- `route53` → ACM/Ingress schema (skip Istio-only validations marked below)

If DNS_TYPE is empty after both attempts, the schema cannot be determined. Skip schema-conditional validations and run only the generic ones.

## Validations

Run each validation in order. If one fails, fix it before continuing to the next. **Do not suppress errors with `2>/dev/null` in diagnostic commands** — errors are information.

### 1. Nodes Ready

```bash
kubectl get nodes
```

- All nodes should show `STATUS: Ready`
- If any node is `NotReady`, check cloud console for node group health

### 2. Namespaces exist

```bash
NS_OUTPUT=$(kubectl get ns) || { echo "ERROR: Cannot reach cluster"; }
echo "$NS_OUTPUT" | grep -E "nullplatform-tools|cert-manager|external-dns"
```

**Always expected:** `nullplatform-tools`, `nullplatform`, `cert-manager`, `external-dns`

**Istio schema only:** `istio-system` — skip this check if using ACM/Ingress schema.

If any expected namespace is missing, the corresponding module may have failed during apply. Check `tofu apply` output.

### 3. Core pods running

```bash
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
kubectl get pods -n nullplatform-tools
```

**Istio schema only:**
```bash
kubectl get pods -n istio-system
```

All pods should be `Running` or `Completed`. For pods in `CrashLoopBackOff` or `Error`:

```bash
kubectl logs -n {namespace} {pod_name} --tail=50
kubectl describe pod -n {namespace} {pod_name}
```

### 4. Cert-manager and ClusterIssuer

```bash
kubectl get clusterissuer -o wide
```

- There should be at least one ClusterIssuer (typically `letsencrypt-prod` or `letsencrypt`)
- The `READY` column must be `True`
- If `READY` is `False`:
  ```bash
  kubectl describe clusterissuer {name}
  ```
  Common cause: DNS not resolving, so ACME challenge fails.

### 5. Certificates

```bash
kubectl get certificates -A
```

- Certificates should show `READY: True`
- If `READY` is `False`:
  ```bash
  kubectl describe certificate -n {namespace} {name}
  kubectl get certificaterequest -A
  kubectl get order -A
  kubectl get challenge -A
  ```
- **Verify the domain matches the DNS zone**: the certificate's domain (in `spec.dnsNames`) must match the DNS zone created in step 5 of the wizard. A mismatch means cert-manager is requesting a certificate for a domain that DNS can't validate.
- If certificate is stuck in `PENDING_VALIDATION`: see [troubleshooting.md](troubleshooting.md#certificate-in-pending_validation)

### 6. DNS resolution

```bash
dig NS {domain}.nullapps.io +short
```

- Must return NS records. If empty, delegation is not complete (see step 5 of SKILL.md).

Then verify external-dns is syncing records:

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=20
```

Look for log lines indicating record creation/updates. If there are permission errors, check IAM roles.

### 7. Istio Gateways (Istio schema only)

**Skip this validation if using ACM/Ingress schema.**

```bash
kubectl get gateway -A
kubectl get pods -n istio-system
```

- Gateway resources should exist
- Istio pods should be `Running`

Verify the NLB/LB is active (AWS example):

```bash
# Get target group ARNs — run each separately to catch errors
ARNS=$(aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `k8s-np`)].TargetGroupArn' --output text)
if [ -z "$ARNS" ]; then
  echo "ERROR: No target groups found matching k8s-np. Check NLB naming or AWS credentials."
else
  for ARN in $ARNS; do
    aws elbv2 describe-target-health --target-group-arn "$ARN"
  done
fi
```

If targets are `unhealthy`, check that the EKS cluster security groups allow traffic on the gateway port (443) and health check port (15021).

### 8. Agent

```bash
kubectl get pods -n nullplatform-tools -l app=nullplatform-agent
```

- Pod should be `Running`
- If `CrashLoopBackOff`:
  ```bash
  kubectl logs -n nullplatform-tools -l app=nullplatform-agent --tail=50
  ```
  Common causes: invalid API key, incorrect NRN, firewall blocking `api.nullplatform.com`

Verify dns_type matches the detected schema:

```bash
DNS_TYPE_RAW=$(kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}')
if [ -z "$DNS_TYPE_RAW" ]; then
  echo "ERROR: Could not read DNS_TYPE from agent secret"
else
  echo "$DNS_TYPE_RAW" | base64 -d
fi
```

Must match the networking schema (see [resources-by-cloud.md](resources-by-cloud.md#ingress-by-cloud)).

---

## Summary

After all validations pass, the infrastructure is ready. Continue with `/np-nullplatform-wizard` to configure Nullplatform resources.

If any validation fails, see [troubleshooting.md](troubleshooting.md) and [aws-troubleshooting.md](aws-troubleshooting.md) for specific solutions.
