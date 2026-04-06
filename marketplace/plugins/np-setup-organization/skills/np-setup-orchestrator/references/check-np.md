# check-np: Verify Nullplatform API

## Flow

### 1. Verify authentication

Invoke `/np-api check-auth`. If it fails (expired token), indicate how to renew it and STOP.

### 2. Query basic structure

Invoke `/np-api` to get:

| Information | Entity to query |
|-------------|-----------------|
| Organization | organization by ID |
| Accounts | accounts of the organization |
| Namespaces | namespaces by account |
| Providers | providers of the account |

### 3. Verify recent activity (last 8 hours)

For each account:

1. Search for namespace applications
2. Search for scopes of active applications
3. Search for application builds
4. Search for application deployments

Filter by `created_at > (now - 8h)` and verify status of the most recent ones.

5. Search for account service specifications. For each spec, verify that at least one recent active scope exists.

### 4. Verify endpoints

If there are active scopes with `domain_name`, verify healthcheck:

```bash
curl -s -o /dev/null -w "%{http_code}" -m 10 "https://{domain_name}{health_check_path}"
```

### 5. Verify scope telemetry

Invoke `/np-api` to get logs and metrics for the application associated with the scope:
- If it returns data → ok
- If it fails or is empty → recommend `/np-setup-troubleshooting`

### 6. Generate health report

For each operation type:
- ok = There is recent successful activity
- error = There is recent activity but it failed
- no activity = No recent activity (neutral)

## Recommendation Logic

Base on the **most recent activity**, not the complete history:

| Condition | Recommendation |
|-----------|----------------|
| No recent activity | "The account is configured. You can create an app from the UI." |
| Last app failed | `/np-setup-troubleshooting app {id}` |
| Last scope failed | `/np-setup-troubleshooting scope {id}` |
| Last build failed | "Review build logs in the UI or GitHub Actions" |
| Last deploy failed | `/np-setup-troubleshooting scope {scope_id}` |
| Endpoint not responding | `/np-setup-troubleshooting scope {id}` |
| Logs not working | `/np-setup-troubleshooting` (see Telemetry section) |
| Metrics not working | `/np-setup-troubleshooting` (see Telemetry section) |
| No scopes for a spec | "Create scope from UI or verify service specification" |
| All OK | "The complete flow is working correctly" |

> **Note**: Do not list ALL historically failed entities, only the most recent of each type if it failed.
