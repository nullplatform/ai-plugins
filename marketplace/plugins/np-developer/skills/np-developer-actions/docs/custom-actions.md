# Custom Actions

Ejecutar acciones custom definidas en un service specification o link specification.

Las **custom actions** permiten a los developers operar componentes de infraestructura de manera
auditada, con aprobaciones y limitando el alcance a comandos especificos definidos por el platform team.

## Tipos de action specifications

| Tipo | Proposito | Visible en "Run action" | Quien la ejecuta |
|------|-----------|------------------------|-------------------|
| `create` | Provisionar el recurso al crearlo | No | Cliente al crear service/link |
| `update` | Actualizar configuracion del recurso | No | Cliente al actualizar |
| `delete` | Destruir el recurso al eliminarlo | No | Cliente al eliminar |
| `custom` | Operaciones ad-hoc definidas por el platform team | **Si** | Developer bajo demanda |

Solo las de tipo `custom` aparecen en el dropdown "Run action" del frontend y son las que
el developer puede ejecutar en cualquier momento.

## Donde pueden existir custom actions

- **A nivel de servicio**: definidas en el `service_specification`. Se ejecutan con `POST /service/{id}/action`.
  Ejemplo: "Run DML Query", "Run DDL Query" en un Postgres DB.
- **A nivel de link**: definidas en la `link_specification`. Se ejecutan con `POST /link/{id}/action`.
  Solo disponibles si la link specification tiene custom action specs configuradas.

---

## @action POST /service/{id}/action (custom)

Ejecuta una custom action sobre un servicio.

### Flujo obligatorio

> **IMPORTANTE**: Este flujo usa `/np-api fetch-api` para LECTURA (discovery, pasos 1-3)
> y `/np-developer-actions exec-api` para ESCRITURA (paso 6). NUNCA usar `curl` ni
> `/np-api` para operaciones POST.

#### Paso 1: Obtener datos del servicio

```bash
np-api fetch-api "/service/<service_id>"
```

Del response obtener `specification_id` (service specification ID).

#### Paso 2: Listar action specifications disponibles

```bash
np-api fetch-api "/service_specification/<spec_id>/action_specification"
```

Filtrar las de `type: "custom"`. Estas son las que el developer puede ejecutar.

Mostrar al usuario las acciones disponibles con:

| # | Nombre | Slug | Parametros requeridos |
|---|--------|------|----------------------|

Donde:
- **Nombre**: `name` de la action specification
- **Slug**: `slug` (se usa como `name` en el POST)
- **Parametros requeridos**: campos `required` del `parameters.schema`

Si solo hay una custom action disponible y el usuario ya indico cual quiere, saltar al paso 4.

#### Paso 3: Preguntar al usuario que accion ejecutar

Usando `AskUserQuestion`, mostrar las custom actions disponibles (max 4 opciones).

#### Paso 4: Obtener parametros de la accion

Del `parameters.schema` de la action specification elegida, extraer:
- **Campos requeridos** (`required[]`): el usuario debe completarlos
- **Campos opcionales**: mostrar con sus defaults
- **Tipo de cada campo**: string, boolean, number, object, array, enum

Presentar los campos al usuario y pedir valores. Si hay `uiSchema`, usarlo como guia
para la presentacion (ej: `"multi": true` indica un textarea).

#### Paso 5: Confirmar con el usuario

Mostrar:
- **QUE**: `POST /service/{service_id}/action` con body completo
- **POR QUE**: "Para ejecutar la accion X en el servicio Y con parametros Z"

Pedir confirmacion explicita.

#### Paso 6: Ejecutar

```bash
action-api.sh exec-api --method POST --data '{
  "name": "<action_slug>",
  "specification_id": "<action_spec_id>",
  "parameters": { <valores_de_los_parametros> }
}' "/service/<service_id>/action"
```

Campos del body:
- `name` (string, required): slug de la action specification (ej: "run-dml-query")
- `specification_id` (uuid, required): ID de la action specification de tipo `custom`
- `parameters` (object, required): valores de los campos de `parameters.schema`

#### Paso 7: Verificar resultado

La action pasa por: `pending` → `in_progress` → `success` o `failed`.

```bash
# Polling del status (esperar ~15 segundos entre intentos)
np-api fetch-api "/service/<service_id>/action/<action_id>"
```

Si `status: "success"`:
- Mostrar `results` al usuario (contiene los valores de salida definidos en `results.schema`)

Si `status: "failed"`:
- Consultar con messages para diagnosticar:

```bash
np-api fetch-api "/service/<service_id>/action/<action_id>?include_messages=true"
```

- Los messages contienen logs del agente (linea por linea del script que ejecuto)
- Buscar lineas con `error:` para identificar la causa del fallo

### Body tipico

```json
{
  "name": "<action-slug>",
  "specification_id": "<action-spec-uuid>",
  "parameters": {
    "campo1": "valor1",
    "campo2": true
  }
}
```

### Respuesta

- `id`: UUID de la action creada
- `status`: `pending` → `in_progress` → `success` | `failed`
- `parameters`: los parametros enviados
- `results`: los valores de salida (definidos por `results.schema` de la action spec)
- `created_by`: ID del usuario que la creo
- `created_at` / `updated_at`: timestamps

### Notas

- Las custom actions NO afectan el status del service/link parent (a diferencia de create/update/delete)
- El `name` del POST body es el `slug` de la action spec, no un nombre libre
- Los `parameters` deben cumplir con el `parameters.schema` de la action spec
- Los `results` siguen el `results.schema` de la action spec
- El agente ejecuta un script especifico por action (ej: `postgres-db/service/run-dml-query`)
- El agente puede crear pods efimeros en K8s para ejecutar la accion (ConfigMap + Secret + Pod)
- El tiempo de ejecucion varia segun la accion (tipicamente 10-30 segundos)
- Las custom actions son auditables: quedan registradas con quien las ejecuto y cuando

---

## @action POST /link/{id}/action (custom)

Ejecuta una custom action sobre un link.

### Flujo obligatorio

Identico al flujo de servicio pero:

1. Obtener la `specification_id` del link (link specification ID)
2. Consultar action specifications de la link specification:

```bash
np-api fetch-api "/link_specification/<link_spec_id>/action_specification"
```

3. Filtrar por `type: "custom"`
4. Ejecutar contra el endpoint del link:

```bash
action-api.sh exec-api --method POST --data '{
  "name": "<action_slug>",
  "specification_id": "<action_spec_id>",
  "parameters": { ... }
}' "/link/<link_id>/action"
```

### Notas

- No todas las link specifications tienen custom actions
- Si no hay custom actions, el boton "Run action" del link aparece deshabilitado en la UI
