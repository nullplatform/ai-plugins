# check-k8s: Verificar Kubernetes

## Prerequisito

El check de cloud debe haber pasado (necesita kubeconfig configurado).

## Flujo

```bash
# 1. Verificar conexión
kubectl cluster-info

# 2. Verificar namespaces
kubectl get namespaces

# 3. Verificar componentes clave
kubectl get pods -n nullplatform-tools
kubectl get pods -n istio-system
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
```

Reportar para cada componente: nombre, namespace, estado, pods running.

## Si el cluster no es accesible

Actualizar kubeconfig según el cloud:

```bash
# AWS
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION

# Azure
az aks get-credentials --name CLUSTER_NAME --resource-group RG_NAME

# GCP
gcloud container clusters get-credentials CLUSTER_NAME --region REGION
```

## Si hay pods en error

Para pods en `CrashLoopBackOff` o `Error`:

```bash
kubectl logs -n {namespace} -l app={app_label} --tail=100
kubectl describe pod -n {namespace} {pod_name}
```

**Causas comunes del Agent en CrashLoopBackOff:**
- API key inválida o expirada
- NRN incorrecto
- Firewall bloqueando conexión a `api.nullplatform.com`

## Validación de dns_type

Verificar que `DNS_TYPE` del agente sea válido para el cloud provider detectado:

```bash
DNS_TYPE=$(kubectl get secret -n nullplatform-tools nullplatform-agent-secret-nullplatform-agent -o jsonpath='{.data.DNS_TYPE}' | base64 -d)
echo "DNS_TYPE: $DNS_TYPE"
```

| Cloud | dns_type esperado |
| ----- | ----------------- |
| AWS   | `route53`         |
| Azure | `azure`           |
| GCP   | `gcp`             |

**Si no coincide:** advertir y recomendar editar `infrastructure/{cloud}/terraform.tfvars` con el valor correcto, luego ejecutar `tofu apply`.
