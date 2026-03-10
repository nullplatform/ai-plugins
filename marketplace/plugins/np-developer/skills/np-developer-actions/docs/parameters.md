# Parameters

Operaciones de gestion de parametros (variables de entorno) en Nullplatform.

## Modelo de datos

Los parametros tienen una estructura de dos niveles:

- **Parameter**: Definicion del parametro (nombre, tipo, secret, NRN)
- **Parameter Values**: Valores concretos por dimension (ej: un valor para production, otro para development)

Un parametro puede tener multiples values, cada uno con sus propias `dimensions`.
Esto permite configurar valores diferentes por ambiente sin crear parametros separados.

---

## @action POST /parameter

Crea un nuevo parametro (variable de entorno) en una aplicacion o scope.

### Flujo obligatorio de creacion

**IMPORTANTE**: Crear un parametro requiere conocer el NRN correcto y los parametros existentes.
Seguir estos pasos en orden:

#### Paso 1: Obtener datos de la aplicacion

```bash
np-api fetch-api "/application/<app_id>"
```

Del NRN extraer `organization_id`, `account_id`, `namespace_id`.

#### Paso 2: Consultar parametros existentes

```bash
# Parametros a nivel de aplicacion
np-api fetch-api "/parameter?nrn=organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>"
```

Mostrar al usuario los parametros existentes:

| Nombre | Tipo | Valor | Secret | Read Only |
|--------|------|-------|--------|-----------|
| DATABASE_URL | environment | postgres://... | true | false |
| REDIS_HOST | linked_service | (auto) | false | true |

Sirve para:
- Ver que parametros ya existen (evitar duplicados)
- Entender la configuracion actual
- Identificar parametros `read_only: true` (generados por service links, no modificables)

#### Paso 3: (Opcional) Consultar parametros de un scope especifico

Si el parametro debe aplicar solo a un scope:

```bash
# Parametros a nivel de scope
np-api fetch-api "/parameter?nrn=organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>:scope=<scope_id>"
```

#### Paso 4: Obtener scopes disponibles (si el parametro es por scope)

```bash
np-api fetch-api "/scope?application_id=<app_id>"
```

#### Paso 5: Armar cuestionario interactivo

Usando `AskUserQuestion`:

1. **Nombre del parametro**: texto libre (convencion: UPPER_SNAKE_CASE)
2. **Valor**: texto libre
3. **Nivel**: aplicacion (aplica a todos los scopes) o scope especifico
4. **Secreto**: si/no (los secretos se enmascaran en la UI y logs)
5. **Scope** (si eligio scope especifico): opciones del paso 4

#### Paso 6: Confirmar con el usuario

Mostrar el body completo que se va a enviar y pedir confirmacion.

#### Paso 7: Ejecutar

```bash
action-api.sh exec-api --method POST --data '<json>' "/parameter"
```

### Campos requeridos (POST /parameter)

- `name` (string): Nombre del parametro (UPPER_SNAKE_CASE)
- `nrn` (string): NRN del nivel donde aplica (aplicacion o scope)
- `variable` (string): Nombre de la env var (generalmente igual a `name`)
- `type` (string): `"environment"` para variables de entorno
- `secret` (boolean): Si es un valor sensible que debe enmascararse
- `encoding` (string): `"plaintext"`

### Body tipico: Parametro a nivel de aplicacion

```json
{
  "name": "DATABASE_URL",
  "nrn": "organization=<org_id>:account=<account_id>:namespace=<namespace_id>:application=<app_id>",
  "variable": "DATABASE_URL",
  "type": "environment",
  "encoding": "plaintext",
  "secret": true
}
```

### Body tipico: Parametro a nivel de scope

```json
{
  "name": "LOG_LEVEL",
  "nrn": "organization=<org_id>:account=<account_id>:namespace=<namespace_id>:application=<app_id>:scope=<scope_id>",
  "variable": "LOG_LEVEL",
  "type": "environment",
  "encoding": "plaintext",
  "secret": false
}
```

**NOTA**: POST /parameter crea la definicion del parametro. Para asignar valores con dimensiones
especificas (ej: valor diferente por ambiente), usar POST /parameter/{id}/value despues de crear
el parametro.

### Consultas previas (via /np-api)

- Aplicacion: `np-api fetch-api "/application/<app_id>"`
- Parametros existentes: `np-api fetch-api "/parameter?nrn=organization=<org>:account=<acc>:namespace=<ns>:application=<app>"`
- Parametros de scope: `np-api fetch-api "/parameter?nrn=organization=<org>:account=<acc>:namespace=<ns>:application=<app>:scope=<scope>"`
- Scopes: `np-api fetch-api "/scope?application_id=<app_id>"`

### Respuesta

- `id`: ID del parametro creado
- `name`: Nombre del parametro
- `nrn`: NRN del nivel
- `type`: `environment`
- `values[]`: Array de values (puede estar vacio si no se asigno valor en la creacion)

### Verificar resultado

```bash
# Verificar que el parametro se creo correctamente
np-api fetch-api "/parameter/<parameter_id>"
```

### Notas

- Los parametros de tipo `linked_service` son read-only (generados por service links)
- El nombre debe ser UPPER_SNAKE_CASE por convencion
- Un parametro a nivel de aplicacion aplica a TODOS los scopes
- Un parametro a nivel de scope sobreescribe al de aplicacion para ese scope
- Los cambios de parametros requieren un re-deploy para tomar efecto
- Los parametros marcados como `secret` se enmascaran en la UI y en logs

---

## @action PATCH /parameter/{id}

Modifica la definicion de un parametro existente (nombre o configuracion).

**IMPORTANTE**: PATCH /parameter solo modifica la definicion del parametro (nombre, secret, etc.).
NO modifica los valores. Para cambiar valores, usar PATCH en el value o crear/eliminar values.
Segun la documentacion oficial: "Replacing a field doesn't affect the underlying parameter values."

### Flujo obligatorio de modificacion

#### Paso 1: Obtener datos de la aplicacion y NRN

```bash
np-api fetch-api "/application/<app_id>"
```

#### Paso 2: Consultar parametros existentes para encontrar el ID

```bash
np-api fetch-api "/parameter?nrn=organization=<org>:account=<acc>:namespace=<ns>:application=<app>"
```

Identificar el parametro a modificar por nombre. Obtener su `id`.

**IMPORTANTE**: No se pueden modificar parametros `read_only: true` (generados por service links).

#### Paso 3: Preguntar al usuario que quiere cambiar

Usando `AskUserQuestion`:

1. **Cambiar nombre**: si/no (si si, pedir nuevo nombre)
2. **Cambiar secret**: si/no

#### Paso 4: Confirmar con el usuario

Mostrar el PATCH que se va a enviar y pedir confirmacion.

#### Paso 5: Ejecutar

```bash
action-api.sh exec-api --method PATCH --data '<json>' "/parameter/<parameter_id>"
```

### Campos opcionales (PATCH /parameter/{id})

- `name` (string): Nuevo nombre
- `variable` (string): Nuevo nombre de la env var
- `secret` (boolean): Cambiar visibilidad

### Body tipico

```json
{
  "name": "NEW_PARAM_NAME",
  "variable": "NEW_PARAM_NAME"
}
```

### Verificar resultado

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

### Notas

- Solo enviar los campos que cambian (es un PATCH, no un PUT)
- Los cambios requieren re-deploy para tomar efecto
- No se pueden modificar parametros `read_only: true`
- **No confundir con cambio de valor** - para eso usar las acciones de parameter value

---

## @action DELETE /parameter/{id}

Elimina un parametro junto con TODOS sus values y versions.

### Flujo obligatorio de eliminacion

#### Paso 1: Consultar parametros existentes

```bash
np-api fetch-api "/parameter?nrn=<nrn>"
```

Identificar el parametro a eliminar por nombre. Obtener su `id`.

#### Paso 2: Confirmar con el usuario

**Advertir que esta accion es irreversible** y que elimina el parametro junto con todos sus
values y versions. Si la aplicacion depende de este parametro, puede dejar de funcionar
despues del proximo deploy.

#### Paso 3: Ejecutar

```bash
action-api.sh exec-api --method DELETE --data '{}' "/parameter/<parameter_id>"
```

### Verificar resultado

```bash
np-api fetch-api "/parameter?nrn=<nrn>"
```

### Notas

- La eliminacion es irreversible (elimina parameter + todos sus values + todas sus versions)
- La aplicacion seguira usando el valor hasta el proximo re-deploy
- No se pueden eliminar parametros `read_only: true`

---

## @action POST /parameter/{id}/value

Crea un valor para un parametro, para una aplicacion o un scope con dimensiones especificas.

### Flujo obligatorio

#### Paso 1: Consultar el parametro y sus values actuales

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

Revisar los `values[]` existentes para entender que dimensiones ya tienen valor asignado.

#### Paso 2: Obtener scopes disponibles (para conocer las dimensiones)

```bash
np-api fetch-api "/scope?application_id=<app_id>"
```

De los scopes extraer las `dimensions` posibles (ej: `environment=production`, `country=usa`).

#### Paso 3: Preguntar al usuario

Usando `AskUserQuestion`:

1. **Valor**: texto libre
2. **Dimensiones**: que dimensiones aplican (ej: `environment=production`)
3. **NRN**: si el valor es a nivel de aplicacion o de un scope especifico

#### Paso 4: Confirmar con el usuario

Mostrar el body completo y pedir confirmacion.

#### Paso 5: Ejecutar

```bash
action-api.sh exec-api --method POST --data '<json>' "/parameter/<parameter_id>/value"
```

### Campos requeridos (POST /parameter/{id}/value)

- `value` (string): El valor concreto
- `nrn` (string): NRN donde aplica (aplicacion o scope)
- `dimensions` (object): Dimensiones donde aplica el valor (ej: `{"environment": "production"}`)

### Body tipico

```json
{
  "value": "172.20.144.91",
  "nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
  "dimensions": {"environment": "production"}
}
```

### Verificar resultado

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

Verificar que el nuevo value aparece en el array `values[]`.

### Notas

- Un parametro puede tener multiples values con dimensiones diferentes
- Las dimensiones determinan a que scopes aplica el valor
- Los cambios requieren re-deploy para tomar efecto

---

## @action POST /parameter/{id}/values

Crea multiples values de una vez para un parametro.

### Flujo obligatorio

Mismo flujo que POST /parameter/{id}/value pero con un array de values.

### Body tipico

```json
[
  {
    "value": "prod-host.example.com",
    "nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
    "dimensions": {"environment": "production"}
  },
  {
    "value": "dev-host.example.com",
    "nrn": "organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>",
    "dimensions": {"environment": "development"}
  }
]
```

### Ejemplo

```bash
action-api.sh exec-api --method POST --data '[{"value":"prod-val","nrn":"...","dimensions":{"environment":"production"}},{"value":"dev-val","nrn":"...","dimensions":{"environment":"development"}}]' "/parameter/<parameter_id>/values"
```

### Notas

- Util para configurar un parametro en multiples ambientes de una sola vez
- Cada value del array sigue la misma estructura que POST /parameter/{id}/value

---

## @action DELETE /parameter/{parameterId}/value/{id}

Elimina un valor especifico de un parametro.

### Flujo obligatorio

#### Paso 1: Consultar el parametro y sus values

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

Identificar el value a eliminar por sus `dimensions` o `value`. Obtener su `id`.

#### Paso 2: Confirmar con el usuario

Mostrar que value se va a eliminar (incluyendo dimensions y valor actual).

#### Paso 3: Ejecutar

```bash
action-api.sh exec-api --method DELETE --data '{}' "/parameter/<parameter_id>/value/<value_id>"
```

### Verificar resultado

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

Verificar que el value ya no aparece en `values[]`.

### Notas

- Eliminar un value no elimina el parametro, solo ese valor especifico
- Si se eliminan todos los values, el parametro queda sin valor asignado
- Respuesta: 204 No Content

---

## @action DELETE /parameter/{parameterId}/values

Elimina multiples values de un parametro de una vez.

### Flujo obligatorio

#### Paso 1: Consultar el parametro y sus values

```bash
np-api fetch-api "/parameter/<parameter_id>"
```

#### Paso 2: Confirmar con el usuario

Listar todos los values que se eliminaran y pedir confirmacion explicita.

#### Paso 3: Ejecutar

```bash
action-api.sh exec-api --method DELETE --data '{}' "/parameter/<parameter_id>/values"
```

### Notas

- Elimina TODOS los values del parametro (no el parametro en si)
- Respuesta: 204 No Content
- Usar con precaucion - puede dejar el parametro sin valores

---

## Visibilidad de secretos (`parameter:read-secrets`)

Los parametros marcados como `secret: true` tienen sus valores enmascarados por defecto.
Para ver el valor real de un parametro secreto, se requiere un approval de tipo
`parameter:read-secrets`.

### Como funciona

1. Cuando se intenta leer el valor de un parametro secreto, la API devuelve el valor enmascarado
2. Para obtener acceso temporal al valor real, se debe crear un approval request
3. El approval puede ser auto-aprobado por policies o requerir aprobacion manual
4. Si se aprueba, se otorga acceso temporal (tipicamente 24 horas)
5. El approval request expira despues de ~3 dias si no se responde

### Flujo para ver secretos

#### Paso 1: Identificar el parametro secreto

```bash
np-api fetch-api "/parameter?nrn=organization=<org>:account=<acc>:namespace=<ns>:application=<app>"
```

Buscar parametros con `secret: true`.

#### Paso 2: Solicitar acceso

El acceso a secretos se gestiona via el sistema de approvals. Buscar si existe un approval
pendiente o crear uno nuevo:

```bash
# Buscar approvals existentes para parametros de esta aplicacion
np-api fetch-api "/approval?nrn=<nrn_url_encoded>&entity=parameter&action=read-secrets"
```

#### Paso 3: Interpretar el approval

| `status` | Significado | Accion |
|----------|-------------|--------|
| `auto_approved` | Policies permiten ver secretos | Acceso otorgado temporalmente |
| `pending` | Requiere aprobacion manual | Solicitar por canal correspondiente |
| `approved` | Aprobado manualmente | Acceso otorgado temporalmente |
| `auto_denied` | Policies no permiten | Escalar a administrador |
| `denied` | Rechazado | Escalar a administrador |
| `expired` | Expiro sin respuesta (~3 dias) | Reintentar |

### Notas

- El acceso a secretos es **temporal** (tipicamente 24 horas)
- Cada solicitud de acceso queda registrada en el audit log
- Las policies de la organizacion determinan si el acceso es automatico o requiere aprobacion
- Este mecanismo aplica a la UI y a la API por igual
- Los parametros de tipo `linked_service` tambien pueden ser secretos
