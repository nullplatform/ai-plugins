---
name: np-agent-local-setup
description: This skill should be used when the user asks to "run agent locally", "setup local agent", "install np-agent", "test service locally", "start local agent", "configure local testing environment", or needs to set up a nullplatform controlplane agent on their machine for local development and testing of services or scopes.
---

# np-agent-local-setup

Setup y ejecucion del agente de nullplatform en modo local para desarrollo y testing iterativo de services y scopes.

## Objetivo

El resultado de este skill es **un agente corriendo localmente y verificado** — conectado a la plataforma, respondiendo pings, y listo para recibir notificaciones de services/scopes.

## Cuando Usar

- Antes de testear un service o scope nuevo localmente
- Cuando se necesita un ambiente de testing iterativo (edit script -> trigger -> ver logs -> fix -> retry)
- Como prerequisito de `/np-service-craft test`, `/np-scope-craft`, o cualquier flujo que necesite ejecucion local del agente

## Critical Rules

1. **NUNCA correr el agente en Docker para testing local** — correrlo directo en el host
2. **El agente DEBE estar corriendo ANTES de crear entidades** (scopes, services, deployments) — si no esta corriendo, las notificaciones no llegan
3. **NUNCA loguear el API Key en texto plano** — usar `$NP_API_KEY` en logs y documentacion
4. **Confirmar con el usuario antes de arrancar el agente** — mostrar el comando completo

## Workflow Operativo

Claude DEBE ejecutar cada paso, no solo documentarlos. El workflow termina cuando el agente esta corriendo y verificado.

### Paso 0: Verificar instalacion

Ejecutar:

```bash
which np-agent && np-agent version
```

Si no esta instalado, pedir confirmacion e instalar con:

```bash
curl https://cli.nullplatform.com/agent/install.sh | bash
```

Se instala en `~/.local/bin/np-agent`. Verificar que `~/.local/bin` esta en el PATH.

### Paso 1: API Key

Verificar si ya esta seteado:

```bash
echo "NP_API_KEY: ${NP_API_KEY:-(not set)}"
```

Si no esta seteado, pedirle al usuario que:

1. **Cree el API Key en la UI**: Ir a nullplatform UI → Settings → API Keys → Create
2. **Lo pegue en el chat** o lo exporte en su terminal

El formato del key es `base64.base64` (dos segmentos separados por punto).

### Paso 2: Preparar el repo en ~/.np/

El agente busca scripts en `~/.np/` (basepath por defecto). Derivar org y repo del contexto del proyecto (remote git, nombre del directorio, o preguntarle al usuario). Crear el symlink:

```bash
mkdir -p ~/.np/<org>
ln -sf $(pwd) ~/.np/<org>/<repo-name>
```

Si el symlink ya existe y apunta al directorio correcto, no recrearlo. Verificar:

```bash
ls -la ~/.np/<org>/<repo-name>/
```

**Alternativas** (preguntar si el symlink no aplica):

- `-command-executor-command-folders /path/to/parent/folder` — agrega paths de busqueda sin symlinks
- `-command-executor-git-command-repos "https://TOKEN@github.com/org/repo.git#main"` — clone automatico (para CI, no dev)

### Paso 3: Verificar que el puerto 8080 este libre

```bash
lsof -i :8080
```

Si el puerto esta ocupado, informar al usuario y pedirle que lo libere antes de continuar.

### Paso 4: Crear script de arranque

Verificar si `scripts/start-agent.sh` ya existe en el repo. Si existe, no recrearlo (puede tener customizaciones del usuario). Si no existe, crearlo con permisos de ejecucion. El script debe:

- Validar que `NP_API_KEY` este seteado (exit 1 si no)
- Arrancar np-agent con los flags correctos
- Redirigir output a `/tmp/np-agent.log` con `tee`

```bash
#!/bin/bash
set -euo pipefail

if [ -z "${NP_API_KEY:-}" ]; then
  echo "ERROR: NP_API_KEY no esta seteado. Exportalo primero:"
  echo "  export NP_API_KEY=\"tu-api-key\""
  exit 1
fi

np-agent \
  -api-key "$NP_API_KEY" \
  -runtime host \
  -tags "environment:development" \
  -command-executor-env "NP_API_KEY=\"$NP_API_KEY\"" \
  -command-executor-debug \
  -webserver-enabled \
  -log-level DEBUG \
  -log-pretty-print \
  2>&1 | tee /tmp/np-agent.log
```

Hacerlo ejecutable: `chmod +x scripts/start-agent.sh`

Para scopes, agregar estos flags adicionales al script:

```bash
-tags "environment:development,cluster:local"
-command-executor-command-folders /path/to/parent/of/scope
```

### Paso 5: Indicar al usuario que arranque el agente

El agente es un proceso daemon que corre en loop (WebSocket + heartbeat). **NO se puede correr en background desde Claude** porque el shell del task termina y mata el proceso.

Indicarle al usuario que abra **otra terminal** y ejecute:

```bash
export NP_API_KEY="<su-api-key>"
./scripts/start-agent.sh
```

Decirle explicitamente: "Ejecuta esto en otra terminal para que no bloquee esta sesion. Cuando veas `Successfully connected to command executor` en los logs, avisame."

Esperar a que el usuario confirme que arranco antes de continuar.

### Paso 6: Verificar conexion

Leer los logs y verificar que el agente esta conectado:

```bash
tail -20 /tmp/np-agent.log
```

Debe mostrar:

```
INFO  Agent registered 200 OK
INFO  Agent id: <uuid>
INFO  Successfully connected to command executor
DEBUG Command <id> [ping] executed with response: map[pong:true status:ok ...]
```

Si los pings responden OK, el agente esta listo. Informar al usuario:
- Agent ID
- Organization ID
- Tags registrados
- Que el agente esta listo para recibir notificaciones

### Post-setup: Ciclo de testing iterativo

Una vez que el agente esta corriendo, el ciclo de desarrollo es:

```
1. Editar script/workflow
2. Trigger accion (crear service, crear scope, o resend notification)
3. Ver logs del agente: tail -f /tmp/np-agent.log
4. Si falla: fix -> resend notification (sin recrear el recurso)
5. Repetir hasta que funcione
```

Para reenviar una notificacion sin recrear el recurso:

```
/np-notification-manager resend <notification-id>
```

Para encontrar el notification ID:

```
/np-api fetch-api "/notification?nrn=<nrn>&per_page=5"
```

## Flags Reference

| Flag | Default | Uso |
|------|---------|-----|
| `-api-key` | `$NP_API_KEY` | Autenticacion (obligatorio) |
| `-runtime` | - | `host` para local (obligatorio) |
| `-tags` | - | Tags para matching con notification channels (`k:v,k2:v2`) |
| `-command-executor-basepath` | `~/.np` | Donde busca scripts |
| `-command-executor-command-folders` | - | Folders adicionales de busqueda |
| `-command-executor-debug` | `false` | Imprime stdout de scripts ejecutados |
| `-command-executor-env` | - | Env vars inyectadas a scripts (`K=V,K2=V2`) |
| `-command-executor-git-command-repos` | - | Repos a clonar en basepath |
| `-command-executor-disable-known-commands-validate` | `false` | Desactiva validacion de paths (bypass seguridad) |
| `-log-level` | `ERROR` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `-log-pretty-print` | `false` | Logs con colores |
| `-webserver-enabled` | `false` | Habilita health check HTTP en :8080 |
| `-heartbeat-interval` | `60` | Segundos entre heartbeats |

**Nota**: `np-agent` usa flags estilo Go con **single dash** (`-api-key`), no double dash (`--api-key`). Ambos funcionan pero el estilo canonico es single dash.

## Gotcha: El agente hereda env vars del shell

El agente pasa **todas** las variables de entorno del shell donde se inicio a los scripts que ejecuta. Si tu shell tiene `AWS_PROFILE=algo`, los scripts lo van a usar aunque `values.yaml` tenga otro profile configurado.

Los scripts (`build_context`) deben overridear explicitamente las variables del cloud provider cuando `values.yaml` tiene un valor. El patron correcto es:

```bash
# values.yaml siempre gana (sin check de -z)
if [ -n "$PROFILE_FROM_VALUES" ]; then
  export AWS_PROFILE="$PROFILE_FROM_VALUES"
fi
```

Si un script falla con "profile not found", verificar que env var hereda el agente con `env | grep AWS` en el shell donde corre.

## Variables de Entorno

| Variable | Quien la usa | Descripcion |
|----------|-------------|-------------|
| `NP_API_KEY` | np-agent | Autenticacion del agente con la plataforma |
| `NULLPLATFORM_API_KEY` | np CLI | El CLI `np` espera esta variable, NO `NP_API_KEY` |
| `NP_ACTION_CONTEXT` | Notification payload | JSON con el contexto de la accion (seteado por la plataforma) |

**Bridge critico**: El agente pasa `NP_API_KEY` pero el CLI `np` espera `NULLPLATFORM_API_KEY`. El entrypoint del service/scope debe hacer el bridge:

```bash
if [ -n "${NP_API_KEY:-}" ] && [ -z "${NULLPLATFORM_API_KEY:-}" ]; then
  export NULLPLATFORM_API_KEY="$NP_API_KEY"
fi
```

## Path Resolution

El agente resuelve comandos asi:

```
cmdline recibido: "org/repo/services/my-svc/entrypoint/entrypoint"
resolucion:       basepath + cmdline = ~/.np/org/repo/services/my-svc/entrypoint/entrypoint
```

Si el archivo no se encuentra en ninguno de los basepaths + command-folders, el agente devuelve: `"command not found in any allowed paths"`.

Verificar que el path existe:

```bash
ls -la ~/.np/<org>/<repo>/services/<service>/entrypoint/entrypoint
```

Y que tiene permisos de ejecucion:

```bash
chmod +x ~/.np/<org>/<repo>/services/<service>/entrypoint/entrypoint
```

Symlinks son validos pero el target debe resolver dentro de los basepaths.

## Troubleshooting

| Problema | Causa | Solucion |
|----------|-------|----------|
| FATAL "bind: address already in use" | Puerto 8080 ocupado por otra instancia | Pedir al usuario que libere el puerto |
| Agent imprime help y sale | Falta `-runtime host` | Agregar el flag |
| "Malformed API key" | Key no tiene formato `base64.base64` | Verificar el key en la UI |
| "command not found in any allowed paths" | Script no esta en basepath | Verificar symlink/clone en `~/.np/` |
| "symlink points outside allowed paths" | Target del symlink fuera de basepaths | Agregar folder con `-command-executor-command-folders` |
| Notification llega pero script no corre | Tags del agente no matchean el channel selector | Comparar `-tags` del agente con el selector del channel |
| "please login first" | `NULLPLATFORM_API_KEY` no seteada | Agregar bridge NP_API_KEY -> NULLPLATFORM_API_KEY en entrypoint |
| Entrypoint falla silenciosamente (exit 1, sin output) | `SERVICE_PATH` relativo no resuelve | Resolver path absoluto en el entrypoint (ver np-service-craft docs/troubleshooting.md) |
| WebSocket se desconecta | Red, token expirado | El agente reconecta automaticamente (backoff 1s-20s) |
| Heartbeat 404 | Server evicto al agente | El agente se re-registra automaticamente |
| Credentials cloud error al ejecutar tofu | No hay sesion activa del cloud provider | `aws sso login --profile <name>` o `az login` antes de arrancar el agente |

## Detener el agente

```bash
# Si corre en foreground: Ctrl+C
# Si corre en background:
kill $(pgrep np-agent)
```

El agente hace cleanup al recibir SIGINT/SIGTERM: se marca como inactive en la API.
