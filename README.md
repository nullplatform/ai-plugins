<h2 align="center">
    <a href="https://nullplatform.com" target="blank_">
        <img height="100" alt="nullplatform" src="https://nullplatform.com/favicon/android-chrome-192x192.png" />
    </a>
    <br>
    <br>
    Nullplatform AI Plugins
    <br>
</h2>

Official [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugins for [Nullplatform](https://nullplatform.com). These plugins extend Claude Code with specialized skills for working with the Nullplatform ecosystem.

## Available Plugins

### np-developer

Daily developer tools for Nullplatform: query APIs, manage deployments, operate scopes, and diagnose issues.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-developer-actions** - Developer operations: create scopes, deploy, manage parameters
- **np-investigation-diagnostic** - Investigate and troubleshoot deployments, services, and applications
- **np-lake** - Query the Nullplatform Customer Lake with SQL across entities
- **np-cli-assistant** - CLI command generation and documentation

### np-troubleshooting

Focused investigation and diagnostics toolkit for Nullplatform.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-investigation-diagnostic** - Investigate and troubleshoot deployments, services, and applications
- **np-lake** - Query the Nullplatform Customer Lake with SQL across entities

### np-governance

Governance Action Items: query and operate on action items, categories and suggestions; build new detector/executor agents with a guided wizard.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-lake** - Query the Nullplatform Customer Lake with SQL across entities
- **np-governance-action-items** - List, create, and update action items, categories, and suggestions
- **np-governance-agent-builder** - Guided wizard to generate new governance detector/executor agents

### np-service-craft

Tools for developing nullplatform services: design specs, write workflows, register with Terraform, and test locally.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-service-guide** - Entry point for all service development tasks with architecture overview
- **np-service-specs** - Author service spec files (service-spec.json.tpl, values.yaml, link specs)
- **np-service-workflows** - Write service workflows and scripts (build_context, do_tofu, entrypoints)
- **np-service-craft** - Orchestrate the full service lifecycle: creation, Terraform registration, and testing
- **np-service-creator** - Register services in Terraform with service_definition modules and agent bindings
- **np-agent-local-setup** - Set up a local nullplatform controlplane agent for development and testing
- **np-notification-manager** - Manage notification channels, debug delivery, and resend notifications

### np-setup-organization

Setup a new nullplatform organization: create org, configure cloud provider, provision infrastructure, and troubleshoot.

**Skills included:**
- **np-organization-create** - Create a new nullplatform organization via the onboarding API
- **np-setup-orchestrator** - Orchestrate the complete organization configuration end-to-end
- **np-api** - Explore and query the Nullplatform API
- **np-cloud-provider-setup** - Configure cloud provider credentials (AWS, Azure, GCP)
- **np-infrastructure-wizard** - Provision VPC, Kubernetes clusters, ingress, DNS, and deploy the NP agent
- **np-nullplatform-bindings-wizard** - Connect nullplatform with GitHub, container registries, and cloud providers
- **np-nullplatform-wizard** - Configure core nullplatform resources: scopes, dimensions, service definitions
- **np-setup-troubleshooting** - Diagnose failures in scopes, applications, telemetry, and permissions

## Installation

### From this marketplace

Add this repository as a plugin marketplace in Claude Code:

```bash
claude plugin add --marketplace https://github.com/nullplatform/ai-plugins
```

Then install the plugin you need:

```bash
claude plugin install np-developer
# or
claude plugin install np-troubleshooting
# or
claude plugin install np-governance
# or
claude plugin install np-service-craft
# or
claude plugin install np-setup-organization
```

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/nullplatform/ai-plugins
   cd ai-plugins
   ```

2. Copy the desired plugin to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-developer ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-troubleshooting ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-governance ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-service-craft ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-setup-organization ~/.claude/plugins/
   ```

3. Restart Claude Code

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A Nullplatform account with API access
- For `np-lake` skill: Nullplatform Customer Lake access configured

## Support

- GitHub Issues: https://github.com/nullplatform/ai-plugins/issues
- Nullplatform: https://nullplatform.com

## License

Apache-2.0
