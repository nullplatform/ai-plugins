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
- **np-audits-read** - Query audit logs via BigQuery
- **np-doc-authoring** - Author documentation pages for the Nullplatform docsite
- **np-cli-assistant** - CLI command generation and documentation
- **np-design** - Design system guardian for UI development

### np-troubleshooting

Focused investigation and diagnostics toolkit for Nullplatform.

**Skills included:**
- **np-api** - Explore and query the Nullplatform API
- **np-audits-read** - Query audit logs via BigQuery
- **np-investigation-diagnostic** - Investigate and troubleshoot deployments, services, and applications

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
   ```

3. Restart Claude Code

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A Nullplatform account with API access
- For audit log skills: Google Cloud BigQuery access configured

## Support

- GitHub Issues: https://github.com/nullplatform/ai-plugins/issues
- Nullplatform: https://nullplatform.com

## License

Apache-2.0
