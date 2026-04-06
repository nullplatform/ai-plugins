# check-services: Verify Services

## Purpose

List services defined in `services/`, verify their registration status in terraform, and offer actions.

## Flow

### 1. Scan local services

```bash
find services/ -path 'services/examples' -prune -o -name 'service-spec.json.tpl' -print 2>/dev/null
```

For each service found, read its spec and extract: `name`, `slug`, `selectors.category`, `selectors.provider`.

### 2. Scan available examples

```bash
find services/examples/ -name 'service-spec.json.tpl' 2>/dev/null
```

### 3. Verify registration status

For each service (not example):
- Search in `nullplatform/main.tf` for a module `service_definition_{slug}`
- Search in `nullplatform-bindings/main.tf` for a module `service_definition_channel_association_{slug}`

### 4. Verify status in the API

Invoke `/np-api fetch-api "/service_specification?nrn=organization={org_id}&show_descendants=true"`

Compare local slugs vs slugs in the API:
- Exists in API and in terraform → registered and deployed
- Exists in terraform but not in API → registered but not applied (`tofu apply` pending)
- Does not exist in terraform → not registered

### 5. Offer actions to the user

Use AskUserQuestion with dynamic options based on status:
- **Create a new service** → `/np-service-craft create`
- **Diagnose a service** → `/np-service-craft test <name>` or `/np-troubleshoot:np-investigate`
- **Modify an existing service** → `/np-service-craft modify <name>`
- **Register a service** (if there are unregistered ones) → `/np-service-craft register <name>`

If there are no services, show only the create option and available examples.

## Recommendation Logic

| Condition | Recommendation |
|-----------|----------------|
| No services in `services/` | `/np-service-craft create` to create the first one |
| Unregistered services | `/np-service-craft register <name>` |
| Registered services without binding | Review `nullplatform-bindings/main.tf` |
| Services in terraform but not in API | Run `tofu apply` in `nullplatform/` |
| Services with errors in API | `/np-troubleshoot:np-investigate service <id>` |
| All OK | Services configured correctly |
