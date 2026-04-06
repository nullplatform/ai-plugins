# Troubleshooting

Para problemas especificos de cada cloud ver: [aws-troubleshooting.md](aws-troubleshooting.md).

## Certificado en PENDING_VALIDATION

**Causa**: La subzona DNS no esta delegada desde `nullapps.io`.

**Solucion**:
1. Verificar delegacion: `dig NS {slug}.nullapps.io +short`
2. Si no hay NS records, solicitar delegacion a Nullplatform (ver paso 5.4 del wizard)
3. Una vez delegado, el certificado se validara automaticamente

## Cluster no se crea

- Verificar quotas del cloud provider
- Revisar permisos del service account/role

## Agent no conecta

- Verificar autenticacion: invocar `/np-api check-auth`
- Verificar `tags_selectors` coinciden con la configuracion esperada

## DNS no resuelve

- Verificar que external-dns esta corriendo
- Revisar configuracion del DNS provider
- Verificar delegacion de subzona

## Error: namespace already exists

**Causa**: Si un `tofu apply` falla a mitad de ejecucion (ej: timeout de certificado), algunos recursos ya fueron creados pero no quedaron registrados en el state de Terraform.

**Solucion**: Importar el recurso existente al state:

```bash
tofu import module.ingress.kubernetes_namespace_v1.namespace nullplatform
tofu apply
```

**Prevencion**: Seguir el flujo de DNS primero (paso 5) para evitar timeouts en certificados.

## Validacion post-apply (generica)

```bash
kubectl cluster-info
kubectl get ns | grep -E "nullplatform|istio"
kubectl get pods -n nullplatform-tools -l app=nullplatform-agent
kubectl get pods -n istio-system
kubectl get pods -n cert-manager
```
