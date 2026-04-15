# State File: organization-{name}.md

State file for tracking the organization creation flow across context compactions. Created at Step 7, updated after Steps 8 and 9.

## Template

```markdown
# Organization: {organization_name}

| Field | Value |
|-------|-------|
| Organization ID | {id} |
| Organization Name | {organization_name} |
| Account Name | {account_name} |
| Created At | {timestamp} |
| Current Phase | {phase} |

## Owners

| Email | First Name | Last Name | Status |
|-------|------------|-----------|--------|
| {email} | {name} | {last_name} | invited |

## Phase History

- [ ] `org-created` — Organization POST succeeded, organization.properties written
- [ ] `api-key-created` — Org-scoped API key saved in np-api.key
- [ ] `complete` — All verification checks passed

## Notes

{any relevant context for resuming the flow}
```

## Lifecycle

| Event | Update |
|-------|--------|
| Step 7 completes (org created) | Create file, set phase to `org-created` |
| Step 8 completes (API key saved) | Set phase to `api-key-created` |
| Step 9 completes (verification passes) | Set phase to `complete`, check all boxes |
| Error at any step | Add error details to Notes section |

## Usage

Read this file at the start of any operation to restore context after compaction. If the file exists and phase is not `complete`, resume from the current phase instead of starting over.
