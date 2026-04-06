# check-np: Verificar Nullplatform API

## Flujo

### 1. Verificar autenticación

Invocar `/np-api check-auth`. Si falla (token expirado), indicar cómo renovarlo y DETENERSE.

### 2. Consultar estructura básica

Invocar `/np-api` para obtener:

| Información | Entidad a consultar |
|-------------|---------------------|
| Organization | organization por ID |
| Accounts | accounts de la organization |
| Namespaces | namespaces por account |
| Providers | providers del account |

### 3. Verificar actividad reciente (últimas 8 horas)

Para cada account:

1. Buscar aplicaciones del namespace
2. Buscar scopes de las aplicaciones activas
3. Buscar builds de las aplicaciones
4. Buscar deployments de las aplicaciones

Filtrar por `created_at > (now - 8h)` y verificar status de los más recientes.

5. Buscar service specifications del account. Para cada spec, verificar que existe al menos un scope activo reciente.

### 4. Verificar endpoints

Si hay scopes activos con `domain_name`, verificar healthcheck:

```bash
curl -s -o /dev/null -w "%{http_code}" -m 10 "https://{domain_name}{health_check_path}"
```

### 5. Verificar telemetría del scope

Invocar `/np-api` para obtener logs y métricas de la aplicación asociada al scope:
- Si retorna datos → ok
- Si falla o vacío → recomendar `/np-setup-troubleshooting`

### 6. Generar reporte de salud

Para cada tipo de operación:
- ok = Hay actividad exitosa reciente
- error = Hay actividad reciente pero falló
- sin actividad = Sin actividad reciente (neutral)

## Lógica de Recomendaciones

Basarse en la **actividad más reciente**, no en el historial completo:

| Condición | Recomendación |
|-----------|---------------|
| Sin actividad reciente | "La cuenta está configurada. Podés crear una app desde la UI." |
| Última app falló | `/np-setup-troubleshooting app {id}` |
| Último scope falló | `/np-setup-troubleshooting scope {id}` |
| Último build falló | "Revisar logs del build en la UI o GitHub Actions" |
| Último deploy falló | `/np-setup-troubleshooting scope {scope_id}` |
| Endpoint no responde | `/np-setup-troubleshooting scope {id}` |
| Logs no funcionan | `/np-setup-troubleshooting` (ver sección Telemetría) |
| Métricas no funcionan | `/np-setup-troubleshooting` (ver sección Telemetría) |
| Sin scopes de un spec | "Crear scope desde UI o verificar service specification" |
| Todo OK | "El flujo completo funciona correctamente" |

> **Nota**: No listar TODAS las entidades fallidas históricamente, solo la más reciente de cada tipo si falló.
