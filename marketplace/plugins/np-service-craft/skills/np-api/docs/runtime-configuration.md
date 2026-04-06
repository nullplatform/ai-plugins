# Runtime Configuration

Runtime configurations permiten provisionar ambientes reutilizables que desacoplan la
infraestructura (DevOps) de la operacion de aplicaciones (Developers). Funcionan como
"facetas de busqueda para scopes": se definen atributos de dimensiones y los developers
seleccionan combinaciones al crear scopes.

**NOTA DEPRECACION**: Esta feature podria ser removida en el futuro. Nullplatform recomienda
usar platform settings y providers en su lugar.

## Concepto

- Los scopes solos son suficientes para escenarios simples
- Runtime configurations abordan infraestructura compleja (ej: produccion en diferentes cloud accounts)
- Requieren que las dimensions y sus valores existan ANTES de crear la runtime configuration
- Los valores se guardan internamente como NRN API profiles

## @endpoint /runtime_configuration

Lista runtime configurations.

### Parametros
- `nrn` (query, required): NRN con URL encoding

### Respuesta
Estructura por confirmar — el endpoint requiere permisos elevados con tokens de developer.
Con API keys estandar devuelve `"You're not authorized to perform this operation."`.

### Ejemplo
```bash
# Requiere permisos elevados (admin o platform team)
np-api fetch-api "/runtime_configuration?nrn=organization%3D<org>%3Aaccount%3D<acc>"
```

### Notas
- Sin NRN devuelve `"NRN is required for this endpoint"`
- Con NRN de developer devuelve `"You're not authorized to perform this operation."`
- Probablemente contiene configuraciones de runtime inyectadas a scopes/deployments
- Diferente de `parameters` que son variables de entorno explicitas
- Requiere investigacion con un token de admin o platform team para documentar completamente
- **Potencialmente deprecado** — considerar usar providers y platform settings

## Relacion con scopes

Las runtime configurations se asignan a scopes via:
- `POST /scope/{id}/runtime_configuration` — Asignar una runtime config a un scope
- `DELETE /scope/{id}/runtime_configuration/{id}` — Remover una runtime config de un scope

Estas operaciones estan documentadas en la documentacion oficial pero requieren permisos elevados.

## Relacion con dimensions

Las runtime configurations dependen del sistema de dimensions:
1. Crear dimensions y sus valores primero (`/dimension`)
2. Crear la runtime configuration referenciando esas dimensions
3. Los scopes que matcheen las dimensions heredan la configuracion
