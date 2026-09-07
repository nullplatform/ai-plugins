# np-governance

Governance & workflow authoring on the Nullplatform engine: query and operate on action items, categories and suggestions; build detector/executor agents; manage approval checklists (templates, action associations, runs, manual approvals); and author, publish, validate and test workflows (YAML, signals, triggers, config-entry secrets) — including the local kit (npx @nullplatform/workflow-kit) and the nullplatform/workflows corpus. Workflows commonly read the lake and drive action items, so all live together here.

## Version



## Skills Included

### np-api

description: This skill should be used when the user asks to "query the nullplatform API", "check authentication", "fetch API data", "search endpoints", "describe an endpoint", "set up project context", "which application is this repo", "pin this repo to an application", mentions a .np folder, or needs to make any programmatic call to api.nullplatform.com. Provides centralized API access with authentication and token management.

### np-lake

description: Query nullplatform Customer Lake. Use for cross-entity relationship queries, bulk entity state analysis, approval workflow investigation, parameter configuration audit, auth/RBAC audits, service & link inventory, and complex SQL queries across 64 tables in 8 domains (Approvals, Audit, Auth, Core Entities, Governance, Parameters, SCM, Services). Use when users need current state of multiple entities, joins across tables, or analytical queries. PREFERRED over individual API calls for data retrieval — a single SQL query replaces multiple API requests.

### np-workflow

description: Build, publish, run, and debug workflows on the Nullplatform workflow engine via REST API. Use when the user asks to "create a workflow", "publish a workflow", "list workflow plugins", "trigger a webhook", "check an execution", "manage workflow secrets", "scaffold a workflow YAML", or any workflow-engine task. Requires NP_TOKEN or NP_API_KEY (same as np-api); NP_WORKFLOW_URL only for self-hosted engines (defaults to api.nullplatform.com).

### np-governance-action-items

description: Operate on Nullplatform Governance Action Items - list, create, update action items, manage categories and suggestions. Includes patterns for idempotency, reconciliation, and executor agents. Use when the user wants to query, create, modify or analyze action items, categories, or suggestions, or build agent flows around them.

### np-governance-agent-builder

description: Guided wizard to generate new Nullplatform Governance Action Item agents (detectors, executors, or both) inside the user's project. Use when the user says "create a governance agent", "new action item agent", "build a detector for X", "generar executor", or invokes /np-governance-create-action-item-agent.

### np-report

description: Generate, modify, and persist nullplatform dynamic reports (dashboards) to the Reports API. Use whenever the user asks to create, update, list, publish, or delete a report/dashboard/visualization/metrics view backed by the nullplatform Customer Lake. Generates the full report definition JSON (JSON Schema + ui_schema + SQL queries) itself — no MCP — validates queries best-effort against the Lake, and saves a draft via the Reports API.

### np-checklist

description: Operate on Nullplatform Approval Checklists — create and manage checklist specifications (formerly "checklist templates"), associate them with approval actions, inspect checklist runs (state, items, events, logs), apply manual approvals and overrides, and migrate existing policy-based actions to checklist mode. Use when the user asks to "create a checklist specification", "create a checklist template", "associate a checklist with an action", "view checklist run state", "approve a manual checklist item", "migrate from policies to checklist", or anything about checklist-mode approvals on the approval-api.

### np-catalog

description: The nullplatform catalog — building it and reading it. Building — specifications, instances (entities), relations (belongs_to, has_one, has_many, many_to_many), interceptors, events, custom actions, authorization, modeling an org's data as a graph, ingesting repos, docs, runbooks or services into a knowledge base, semantic fields and embeddings. Reading — any question answerable from records already in the catalog — analysing, reporting on, counting, comparing, auditing or explaining deployments, releases, services, applications, incidents or documents. Covers "give me the deployment analysis", "what shipped last month", "what changed across our services", "how many X by Y", "is this field trustworthy". Use it whenever a question could be answered from catalog data, even if the user never says "catalog", never names the API, and only asks for an analysis, summary or report. Also use when a spec change or ingest misbehaves. Requires NP_TOKEN or NP_API_KEY (same auth as np-api).

## Installation

### From Plugin Marketplace

1. Open Claude Code
2. Go to Plugins
3. Search for "np-governance"
4. Click Install

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nullplatform/np-claude-skills
   cd np-claude-skills
   ```

2. Build this plugin:
   ```bash
   ./scripts/build-plugins.sh --bundle np-governance
   ```

3. Copy to your Claude Code plugins directory:
   ```bash
   cp -r marketplace/plugins/np-governance ~/.claude/plugins/
   ```

4. Restart Claude Code

## Permissions

This plugin requires the following permissions:

```json
[
  "Bash(./.claude/skills/np-api/scripts/check_auth.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/fetch_np_api_url.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-api.sh:*)",
  "Bash(./.claude/skills/np-api/scripts/np-context.sh:*)",
  "Bash(./.claude/skills/np-catalog/scripts/catalog-api.sh:*)",
  "Bash(./.claude/skills/np-checklist/scripts/*.sh:*)",
  "Bash(./.claude/skills/np-governance-action-items/scripts/*.sh:*)",
  "Bash(./.claude/skills/np-governance-agent-builder/scripts/*.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/ch_query.sh:*)",
  "Bash(./.claude/skills/np-lake/scripts/check_ch_auth.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/execution.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/ping.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/plugins.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/publish.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/run.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/scaffold.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/trigger.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/workflow-api.sh:*)",
  "Bash(./.claude/skills/np-workflow/scripts/workflows.sh:*)",
  "Skill(np-api)",
  "Skill(np-api:*)",
  "Skill(np-catalog)",
  "Skill(np-catalog:*)",
  "Skill(np-checklist)",
  "Skill(np-checklist:*)",
  "Skill(np-governance-action-items)",
  "Skill(np-governance-action-items:*)",
  "Skill(np-governance-agent-builder)",
  "Skill(np-governance-agent-builder:*)",
  "Skill(np-lake)",
  "Skill(np-lake:*)",
  "Skill(np-report)",
  "Skill(np-report:*)",
  "Skill(np-workflow)",
  "Skill(np-workflow:*)"
]
```

These permissions are automatically configured when you install the plugin.

## Repository

https://github.com/nullplatform/np-claude-skills

## License

Apache-2.0

