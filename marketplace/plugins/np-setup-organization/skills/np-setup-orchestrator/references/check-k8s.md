# check-k8s: Verify Kubernetes

## Prerequisite

The cloud check must have passed (requires kubeconfig configured).

## Flow

```bash
# 1. Verify connection
kubectl cluster-info

# 2. Verify namespaces
kubectl get namespaces

# 3. Verify key components
kubectl get pods -n nullplatform-tools
kubectl get pods -n istio-system
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
```

Report for each component: name, namespace, status, running pods.

## If the cluster is not accessible

Update kubeconfig according to the cloud:

```bash
# AWS
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION

# Azure
az aks get-credentials --name CLUSTER_NAME --resource-group RG_NAME

# GCP
gcloud container clusters get-credentials CLUSTER_NAME --region REGION
```

## If there are pods in error

For pods in `CrashLoopBackOff` or `Error`:

```bash
kubectl logs -n {namespace} -l app={app_label} --tail=100
kubectl describe pod -n {namespace} {pod_name}
```

**Common causes for Agent in CrashLoopBackOff:**
- Invalid or expired API key
- Incorrect NRN
- Firewall blocking connection to `api.nullplatform.com`

## dns_type Validation

Verify that the agent's `DNS_TYPE` is valid for the detected cloud provider:

```bash
DNS_TYPE=$(kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d)
echo "DNS_TYPE: $DNS_TYPE"
```

| Cloud | Expected dns_type |
| ----- | ----------------- |
| AWS   | `route53`         |
| Azure | `azure`           |
| GCP   | `gcp`             |

**If it doesn't match:** warn and recommend editing `infrastructure/{cloud}/terraform.tfvars` with the correct value, then run `tofu apply`.
