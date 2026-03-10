# Deployments

Operaciones de deployment en Nullplatform: crear y gestionar despliegues.

## @action POST /deployment

Crea un nuevo deployment en un scope.

### Flujo obligatorio de deployment

**IMPORTANTE**: Un deployment requiere un proceso de discovery previo. NO asumir valores.
Seguir estos pasos en orden:

#### Paso 1: Obtener datos de la aplicacion

```bash
np-api fetch-api "/application/<app_id>"
```

Del NRN extraer `organization_id` y `account_id`.

#### Paso 2: Obtener scopes disponibles

```bash
np-api fetch-api "/scope?application_id=<app_id>"
```

Filtrar por `status: "active"` (ignorar `failed`, `deleted`, `stopped`).

Mostrar al usuario los scopes disponibles:

| Nombre | ID | Environment | Status |
|--------|----|-------------|--------|
| Production | <scope_id_1> | production | active |
| Staging | <scope_id_2> | staging | active |

**Preguntar al usuario en que scope quiere desplegar.**

#### Paso 3: Obtener builds disponibles

```bash
# Builds recientes de la aplicacion
np-api fetch-api "/build?application_id=<app_id>&status=success&sort=created_at:desc&limit=10"
```

Mostrar al usuario los builds disponibles:

| Build ID | Branch | Commit | Fecha |
|----------|--------|--------|-------|
| <build_id_1> | main | a1b2c3d | 2026-02-12 |
| <build_id_2> | develop | e4f5g6h | 2026-02-11 |

**Preguntar al usuario que build quiere desplegar.**

#### Paso 4: Obtener releases del build elegido

```bash
np-api fetch-api "/release?application_id=<app_id>&build_id=<build_id>"
```

Si el build tiene un release existente, usarlo. Si no tiene release, crear uno primero
(ver seccion `## @action POST /release` mas abajo).

#### Paso 5: Verificar asset_name del scope

**IMPORTANTE**: El scope debe tener `asset_name` configurado para poder desplegar.
Si `asset_name` es `null`, el deployment fallara con un error confuso:
`"The scope and the release belongs to different applications"`.

```bash
np-api fetch-api "/scope/<scope_id>"
```

Verificar que el campo `asset_name` no sea `null`. Valores tipicos: `"docker-image-asset"`, `"lambda-asset"`.

Si `asset_name` es `null`, se debe setear antes de desplegar:

```bash
action-api.sh exec-api --method PATCH --data '{"asset_name":"docker-image-asset"}' "/scope/<scope_id>"
```

Para saber que assets existen, consultar el release:

```bash
np-api fetch-api "/release/<release_id>"
```

Los assets disponibles dependen del template de la aplicacion. Comunes:
- `docker-image-asset`: para scopes K8s y EC2
- `lambda-asset`: para scopes serverless

**Preguntar al usuario que asset usar si hay mas de uno.**

#### Paso 6: Analisis pre-deploy

Antes de desplegar, recopilar informacion del estado actual del scope para informar al usuario.

##### 6a: Consultar deployment activo del scope

```bash
# Ver el scope para obtener el deployment activo y la configuracion
np-api fetch-api "/scope/<scope_id>"
```

Del scope extraer:
- `active_deployment`: ID del deployment activo actual (si existe)
- `domain`: URL publica del scope (si aplica)
- `capabilities.health_check`: path y configuracion del health check
- `capabilities.visibility.reachability`: si es `public` o `private`

```bash
# Ver deployments recientes del scope
np-api fetch-api "/deployment?scope_id=<scope_id>&sort=created_at:desc&limit=5"
```

##### 6b: Determinar tipo de deploy (initial vs blue-green)

Si el scope **no tiene** `active_deployment` (es null o no existe):
- Este sera un deploy **initial** (primera vez). No habra traffic switch.
- Informar: "Este es el primer deployment en este scope. Se crearan los recursos desde cero."

Si el scope **tiene** `active_deployment`:
- Este sera un deploy **blue-green** con traffic switch.
- Consultar el deployment activo para saber que version esta corriendo:

```bash
np-api fetch-api "/deployment/<active_deployment_id>?include_messages=true"
```

- Obtener el `release_id` del deployment activo y consultar el release para saber la version:

```bash
np-api fetch-api "/release/<release_id_activo>"
```

- Informar al usuario el cambio de version: "Version actual: vX.Y.Z → Nueva version: vA.B.C"

##### 6c: Comparar mensajes con deployment anterior

Si hay deployments anteriores finalizados en el scope, sirven como referencia para saber
que eventos esperar y cuanto tardo. Revisar los `messages` del ultimo deployment exitoso
(`status: finalized`) para tener una baseline de comparacion durante el monitoreo.

##### 6d: Verificar cambios de parametros

```bash
# Consultar parametros actuales del scope
np-api fetch-api "/parameter?nrn=organization=<org_id>:account=<acc_id>:namespace=<ns_id>:application=<app_id>:scope=<scope_id>"
```

Si hubo cambios de parametros desde el ultimo deploy, informar al usuario cuales son
los parametros que se aplicaran con este deployment.

#### Paso 7: Armar cuestionario interactivo

Usando `AskUserQuestion`:

1. **Scope target**: opciones del paso 2
2. **Build/Release**: opciones del paso 3-4
3. **Asset**: si el scope no tiene `asset_name`, preguntar que asset usar

#### Paso 8: Confirmar con el usuario

Mostrar un resumen amigable para el usuario. NO mostrar detalles tecnicos (POST, JSON, endpoints).

Ejemplo de confirmacion:

> Voy a desplegar la aplicacion **orders-api** con estos datos:
>
> - **Scope**: Production (Kubernetes, publico)
> - **Release**: v0.0.1 (build del commit `75083ad` en branch `main`)
> - **Asset**: docker-image-asset
> - **Dominio**: orders-api-production.org-main.nullapps.io
> - **Tipo**: Deploy inicial (primera vez en este scope)
>
> ¿Confirmas?

Pedir confirmacion explicita.

#### Paso 9: Ejecutar

```bash
action-api.sh exec-api --method POST --data '<json>' "/deployment"
```

**Si retorna error "already a running deployment"**: El scope tiene un deployment previo en status
`running` que debe finalizarse primero. Ver seccion `## Error: "already a running deployment"`
mas abajo para el procedimiento de finalizacion.

#### Paso 10: Monitorear el deployment

**IMPORTANTE**: Despues de crear el deployment, monitorear su progreso.
El deployment pasa por: `creating_approval` → `creating` → `waiting_for_instances` → `running` → (usuario finaliza) → `finalizing` → `finalized`

**CRITICO - NO FINALIZAR AUTOMATICAMENTE**: Cuando el deployment llega a `running` con trafico
al 100%, **NO hacer PATCH a `finalizing`** sin confirmacion explicita del usuario. La finalizacion
**destruye la infraestructura de la version anterior** y elimina la posibilidad de rollback
instantaneo. Nullplatform mantiene ambas versiones corriendo hasta 2 horas, permitiendo rollback
automatico e instantaneo durante ese periodo. Solo finalizar si el usuario explicitamente confirma
que no necesita la ventana de rollback.

```bash
# Verificar estado del deployment (repetir cada 15-30 segundos)
np-api fetch-api "/deployment/<deployment_id>?include_messages=true"
```

#### Paso 10a: Si el deployment queda en `creating_approval`

El status `creating_approval` significa que el deployment esta esperando aprobacion de **policies**.
Las policies pueden auto-aprobar, auto-rechazar, o requerir aprobacion manual.

**IMPORTANTE**: La **aprobacion** en si NO se puede hacer desde este skill — es un proceso
organizacional que pasa por canales externos (Slack, UI de Nullplatform, etc.). Sin embargo,
una vez aprobado, el **inicio del deployment** SI se puede ejecutar desde este skill via
`POST /approval/{id}/execute`.

##### 10a.1: Consultar el estado del approval via API

Usar el NRN del deployment (obtenido de la respuesta del POST /deployment) para buscar el approval:

```bash
# Buscar approval del deployment por NRN (URL-encoded: = → %3D, : → %3A)
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>%3Ascope%3D<scope_id>%3Adeployment%3D<deployment_id>"
```

Del resultado extraer:

- `status`: `pending` | `approved` | `auto_approved` | `auto_denied` | `denied` | `cancelled` | `expired`
- `execution_status`: `pending` | `executing` | `success` | `failed` | `expired`
- `policy_context.policies[]`: Policies evaluadas y si pasaron o no
- `policy_context.action`: `auto` (auto-aprobado/auto-denegado) | `manual` (requiere aprobacion humana)

**Interpretar el resultado:**

| `status` | `execution_status` | Significado | Accion |
|----------|--------------------|--------------| ------|
| `pending` | `pending` | Esperando aprobacion humana | Solicitar aprobacion por canal correspondiente |
| `approved` | `pending` | Aprobado, esperando inicio | Ejecutar `POST /approval/{id}/execute` |
| `approved` | `executing` | Ejecutandose | Esperar |
| `approved` | `success` | Completado | Continuar flujo |
| `approved` | `failed` | Ejecucion fallo | Diagnosticar |
| `approved` | `expired` | Ventana de ejecucion expiro | Informar, puede necesitar recrear |
| `auto_approved` | `*` | Policies pasaron, auto-aprobado | Continuar flujo |
| `auto_denied` | - | Policies rechazaron automaticamente | Mostrar policies que fallaron, sugerir fixes |
| `denied` | - | Rechazado manualmente | Informar |
| `cancelled` | - | Cancelado | Informar |
| `expired` | - | Expiro sin respuesta | Informar, recrear deployment si necesario |

Analizar `policy_context.policies[]` para identificar que policies fallaron (`passed: false`)
y que condiciones no se cumplieron (`evaluations[].result: "not_met"`).

**Opciones segun el estado:**

1. **`auto_denied` o `denied`**: Corregir y recrear con valores que cumplan las policies,
   o escalar a un administrador
2. **`pending`**: Indicar que debe solicitar aprobación por el canal correspondiente
   (Slack, UI de Nullplatform). Si tiene permisos, puede aprobar via:
   ```bash
   action-api.sh exec-api --method POST --data '{"status":"approved"}' "/approval/<approval_id>"
   ```
3. **`approved` + `execution_status: pending`**: El deployment fue aprobado pero necesita
   ser iniciado. Ejecutar via API o desde la UI de Nullplatform
4. **`expired`**: Recrear el deployment si la ventana de aprobacion expiro

##### 10a.2: Mostrar detalle de policies evaluadas

Del `policy_context.policies[]` del approval, mostrar al usuario:

| Policy | Condicion | Resultado |
|--------|-----------|-----------|
| `name` | `conditions` (legible) | passed: true/false |

Esto le permite al usuario entender POR QUE se requirio aprobacion manual.

##### 10a.3: Buscar donde se puede aprobar

Consultar notification channels del account:

```bash
# Listar notification channels del account que manejan approvals
np-api fetch-api "/notification/channel?nrn=organization%3D<org_id>%3Aaccount%3D<account_id>"
```

Filtrar los resultados por `source` que incluya `"approval"`. Estos canales son los que
reciben las notificaciones de aprobacion y determinan donde el usuario puede aprobar.

**Tipos de canales de approval:**

| Tipo | Donde aprobar | Ejemplo |
|------|--------------|---------|
| `slack` | Ir al canal de Slack indicado en `configuration.channels` | El canal configurado tendra un mensaje con botones Approve/Deny |
| `http` | Webhook externo que procesa la aprobacion automaticamente | URL configurada en `configuration.url` |
| `agent` | Un agent evalua y decide automaticamente | El agent usa policies para auto-aprobar o rechazar |

**Informar al usuario:**

1. Listar los canales de approval activos encontrados
2. Indicar el tipo y destino (ej: "Hay un canal Slack `#approvals` donde podes aprobar")
3. Mencionar que tambien se puede aprobar desde la **UI de Nullplatform** (ir a la app → scope → deployment pendiente)

##### 10a.4: Monitorear hasta que se apruebe e inicie

Repetir la consulta del approval cada 15-30 segundos:

```bash
np-api fetch-api "/approval?nrn=<deployment_nrn_encoded>"
```

Cuando el approval pase a `status: approved`:
- Si `execution_status: pending`: Preguntar al usuario si quiere iniciar el deployment. Si confirma, ejecutar `POST /approval/{id}/execute` (ver seccion correspondiente mas abajo)
- Si `execution_status: executed`: Continuar al paso 10b/10c (monitoreo del deployment)

**Resultado esperado del paso 10a**: El usuario sabe el estado del approval, que policies fallaron,
DONDE ir a aprobar, y puede iniciar el deployment via API una vez aprobado.

**Si el deployment es cancelado por policies** (status pasa a `cancelled` desde `creating_approval`):
- Significa que las policies evaluaron y rechazaron automaticamente
- Causas comunes: coverage < umbral requerido, vulnerabilidades criticas en el build
- Informar al usuario y sugerir: corregir el build, o desplegar manualmente desde la UI

#### Paso 10b: Si el deployment falla

Si el status es `failed`:

```bash
# Obtener el instance_id del scope
np-api fetch-api "/scope/<scope_id>"

# Consultar las actions del service
np-api fetch-api "/service/<instance_id>/action?limit=10"

# Para cada action con status=failed, obtener los messages
np-api fetch-api "/service/<instance_id>/action/<action_id>?include_messages=true"
```

**Errores comunes:**

| Sintoma | Causa probable | Diagnostico |
|---------|---------------|-------------|
| Queda en `creating_approval` y luego `cancelled` | Policies rechazan (coverage, vulns) | Revisar build quality, desplegar desde UI |
| Queda en `creating_approval` con `auto_denied` | Policies rechazaron automaticamente | Revisar `policy_context.policies[]` del approval para ver que fallo |
| Approval `expired` | Ventana de aprobacion expiro sin respuesta | Recrear deployment si es necesario |
| Status `failed` sin messages | El agent no proceso la notificacion | Verificar notification channels y agent |
| BackOff events en messages | Container crashea al iniciar | Revisar logs: health check path, puerto, variables de entorno |
| Timeout en `deploying` | Health check no responde | Verificar `initial_delay_seconds`, puerto de la app |
| `finalized` pero app no responde | App arranco pero tiene errores | Revisar logs de aplicacion via telemetry |
| Queda en `pending`/`creating` sin progreso | Entity hook `before` bloqueando | `GET /entity_hook?nrn=<deployment_nrn>&entity_name=deployment` — buscar `status: pending/failed` |
| Traffic switch no avanza | Entity hook `deployment:write` bloqueando | `GET /entity_hook?nrn=<deployment_nrn>&entity_name=deployment` — buscar hooks con `on: write` |

#### Paso 10c: Cuando el deployment llega a `running` (instancias saludables, trafico en 0%)

**CRITICO - EL TRAFICO NO SE MUEVE AUTOMATICAMENTE**: Cuando el deployment llega a status `running`,
las nuevas instancias estan corriendo y saludables, pero tienen **0% de trafico**. La version
anterior sigue sirviendo el 100% del trafico. El trafico **NUNCA** se mueve solo — el agente
**DEBE** moverlo explicitamente con un PATCH al deployment. Sin este paso, la nueva version
queda corriendo pero sin recibir trafico.

Este es el momento de decidir la estrategia de traffic switch.

**Preguntar al usuario con AskUserQuestion:**

- **Opcion 1: "Despliegue gradual con monitoreo (Recomendado)"** - Mover trafico en etapas
  (10% → 50% → 100%) verificando logs, metricas y health check en cada paso. Mas seguro,
  permite detectar problemas antes de comprometer todo el trafico.
- **Opcion 2: "Despliegue rapido al 100%"** - Mover todo el trafico de una vez. Mas rapido,
  pero si hay problemas afectan a todos los usuarios inmediatamente.

##### Opcion 1: Despliegue gradual con monitoreo

Ejecutar el traffic switch en etapas. En cada etapa:

1. **Mover trafico al porcentaje indicado:**

```bash
action-api.sh exec-api --method PATCH --data '{"strategy_data":{"desired_switched_traffic":<porcentaje>}}' "/deployment/<deployment_id>"
```

2. **Esperar ~30 segundos** para que el trafico se estabilice

3. **Verificar health check:**

```bash
WebFetch https://<domain><health_check_path>
```

4. **Revisar logs buscando errores:**

```bash
np-api fetch-api "/telemetry/application/<app_id>/log?scope_id=<scope_id>&limit=50"
```

5. **Informar al usuario** el estado de cada etapa antes de continuar a la siguiente

**Etapas sugeridas:**

| Etapa | Trafico | Verificacion |
|-------|---------|-------------|
| 1 | 10% | Health check + logs. Si hay errores, preguntar si continuar o rollback |
| 2 | 50% | Health check + logs. Buscar incremento en errores o latencia |
| 3 | 100% | Health check + logs. Verificacion final completa |

**Si se detectan problemas en cualquier etapa**, informar al usuario y preguntar:

- **Rollback**: `PATCH` con `{"strategy_data": {"desired_switched_traffic": 0}}`
- **Continuar de todos modos**: Pasar a la siguiente etapa bajo riesgo del usuario

##### Opcion 2: Despliegue rapido al 100%

Mover todo el trafico de una vez:

```bash
action-api.sh exec-api --method PATCH --data '{"strategy_data":{"desired_switched_traffic":100}}' "/deployment/<deployment_id>"
```

Verificar health check y logs una vez completado.

#### Paso 10d: Despues del traffic switch al 100% - Preguntar sobre finalizacion

Una vez que el trafico esta al 100% y el deployment es estable, **la version anterior sigue
corriendo en paralelo**. Esto permite rollback instantaneo.

**Preguntar al usuario con AskUserQuestion:**

- **Opcion 1: "Mantener ventana de rollback (Recomendado)"** - No finalizar. La version anterior
  se mantiene ~2 horas. Si hay problemas, el rollback es instantaneo desde la UI o via API
  (PATCH con `desired_switched_traffic: 0`). Nullplatform finalizara automaticamente cuando expire.
- **Opcion 2: "Finalizar ahora"** - Destruir la version anterior inmediatamente. Solo elegir si
  se tiene total confianza en el deploy. **Esta accion es irreversible.**

Si el usuario elige mantener la ventana de rollback, informar:

1. El deployment queda en status `running` y es completamente funcional
2. La version anterior se limpiara automaticamente en ~2 horas
3. Para rollback: ir a la UI de Nullplatform o hacer PATCH al deployment con
   `{"strategy_data": {"desired_switched_traffic": 0}}`

Si el usuario elige finalizar, proceder con:

```bash
action-api.sh exec-api --method PATCH --data '{"status":"finalizing"}' "/deployment/<deployment_id>"
```

#### Paso 11: Verificacion post-deploy

Cuando el deployment llega a `running` con trafico al 100% (o a `finalized`):

##### 11a: Verificar health check (si scope es publico)

Si el scope tiene `capabilities.visibility.reachability: "public"` y `domain` no es null:

```bash
# Navegar el health check URL para verificar que la app responde
WebFetch https://<domain><health_check_path>
```

Donde `<domain>` viene de `/scope/<scope_id>` y `<health_check_path>` viene de
`capabilities.health_check.path` (tipicamente `/health`).

Si responde OK (ej: `{"status":"ok"}`), informar que la app esta corriendo correctamente.
Si no responde o da error, investigar logs y messages del deployment.

##### 11b: Revisar logs y metricas aplicativas

```bash
# Consultar logs recientes de la aplicacion en el scope
np-api fetch-api "/telemetry/application/<app_id>/log?scope_id=<scope_id>&limit=50"
```

Verificar que no haya errores en los logs post-deploy.

##### 11c: Comparar con deployment anterior

Si en el paso 6c se obtuvieron los messages del deployment anterior, comparar:

- Tiempos de cada fase (creating, waiting_for_instances, finalizing)
- Cantidad y tipo de eventos (probe failures, node scheduling, image pulls)
- Cualquier evento nuevo o inesperado que no aparecia en el deploy anterior

Informar al usuario si hay diferencias significativas.

---

### Prerequisito: asset_name en el scope

**CRITICO**: Antes de crear un deployment, el scope DEBE tener `asset_name` configurado.
Sin `asset_name`, la API retorna el error confuso: `"The scope and the release belongs to different applications"`.

Verificar con `GET /scope/<scope_id>` y si `asset_name` es `null`, hacer PATCH al scope primero.

### Campos requeridos (POST /deployment)

- `scope_id` (number): ID del scope target
- `release_id` (number): ID del release a desplegar

### Campos opcionales

- `application_id` (number): ID de la aplicacion (inferido del scope si no se envia)
- `description` (string): Descripcion del deployment

### Body tipico

```json
{
  "scope_id": "<scope_id>",
  "release_id": "<release_id>"
}
```

### Consultas previas (via /np-api)

- Aplicacion: `np-api fetch-api "/application/<app_id>"`
- Scopes: `np-api fetch-api "/scope?application_id=<app_id>"`
- Builds: `np-api fetch-api "/build?application_id=<app_id>&status=success&sort=created_at:desc&limit=10"`
- Releases: `np-api fetch-api "/release?application_id=<app_id>&build_id=<build_id>"`
- Deployment activo: `np-api fetch-api "/deployment?scope_id=<scope_id>&sort=created_at:desc&limit=1"`

### Respuesta

- `id`: ID del deployment creado
- `status`: `pending` inicialmente
- `scope_id`: ID del scope
- `application_id`: ID de la aplicacion
- `release_id`: ID del release
- `deployment_group_id`: ID del grupo (si aplica)

### Verificar resultado

```bash
# Verificar estado del deployment
np-api fetch-api "/deployment/<deployment_id>?include_messages=true"

# Si fallo, diagnosticar via service actions
np-api fetch-api "/scope/<scope_id>"
# → instance_id
np-api fetch-api "/service/<instance_id>/action?limit=10"
np-api fetch-api "/service/<instance_id>/action/<action_id>?include_messages=true"
```

### Notas

- **`asset_name` en el scope es OBLIGATORIO** para deployments. Sin el, da error confuso. Ver Paso 5
- El deployment usa blue-green: crea nuevas instancias, cambia trafico, y limpia las viejas
- Las actions del service muestran los pasos: `start-blue-green`, `switch-traffic`, `finalize-blue-green`
- `status: finalized` significa que el proceso termino, pero revisar messages por errores
- Si no hay builds exitosos, el usuario necesita triggear un build primero (fuera del scope de este skill)
- Los deployments multi-scope crean un `deployment_group` que agrupa los deployments individuales
- **Policies**: Si hay policies de la org (ej: coverage >= 80%, sin vulnerabilidades criticas), el deployment queda en `creating_approval` y requiere aprobacion manual por un canal externo (Slack, UI)
- **La aprobacion de deployments es un proceso organizacional externo** (Slack, UI), pero el inicio post-aprobacion SI se puede hacer via `POST /approval/{id}/execute`
- Assets tipicos: `docker-image-asset` (K8s, EC2), `lambda-asset` (serverless)
- **Error "already a running deployment"**: Ver seccion de errores de deployment mas abajo

---

## @action POST /release

Crea un release a partir de un build. Un release es necesario para desplegar.

### Flujo obligatorio

1. Obtener el build exitoso que se quiere desplegar (Paso 3 del flujo de deployment)
2. Verificar si ya existe un release para ese build (Paso 4)
3. Si no existe, crear uno con este endpoint

### Campos requeridos

- `build_id` (number): ID del build a partir del cual crear el release
- `application_id` (number): ID de la aplicacion
- `status` (string): **OBLIGATORIO** - Debe ser `"active"`. Sin este campo la API retorna 400 con `"Missing parameter: status"`

### Body tipico

```json
{
  "build_id": "<build_id>",
  "application_id": "<app_id>",
  "status": "active"
}
```

### Ejemplo

```bash
action-api.sh exec-api --method POST --data '{"build_id": 123, "application_id": 456, "status": "active"}' "/release"
```

### Respuesta

- `id`: ID del release creado
- `status`: `active`
- `build_id`: ID del build asociado
- `application_id`: ID de la aplicacion
- `assets`: Lista de assets generados (docker-image-asset, lambda-asset, etc.)

### Errores comunes

| Error | Causa | Solucion |
|-------|-------|----------|
| 400 `Missing parameter: status` | No se envio `"status": "active"` en el body | Agregar `"status": "active"` al body |

---

## @action POST /approval/{id}/execute

Inicia un deployment que ya fue aprobado. Despues de que un approval pasa a `status: approved`,
el deployment NO arranca automaticamente — queda en `execution_status: pending` esperando
que alguien lo inicie explicitamente.

### Cuando usar

Cuando un approval tiene:
- `status`: `approved`
- `execution_status`: `pending`

Esto significa que las policies fueron satisfechas (manual o automaticamente) pero el deployment
aun no comenzo. Se necesita este endpoint para iniciar la ejecucion.

### Flujo obligatorio

1. Consultar el approval del deployment:

```bash
np-api fetch-api "/approval?nrn=organization%3D<org_id>%3Aaccount%3D<acc_id>%3Anamespace%3D<ns_id>%3Aapplication%3D<app_id>%3Ascope%3D<scope_id>%3Adeployment%3D<deployment_id>"
```

2. Verificar que `status` sea `approved` y `execution_status` sea `pending`
3. Obtener el `id` del approval de la respuesta
4. Confirmar con el usuario que quiere iniciar el deployment
5. Ejecutar POST /approval/{id}/execute

### Campos requeridos

No requiere body. Solo el ID del approval en la URL.

### Ejemplo

```bash
action-api.sh exec-api --method POST --data '{}' "/approval/<approval_id>/execute"
```

### Verificar resultado

Despues de ejecutar, consultar el approval nuevamente:

```bash
np-api fetch-api "/approval/<approval_id>"
```

Verificar que `execution_status` cambio a `executed` o `success`.
Luego monitorear el deployment normalmente (Paso 10b/10c del flujo de deployment).

---

## Error: "already a running deployment"

Al intentar crear un nuevo deployment con `POST /deployment`, si el scope ya tiene un deployment
en status `running` (con trafico activo), la API retorna error 400:

```
"already a running deployment"
```

### Causa

El scope tiene un deployment previo que no fue finalizado. Nullplatform solo permite un deployment
activo por scope. Antes de crear uno nuevo, se debe finalizar el anterior.

### Solucion

1. Identificar el deployment en status `running`:

```bash
np-api fetch-api "/deployment?scope_id=<scope_id>&status=running"
```

2. Confirmar con el usuario que desea finalizar el deployment anterior (esto destruye la version
   vieja y elimina la posibilidad de rollback instantaneo)

3. Finalizar el deployment anterior:

```bash
action-api.sh exec-api --method PATCH --data '{"status":"finalizing"}' "/deployment/<old_deployment_id>"
```

4. Esperar a que el deployment anterior llegue a `status: finalized`:

```bash
np-api fetch-api "/deployment/<old_deployment_id>"
```

5. Una vez finalizado, crear el nuevo deployment normalmente con `POST /deployment`

### Nota importante

Si el deployment anterior esta en status `running` con trafico al 100%, finalizarlo es seguro
siempre y cuando la nueva version ya este lista para desplegar. La finalizacion destruye las
instancias de la version vieja, asi que asegurarse de que el usuario entiende que pierde la
posibilidad de rollback instantaneo
