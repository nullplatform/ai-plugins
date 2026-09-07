# Decision Tree - Azure ARO Infrastructure

> Invoked from step 4 of the main wizard (`SKILL.md`).
> ARO uses OpenShift instead of AKS.

TODO: Implement following the pattern in [azure.md](azure.md).

Expected modules: resource_group, vnet, aro, dns, private_dns, base_security, cert_manager, istio, external_dns, prometheus.

> The nullplatform modules (`agent_api_key`, `agent`, `base`) are missing from that list and
> are always included — see [azure.md](azure.md#nullplatform-always-included-dont-ask).

## `base` values on ARO

Until this file is implemented, follow [azure.md](azure.md#the-base-block-on-azure) with two
differences:

- `k8s_provider = "aro"` (the module accepts `eks`, `gke`, `aks`, `oke`, `aro`)
- `metrics_server_enabled = false`, as a literal — ARO ships metrics-server with OpenShift
  monitoring, so `true` hits the same `APIService` ownership conflict as AKS and GKE. See
  [generation rule 35](infrastructure-generation.md#35-metrics_server_enabled-depends-on-cloud-provider).
