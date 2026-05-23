# hermes-cursor-provider

Provider de Cursor para Hermes Agent. Permite usar el agente de Cursor via ACP (Agent Client Protocol) como backend de inferencia en Hermes, igual que funciona GitHub Copilot ACP, OpenAI Codex, y los demas providers nativos.

**Repo:** https://github.com/RobertoVillegas/hermes-cursor-provider

---

## Estado

✅ **FUNCIONANDO** — Probado con `agent login` + suscripcion Individual de Cursor. Composer 2.5 responde correctamente via ACP.

| Feature | Estado |
|---------|--------|
| Autenticacion `agent login` | ✅ Funciona |
| Crear sesion ACP | ✅ Funciona |
| Enviar prompts | ✅ Funciona |
| Streaming de respuestas | ✅ Funciona |
| Composer 2.5 | ✅ Disponible (configurable en tu cuenta de Cursor) |

**Nota:** El modelo que usa ACP depende de tu configuracion de cuenta de Cursor. Puedes cambiarlo desde la app de Cursor o el CLI interactivo (`agent` → `/model`). El ACP usa el modelo que tengas seleccionado como default.

## Que es Cursor ACP?

Cursor expone su agente AI via **Agent Client Protocol (ACP)**, un protocolo JSON-RPC 2.0 sobre stdin/stdout a traves del CLI `agent acp`.

El flujo basico:

1. Pre-autenticar: `agent login` (browser) o `export CURSOR_API_KEY=...`
2. Iniciar `agent acp` como subproceso
3. Enviar `initialize` con capabilities del cliente
4. Autenticar via `authenticate` (methodId: `cursor_login`)
5. Crear sesion via `session/new`
6. Enviar prompts via `session/prompt`
7. Recibir respuestas streaming via `session/update` notifications
8. Responder permisos via `session/request_permission` (allow-once / allow-always / reject-once)

## Composer 2.5 y seleccion de modelo (IMPORTANTE: requiere suscripcion Individual/Pro)

**Este provider solo funciona con suscripcion Individual ($20/mes) o superior de Cursor.** No requiere API key. Usa `agent login` (browser auth) que viene con tu suscripcion.

Segun [Lee Robinson](https://x.com/leerob/status/2057170644681277470), Cursor **no ofrece acceso API directo** a Composer 2.5. La unica forma de usarlo es via ACP con `agent login` (autenticacion browser/suscripcion).

| Metodo de auth | Modelos disponibles | Requiere | Funciona con este provider? |
|---------------|-------------------|----------|---------------------------|
| `agent login` (browser) | **Todos incluyendo Composer 2.5** | Suscripcion Individual ($20) o superior | **Si** |
| `CURSOR_API_KEY` | Modelos basicos / API access | API key del dashboard (no disponible en Individual) | No |

**Nota:** Si tienes API key, el [PR #30641](https://github.com/NousResearch/hermes-agent/pull/30641) de Hermes ofrece integracion via Cursor SDK Python. Este repo es especificamente para quienes tienen suscripcion Individual/Pro **sin** API key y necesitan ACP.

### Seleccionar Composer 2.5

El modelo que usa ACP lo controla tu cuenta de Cursor, no Hermes. Para cambiarlo:

1. Abre la app de Cursor o corre `agent` en modo interactivo
2. Cambia el modelo a Composer 2.5 (sin fast si prefieres)
3. El ACP automaticamente usara ese modelo como default

**No uses `CURSOR_ACP_MODEL`** para forzar el modelo. El ACP CLI de Individual/Pro solo expone `composer-2.5[fast=true]` en su catalogo interno, pero el modelo real depende de tu configuracion de cuenta.

Si necesitas confirmar que modelo esta usando, simplemente pregunta en el chat:
```
What model are you currently running?
```

## Diferencia con hermes-cursor-harness

| | Este repo (cursor-acp) | hermes-cursor-harness |
|---|---|---|
| Fecha | Mayo 2026 | **Mayo 1** (antes de Composer 2.5) |
| Enfoque | ACP ligero (subprocess stdio) | SDK + ACP + stream-json |
| Composer 2.5 | **Si** (via ACP + suscripcion) | No (solo `cursor/composer-2`) |
| Dependencias | Solo `@cursor/agent` | `@cursor/sdk` + Node + mucho mas |
| Tamaño | ~700 LOC | 10x mas grande |

Para usar Composer 2.5 con suscripcion Individual, **este repo es la opcion recomendada** porque el harness no fue actualizado para la nueva version.

## Estrategia de integracion: Plugin + Core PR

Hermes tiene dos niveles de providers:

### Nivel 1: Plugin Profile (declarativo)

Se puede instalar como **drop-in plugin** en `~/.hermes/plugins/model-providers/cursor-acp/` o como paquete pip. Solo declara metadata.

### Nivel 2: ACP Client (ejecucion)

Requiere **PR al core de Hermes** porque el cliente ACP debe vivir en `agent/` y ser importado por `agent_runtime_helpers.py`.

| Nivel | Archivos | Puede ser plugin standalone? |
|-------|----------|------------------------------|
| 1 | `plugins/model-providers/cursor-acp/__init__.py`, `plugin.yaml` | Si |
| 2 | `agent/cursor_acp_client.py`, patches del core | **No** |

Ver [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS.md) para el analisis completo.

## Archivos del repo

| Archivo | Proposito |
|---------|-----------|
| `README.md` | Este archivo |
| `ARCHITECTURE_ANALYSIS.md` | Analisis profundo del sistema de providers en Hermes |
| `IMPLEMENTATION.md` | Plan de implementacion paso a paso |
| `cursor_acp_client.py` | Cliente ACP completo (shim OpenAI-compatible) |
| `plugins/model-providers/cursor-acp/` | Plugin profile declarativo |
| `patches/` | 13 archivos patch para los cambios en el core de Hermes y WebUI |
| `CONTRIBUTING.md` | Guia para crear el PR al repo oficial |
| `pyproject.toml` | Config del paquete pip |
| `hermes_cursor_provider/` | Paquete pip-installable |

## Instalacion rapida (todo automatico)

El script `install.sh` aplica todos los patches, copia el cliente ACP e instala el plugin profile:

```bash
git clone https://github.com/RobertoVillegas/hermes-cursor-provider.git
cd hermes-cursor-provider
./install.sh
```

El script detecta automaticamente `~/.hermes/hermes-agent` y `~/.hermes/hermes-webui`. Si usas rutas custom, exporta:

```bash
export HERMES_AGENT_DIR=/ruta/a/hermes-agent
export HERMES_WEBUI_DIR=/ruta/a/hermes-webui
./install.sh
```

Luego reinicia el WebUI (si lo usas) y refresca tu navegador.

---

## Instalacion manual (paso a paso)

Si prefieres control total, sigue estos pasos:

### 1. Instalar Cursor CLI

```bash
# macOS / Linux / WSL
curl https://cursor.com/install -fsS | bash

# Verificar
agent --version   # Debe mostrar algo como: 2026.05.20-2b5dd59

# Autenticar con tu suscripcion (abre browser)
agent login
```

**Requisito:** Suscripcion Individual ($20/mes) o superior de Cursor. No necesitas API key.

El binario se instala como `agent` en `~/.local/bin/agent` (asegurate de que `~/.local/bin` este en tu PATH).

### 2. Aplicar los patches al core de Hermes

```bash
# Desde el repo clonado
cd hermes-cursor-provider

# Aplica los 13 patches
git -C ~/.hermes/hermes-agent apply patches/001-hermes_cli-providers.patch
git -C ~/.hermes/hermes-agent apply patches/002-hermes_cli-auth.patch
git -C ~/.hermes/hermes-agent apply patches/003-hermes_cli-runtime_provider.patch
git -C ~/.hermes/hermes-agent apply patches/004-agent-agent_runtime_helpers.patch
git -C ~/.hermes/hermes-agent apply patches/005-hermes_cli-models.patch
git -C ~/.hermes/hermes-agent apply patches/006-agent-conversation_loop.patch
git -C ~/.hermes/hermes-agent apply patches/007-agent-agent_init.patch
git -C ~/.hermes/hermes-agent apply patches/008-agent-auxiliary_client.patch
git -C ~/.hermes/hermes-agent apply patches/009-agent-model_metadata.patch
git -C ~/.hermes/hermes-agent apply patches/010-hermes_cli-auth-fix.patch
git -C ~/.hermes/hermes-agent apply patches/011-hermes_cli-auth-status.patch
git -C ~/.hermes/hermes-agent apply patches/012-hermes_cli-model_switch.patch
git -C ~/.hermes/hermes-webui apply patches/013-hermes-webui-config.patch
```

### 3. Copiar el cliente ACP

```bash
cp cursor_acp_client.py ~/.hermes/hermes-agent/agent/cursor_acp_client.py
```

### 4. Instalar el plugin profile

```bash
mkdir -p ~/.hermes/plugins/model-providers/cursor-acp
cp -r plugins/model-providers/cursor-acp/* ~/.hermes/plugins/model-providers/cursor-acp/
```

### 5. Limpiar caches y reiniciar

```bash
# Python caches
find ~/.hermes/hermes-agent -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
find ~/.hermes/hermes-webui -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null

# WebUI model cache
rm -f ~/.hermes/webui/models_cache.json

# Reiniciar WebUI (si lo usas)
kill $(lsof -t -i:8787) 2>/dev/null; sleep 2
cd ~/.hermes/hermes-webui
~/.hermes/hermes-agent/venv/bin/python server.py &
```

### 6. Usar

```bash
hermes chat
/model
# Seleccionar "Cursor ACP"
```

En el WebUI, simplemente refresca tu navegador despues del reinicio.

---

| # | Archivo | Que arregla |
|---|---------|------------|
| 001-003 | `agent_runtime_helpers.py`, `agent_init.py` | Registro del provider y discovery |
| 004 | `providers.yaml` | Metadata del provider en el registro |
| 005 | `hermes_cli/auth.py` | Resolucion de credenciales external_process |
| 006 | `agent/conversation_loop.py` | Desactivar streaming para cursor-acp |
| 007 | `agent/agent_init.py` | api_mode y pasar acp_command/acp_args |
| 008 | `agent/auxiliary_client.py` | Soporte en tareas auxiliares |
| 009 | `agent/model_metadata.py` | Prefijos y contexto de modelo |
| 010 | `agent/conversation_loop.py` | Paridad con copilot-acp en streaming |
| 011 | `hermes_cli/auth.py` | Auth status generico para external_process |
| 012 | `hermes_cli/model_switch.py` | Deteccion en `/model` picker del CLI |
| 013 | `hermes-webui/api/config.py` | `_PROVIDER_MODELS` y `_PROVIDER_DISPLAY` del WebUI |

## Como contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para los pasos detallados para crear un PR al repo oficial de Hermes.

## Documentacion oficial de Hermes

- [Model Provider Plugins](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)
- [Adding Providers](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)
- [Provider Runtime](https://hermes-agent.nousresearch.com/docs/developer-guide/provider-runtime)

## Documentacion oficial de Cursor

- [Cursor ACP](https://cursor.com/docs/cli/acp)
- [Cursor Authentication](https://cursor.com/docs/cli/reference/authentication)

## License

MIT
