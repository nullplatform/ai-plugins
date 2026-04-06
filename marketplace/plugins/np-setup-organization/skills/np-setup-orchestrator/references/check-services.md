# check-services: Verificar Servicios

## Propósito

Listar los servicios definidos en `services/`, verificar su estado de registro en terraform, y ofrecer acciones.

## Flujo

### 1. Escanear servicios locales

```bash
find services/ -path 'services/examples' -prune -o -name 'service-spec.json.tpl' -print 2>/dev/null
```

Para cada servicio encontrado, leer su spec y extraer: `name`, `slug`, `selectors.category`, `selectors.provider`.

### 2. Escanear ejemplos disponibles

```bash
find services/examples/ -name 'service-spec.json.tpl' 2>/dev/null
```

### 3. Verificar estado de registro

Para cada servicio (no ejemplo):
- Buscar en `nullplatform/main.tf` un module `service_definition_{slug}`
- Buscar en `nullplatform-bindings/main.tf` un module `service_definition_channel_association_{slug}`

### 4. Verificar estado en la API

Invocar `/np-api fetch-api "/service_specification?nrn=organization={org_id}&show_descendants=true"`

Comparar slugs locales vs slugs en la API:
- Existe en API y en terraform → registrado y desplegado
- Existe en terraform pero no en API → registrado pero no aplicado (`tofu apply` pendiente)
- No existe en terraform → no registrado

### 5. Ofrecer acciones al usuario

Usar AskUserQuestion con opciones dinámicas según estado:
- **Crear un servicio nuevo** → `/np-service-craft create`
- **Diagnosticar un servicio** → `/np-service-craft test <name>` o `/np-troubleshoot:np-investigate`
- **Modificar un servicio existente** → `/np-service-craft modify <name>`
- **Registrar un servicio** (si hay sin registrar) → `/np-service-craft register <name>`

Si no hay servicios, mostrar solo la opción de crear y los ejemplos disponibles.

## Lógica de Recomendaciones

| Condición | Recomendación |
|-----------|---------------|
| No hay servicios en `services/` | `/np-service-craft create` para crear el primero |
| Hay servicios sin registrar | `/np-service-craft register <name>` |
| Hay servicios registrados sin binding | Revisar `nullplatform-bindings/main.tf` |
| Servicios en terraform pero no en API | Ejecutar `tofu apply` en `nullplatform/` |
| Servicios con errores en API | `/np-troubleshoot:np-investigate service <id>` |
| Todo OK | Servicios configurados correctamente |
