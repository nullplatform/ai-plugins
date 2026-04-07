# Troubleshooting

For cloud-specific problems see: [aws-troubleshooting.md](aws-troubleshooting.md).

## Certificate in PENDING_VALIDATION

**Cause**: The DNS subzone is not delegated from `nullapps.io`.

**Solution**:
1. Verify delegation: `dig NS {slug}.nullapps.io +short`
2. If there are no NS records, request delegation from Nullplatform (see wizard step 5.5)
3. Once delegated, the certificate will validate automatically

## Cluster doesn't get created

- Verify cloud provider quotas
- Review service account/role permissions

## Agent doesn't connect

- Verify authentication: invoke `/np-api check-auth`
- Verify `tags_selectors` match the expected configuration

## DNS doesn't resolve

- Verify that external-dns is running
- Review DNS provider configuration
- Verify subzone delegation

## Error: namespace already exists

**Cause**: If a `tofu apply` fails mid-execution (e.g., certificate timeout), some resources were already created but were not registered in the Terraform state.

**Solution**: Import the existing resource into the state:

```bash
tofu import module.ingress.kubernetes_namespace_v1.namespace nullplatform
tofu apply
```

**Prevention**: Follow the DNS-first flow (step 5) to avoid certificate timeouts.

## Post-apply validation

See [post-apply-validation.md](post-apply-validation.md) for the complete validation flow (pre-checks, schema detection, and all cluster-level validations).
