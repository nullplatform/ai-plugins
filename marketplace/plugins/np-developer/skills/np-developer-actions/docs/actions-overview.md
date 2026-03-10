# Operaciones de Developer - Nullplatform API

Flujos de operaciones multi-paso para developers.
Para consultas de lectura, usar `/np-api fetch-api`.

## Operaciones Documentadas

| Operacion | Doc | Metodo | Endpoint | Descripcion |
|-----------|-----|--------|----------|-------------|
| Crear servicio | `services.md` | POST | /service | Provisionar nuevo servicio de infraestructura (DB, cola, cache) |
| Crear scope | `scopes.md` | POST | /scope | Crear un scope con discovery de tipos, dimensions y capabilities |
| Desplegar | `deployments.md` | POST | /deployment | Crear deployment eligiendo build/release y scope target |
| Crear parametro | `parameters.md` | POST | /parameter | Crear variable de entorno a nivel de aplicacion o scope |
| Modificar parametro | `parameters.md` | PATCH | /parameter/{id} | Modificar valor o nombre de un parametro existente |
| Eliminar parametro | `parameters.md` | DELETE | /parameter/{id} | Eliminar un parametro existente |
| Linkear servicio | `service-links.md` | POST | /link | Linkear un servicio existente y disponible a la aplicacion |
| Eliminar link | `service-links.md` | DELETE | /link/{id} | Eliminar un link existente |
| Eliminar servicio | `services.md` | POST | /service/{id}/action | Eliminar servicio via delete action (DELETE directo da 403) |
| Ejecutar custom action (servicio) | `custom-actions.md` | POST | /service/{id}/action | Ejecutar accion custom definida en el service specification |
| Ejecutar custom action (link) | `custom-actions.md` | POST | /link/{id}/action | Ejecutar accion custom definida en la link specification |
| Crear aplicacion | `applications.md` | POST | /application | Crear nueva aplicacion en un namespace con template y metadata |
| Modificar scope | `scopes.md` | PATCH | /scope/{id} | Modificar capabilities, requested_spec, tier, asset_name, nombre |
| Eliminar scope | `scopes.md` | DELETE | /scope/{id} | Eliminar scope y toda su infraestructura asociada |
| Crear release | `deployments.md` | POST | /release | Crear release a partir de un build (necesario para desplegar) |

## Flujo General

Cada operacion sigue el mismo patron:

1. **Discovery**: Consultar la API para obtener IDs, opciones disponibles, schemas
2. **Preguntar**: Usar `AskUserQuestion` para que el usuario elija opciones
3. **Confirmar**: Mostrar el body completo y pedir confirmacion
4. **Ejecutar**: `action-api.sh exec-api --method <M> --data '<json>' "<endpoint>"`
5. **Verificar**: Consultar el estado post-ejecucion y diagnosticar si fallo

## Regla Critica

**SIEMPRE confirmar con el usuario ANTES de ejecutar `exec-api`.**

Mostrar:
- **QUE**: metodo + endpoint + body completo
- **POR QUE**: motivo de la operacion
- Preguntar: "Procedo?"
