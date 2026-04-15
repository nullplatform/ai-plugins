# np-setup-organization

Setup a new nullplatform organization: create org, configure cloud provider, infrastructure, and troubleshooting

## Version



## Skills Included

### np-organization-create

description: This skill should be used when the user asks to "create an organization", "new nullplatform org", "onboard a new client", "initialize organization", "bootstrap nullplatform", "first-time setup", "set up a new client", "I need to create an org", "setting up nullplatform from scratch", or needs to create a new nullplatform organization via the onboarding API. This is an irreversible operation.

### np-setup-orchestrator

description: Orchestrates the complete configuration of a Nullplatform organization. Use when you need to initialize a project, verify infrastructure/cloud/K8s/API status, diagnose issues, or run tool, cloud, Kubernetes, Nullplatform API, telemetry, and service checks.

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-setup-troubleshooting

description: This skill should be used when the user asks "why did my scope fail", "why is my application broken", "diagnose setup failure", "troubleshoot permissions", "fix telemetry", or needs to diagnose why nullplatform entities (scopes, applications, telemetry, permissions) failed during setup.

### np-nullplatform-wizard

description: This skill should be used when the user asks to "configure nullplatform resources", "setup dimensions", "create service definitions", "configure scope types", or needs to configure core nullplatform resources including scopes, dimensions, and service definitions via Terraform.

### np-nullplatform-bindings-wizard

description: This skill should be used when the user asks to "connect GitHub", "setup container registry", "bind cloud provider", "configure bindings", "link external service", or needs to connect nullplatform with external services like GitHub, container registries (ECR, ACR, GCR), and cloud providers.

### np-cloud-provider-setup

description: This skill should be used when the user asks to "configure cloud credentials", "setup AWS access", "setup Azure access", "setup GCP access", "connect cloud provider", or needs to configure cloud provider authentication for nullplatform infrastructure provisioning.

### np-infrastructure-wizard

description: Creates cloud infrastructure for Nullplatform. Use when you need to configure VPC/VNet, Kubernetes clusters (EKS/AKS/GKE/OKE/ARO), ingress (Istio/ALB), DNS zones, tfstate backend, and deploy the Nullplatform agent. Supports AWS, Azure, Azure ARO, GCP, and OCI.

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-setup-organization"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-setup-organization
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-setup-organization ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-setup-orchestrator/scripts/check-tf-api-key.sh:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-cloud-provider-setup)",
  "Skill(np-cloud-provider-setup:*)",
  "Skill(np-infrastructure-wizard)",
  "Skill(np-infrastructure-wizard:*)",
  "Skill(np-nullplatform-bindings-wizard)",
  "Skill(np-nullplatform-bindings-wizard:*)",
  "Skill(np-nullplatform-wizard)",
  "Skill(np-nullplatform-wizard:*)",
  "Skill(np-organization-create)",
  "Skill(np-organization-create:*)",
  "Skill(np-setup-orchestrator)",
  "Skill(np-setup-orchestrator:*)",
  "Skill(np-setup-troubleshooting)",
  "Skill(np-setup-troubleshooting:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

