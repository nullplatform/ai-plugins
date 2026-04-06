# AWS Troubleshooting

For generic problems (DNS, agent, namespace) see [troubleshooting.md](troubleshooting.md).

## ALB Controller webhook not ready

**Cause**: The ALB Controller needs ~2 minutes to register its validation webhook. If other Helm charts are applied before, they fail with webhook errors.

**Solution**: Verify that subsequent Helm modules (`cert_manager`, `external_dns`, `istio`, `ingress`) have `depends_on = [module.alb_controller]`. Also verify that `alb_controller_iam` is included and that `alb_controller` depends on it (it creates the required service account).

```bash
kubectl get validatingwebhookconfigurations | grep alb
```

## IRSA role not working

**Cause**: The EKS cluster's OIDC provider doesn't match the IAM role's trust policy, or the service account doesn't have the correct annotation.

**Solution**:
1. Verify OIDC provider: `aws eks describe-cluster --name {cluster} --query "cluster.identity.oidc.issuer"`
2. Verify role trust policy: `aws iam get-role --role-name {role} --query "Role.AssumeRolePolicyDocument"`
3. Verify service account annotation: `kubectl get sa {sa-name} -n {namespace} -o yaml | grep eks.amazonaws.com/role-arn`

## EKS endpoint not accessible

**Cause**: The EKS cluster has public/private access configuration that doesn't allow connection from where tofu is running.

**Solution**:
1. Verify access config: `aws eks describe-cluster --name {cluster} --query "cluster.resourcesVpcConfig.{publicAccess:endpointPublicAccess,privateAccess:endpointPrivateAccess}"`
2. If private only, tofu must run from within the VPC or via VPN
3. If public, verify the source CIDR is in the allowlist

## S3 backend permission denied

**Cause**: The AWS CLI profile doesn't have permissions on the S3 bucket.

**Solution**:
1. Verify profile: `aws sts get-caller-identity --profile {profile}`
2. Verify bucket access: `aws s3 ls s3://{bucket} --profile {profile}`
3. Verify that `backend.tf` has the correct `profile` (mandatory in AWS)

## NLB targets unhealthy (FailedHealthChecks)

**Cause**: The EKS cluster SG doesn't have ingress rules allowing traffic from the NLB (gateway) SG. The NLB with target type `ip` sends traffic directly to pods. Without explicit rules in the cluster SG, health checks (port 15021) and HTTPS traffic (port 443) are blocked.

**Symptoms**:
- DNS resolves correctly (dig returns NLB IPs)
- curl times out (doesn't connect to port 443)
- NLB target groups show `Target.FailedHealthChecks`

**Solution**:
1. Verify that the `security` module receives `cluster_security_group_id` with the **primary SG**:
   ```hcl
   cluster_security_group_id = module.eks.eks_cluster_primary_security_group_id
   ```
2. DO NOT use `eks_cluster_security_group_id` (it's the additional SG, not attached to nodes)
3. Verify targets: `aws elbv2 describe-target-health --target-group-arn {arn}`
4. Verify cluster SG rules: `aws ec2 describe-security-group-rules --filters "Name=group-id,Values={cluster_sg_id}"`

**Difference between EKS SGs**:
- `eks_cluster_primary_security_group_id`: Created by EKS, automatically attached to all nodes. Name: `eks-cluster-sg-{cluster}-*`
- `eks_cluster_security_group_id`: Created by the EKS Terraform module (additional). Name: `{cluster}-cluster-*`

## Agent creates ALB Ingress instead of HTTPRoute

**Cause**: The agent doesn't have Istio template variables configured. By default it uses `/root/.np/nullplatform/scopes/k8s/deployment/templates/initial-ingress.yaml.tpl` which is an Ingress with `ingressClassName: alb`.

**Symptoms**:
- `kubectl get ingress -A` shows an Ingress with class `alb`
- `kubectl get httproute -A` doesn't show HTTPRoutes for the app
- The scope has no DNS resolution

**Solution**: Add to the `agent` module the `service_template`, `initial_ingress_path`, and `blue_green_ingress_path` variables pointing to the `istio/` templates. See "Agent HTTPRoute Templates" section in [aws.md](aws.md).

## AWS post-apply validation

```bash
kubectl cluster-info
kubectl get ns | grep -E "nullplatform|istio"
kubectl get pods -n nullplatform-tools -l app=nullplatform-agent
kubectl get pods -n istio-system
kubectl get pods -n cert-manager
aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`*.{slug}.nullapps.io`].Status'
```
