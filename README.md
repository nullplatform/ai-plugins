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
- **np-checklist** - Inspect approval checklist runs, items, events, and logs

### np-governance

Governance and workflow authoring: query and operate on action items, categories and suggestions; manage approval checklists; build detector/executor agents; and author, publish and debug workflows.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-lake** - Query the Nullplatform Customer Lake with SQL across entities
- **np-governance-action-items** - List, create, and update action items, categories, and suggestions
- **np-governance-agent-builder** - Guided wizard to generate new governance detector/executor agents
- **np-workflow** - Build, publish, run, and debug workflows on the Nullplatform workflow engine
- **np-report** - Generate and persist dynamic reports and dashboards backed by the Customer Lake
- **np-checklist** - Manage approval checklist templates, action associations, runs, and manual approvals
- **np-catalog** - Build and query the nullplatform catalog: specifications, entities, relations, and knowledge-base ingestion

### np-workflow-craft

Focused toolkit for the Nullplatform workflow engine: author YAML, publish, trigger, and debug executions.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-workflow** - Build, publish, run, and debug workflows on the Nullplatform workflow engine

### np-catalog

Manage the nullplatform catalog: entity specifications, entity instances, relations, search/facets, interceptors/events, custom actions and authorization.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-catalog** - Build and query the nullplatform catalog: specifications, entities, relations, and knowledge-base ingestion

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
- **np-package-builder** - Build, run, and publish nullplatform packages with the np CLI
- **np-rules** - Shared rules the service skills follow: infrastructure as code, ask instead of inferring

### np-package-craft

Build, run, and publish nullplatform packages (scope / service / simple) with the np CLI: init, dev, test, build, run (local agent), publish, and artifact release metadata.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-package-builder** - Build, run, and publish nullplatform packages with the np CLI

### np-communications

Operate Communications through the public API or the CLI: inbox rules (write, validate, dry-run, test, activate), emitting invoked inbox rules from workflows or CI, announcements and banners, and troubleshooting who gets which notification.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-communications** - Write and test inbox rules, emit notifications from CI or a workflow, publish announcements and banners

### np-knowledge-base

Navigate, curate, and extend the organizational knowledge base built on the nullplatform catalog.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-workflow** - Build, publish, run, and debug workflows on the Nullplatform workflow engine
- **np-catalog** - Build and query the nullplatform catalog: specifications, entities, relations, and knowledge-base ingestion
- **np-kb-navigate** - Answer questions from the knowledge base, with provenance
- **np-kb-curate** - Keep the knowledge base healthy: merge duplicates, review suggestions, delete instances safely
- **np-kb-lore** - Register and consult cross-cutting norms, knowledge, and investigation instructions
- **np-kb-extend** - Plug an external source into the knowledge base and launch re-analyses

## Installation

### Kiro CLI

1. Clone this repository:
   ```bash
   git clone https://github.com/nullplatform/ai-plugins
   cd ai-plugins
   ```

2. Run the installer:
   ```bash
   # Install globally (available in any project)
   ./install-kiro.sh --global np-developer

   # Install in the current project only
   ./install-kiro.sh np-developer

   # Install multiple plugins
   ./install-kiro.sh --global np-developer np-troubleshooting

   # List available plugins
   ./install-kiro.sh --list
   ```

3. Switch to the `nullplatform` agent in Kiro:
   ```
   /agent nullplatform
   ```

#### Updating

```bash
./install-kiro.sh --update           # update local installation
./install-kiro.sh --update --global  # update global installation
```

The update command pulls the latest changes from git and reinstalls any previously installed plugins.

### Claude Code

#### From this marketplace

Add this repository as a plugin marketplace in Claude Code:

```bash
claude plugin marketplace add https://github.com/nullplatform/ai-plugins
```

Then install the plugin you need:

```bash
claude plugin install np-developer@nullplatform
# or
claude plugin install np-troubleshooting@nullplatform
# or
claude plugin install np-governance@nullplatform
# or
claude plugin install np-workflow-craft@nullplatform
# or
claude plugin install np-catalog@nullplatform
# or
claude plugin install np-service-craft@nullplatform
# or
claude plugin install np-package-craft@nullplatform
# or
claude plugin install np-communications@nullplatform
# or
claude plugin install np-knowledge-base@nullplatform
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
   cp -r marketplace/plugins/np-workflow-craft ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-catalog ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-service-craft ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-package-craft ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-communications ~/.claude/plugins/
   # or
   cp -r marketplace/plugins/np-knowledge-base ~/.claude/plugins/
   ```

3. Restart Claude Code

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Kiro CLI](https://kiro.dev) installed
- A Nullplatform account with API access
- For `np-lake` skill: Nullplatform Customer Lake access configured

## Support

- GitHub Issues: https://github.com/nullplatform/ai-plugins/issues
- Nullplatform: https://nullplatform.com

## License

Apache-2.0
