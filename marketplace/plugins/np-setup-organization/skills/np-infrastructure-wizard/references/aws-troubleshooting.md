# Troubleshooting AWS

Para problemas genericos (DNS, agent, namespace) ver [troubleshooting.md](troubleshooting.md).

## ALB Controller webhook no ready

**Causa**: El ALB Controller necesita ~2 minutos para registrar su webhook de validacion. Si otros Helm charts se aplican antes, fallan con errores de webhook.

**Solucion**: Verificar que los modulos Helm posteriores (`cert_manager`, `external_dns`, `istio`, `ingress`) tienen `depends_on = [module.alb_controller]`. Tambien verificar que `alb_controller_iam` esta incluido y que `alb_controller` depende de el (crea el service account necesario).

```bash
kubectl get validatingwebhookconfigurations | grep alb
```

## IRSA role no funciona

**Causa**: El OIDC provider del cluster EKS no coincide con la trust policy del IAM role, o el service account no tiene la annotation correcta.

**Solucion**:
1. Verificar OIDC provider: `aws eks describe-cluster --name {cluster} --query "cluster.identity.oidc.issuer"`
2. Verificar trust policy del role: `aws iam get-role --role-name {role} --query "Role.AssumeRolePolicyDocument"`
3. Verificar annotation del service account: `kubectl get sa {sa-name} -n {namespace} -o yaml | grep eks.amazonaws.com/role-arn`

## EKS endpoint no accesible

**Causa**: El cluster EKS tiene configuracion de acceso publico/privado que no permite la conexion desde donde se ejecuta tofu.

**Solucion**:
1. Verificar config de acceso: `aws eks describe-cluster --name {cluster} --query "cluster.resourcesVpcConfig.{publicAccess:endpointPublicAccess,privateAccess:endpointPrivateAccess}"`
2. Si es solo privado, tofu debe ejecutarse desde dentro de la VPC o via VPN
3. Si es publico, verificar que el CIDR de origen esta en la allowlist

## S3 backend permission denied

**Causa**: El profile de AWS CLI no tiene permisos sobre el bucket S3.

**Solucion**:
1. Verificar profile: `aws sts get-caller-identity --profile {profile}`
2. Verificar acceso al bucket: `aws s3 ls s3://{bucket} --profile {profile}`
3. Verificar que `backend.tf` tiene el `profile` correcto (es obligatorio en AWS)

## NLB targets unhealthy (FailedHealthChecks)

**Causa**: El SG del cluster EKS no tiene reglas de ingreso permitiendo trafico desde el SG del NLB (gateway). El NLB con target type `ip` envia trafico directo a los pods. Sin reglas explicitas en el cluster SG, los health checks (puerto 15021) y el trafico HTTPS (puerto 443) son bloqueados.

**Sintomas**:
- DNS resuelve correctamente (dig devuelve IPs del NLB)
- curl hace timeout (no conecta al puerto 443)
- Target groups del NLB muestran `Target.FailedHealthChecks`

**Solucion**:
1. Verificar que el modulo `security` recibe `cluster_security_group_id` con el **primary SG**:
   ```hcl
   cluster_security_group_id = module.eks.eks_cluster_primary_security_group_id
   ```
2. NO usar `eks_cluster_security_group_id` (es el additional SG, no esta adjunto a los nodos)
3. Verificar targets: `aws elbv2 describe-target-health --target-group-arn {arn}`
4. Verificar reglas del cluster SG: `aws ec2 describe-security-group-rules --filters "Name=group-id,Values={cluster_sg_id}"`

**Diferencia entre SGs de EKS**:
- `eks_cluster_primary_security_group_id`: Creado por EKS, adjunto automaticamente a todos los nodos. Nombre: `eks-cluster-sg-{cluster}-*`
- `eks_cluster_security_group_id`: Creado por el modulo Terraform de EKS (additional). Nombre: `{cluster}-cluster-*`

## Agent crea Ingress ALB en vez de HTTPRoute

**Causa**: El agent no tiene configuradas las variables de templates Istio. Por defecto usa `/root/.np/nullplatform/scopes/k8s/deployment/templates/initial-ingress.yaml.tpl` que es un Ingress con `ingressClassName: alb`.

**Sintomas**:
- `kubectl get ingress -A` muestra un Ingress con clase `alb`
- `kubectl get httproute -A` no muestra HTTPRoutes para la app
- El scope no tiene DNS resolution

**Solucion**: Agregar al modulo `agent` las variables `service_template`, `initial_ingress_path` y `blue_green_ingress_path` apuntando a los templates de `istio/`. Ver seccion "Agent HTTPRoute Templates" en [aws.md](aws.md).

## Validacion post-apply AWS

```bash
kubectl cluster-info
kubectl get ns | grep -E "nullplatform|istio"
kubectl get pods -n nullplatform-tools -l app=nullplatform-agent
kubectl get pods -n istio-system
kubectl get pods -n cert-manager
aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`*.{slug}.nullapps.io`].Status'
```
