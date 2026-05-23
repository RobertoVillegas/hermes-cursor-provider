# hermes-cursor-provider

Provider de Cursor para Hermes Agent. Permite usar el agente de Cursor via ACP (Agent Client Protocol) como backend de inferencia en Hermes, igual que funciona GitHub Copilot ACP, OpenAI Codex, y los demás providers nativos.

---

## Estado

En desarrollo. Analisis de arquitectura completado. Implementacion en progreso.

## Que es Cursor ACP?

Cursor expone su agente AI via **Agent Client Protocol (ACP)**, un protocolo JSON-RPC 2.0 sobre stdin/stdout. Esto permite que cualquier cliente (IDEs, CLI tools, etc.) se conecten al agente de Cursor.

El flujo basico:

1. Iniciar `cursor --acp --stdio` como subproceso
2. Enviar `initialize` con capabilities del cliente
3. Autenticar via `authenticate` (methodId: `cursor_login`)
4. Crear sesion via `session/new`
5. Enviar prompts via `session/prompt`
6. Recibir respuestas streaming via `session/update` notifications

## Arquitectura del Provider en Hermes

Hermes maneja providers en tres capas:

### 1. Provider Definition (`hermes_cli/providers.py`)

Los providers se definen via `HermesOverlay` con:
- `transport`: `openai_chat` | `anthropic_messages` | `codex_responses` | `external_process`
- `auth_type`: `api_key` | `oauth_external` | `external_process`
- `base_url_override`: URL del endpoint
- `base_url_env_var`: variable de entorno para override
- `extra_env_vars`: variables adicionales

Cursor ACP usa `external_process` como auth type (igual que `copilot-acp`).

### 2. Auth Registry (`hermes_cli/auth.py`)

El `PROVIDER_REGISTRY` define como se autentica cada provider:
- API key: lee de env vars
- OAuth external: flujo de login via navegador
- External process: delega al subprocess (ACP)

Cursor usa `cursor_login` como auth method en el protocolo ACP.

### 3. Runtime Resolution (`hermes_cli/runtime_provider.py`)

Resuelve credentials en tiempo de ejecucion. Para ACP providers, esto devuelve un `base_url` especial (`acp://cursor`) que luego el cliente ACP intercepta.

### 4. ACP Client (`agent/cursor_acp_client.py`)

Este es el corazon del provider. Es un shim OpenAI-compatible que:
- Spawnea `cursor --acp --stdio`
- Convierte mensajes Hermes (OpenAI format) a prompts ACP
- Extrae tool calls del texto de respuesta
- Maneja permisos, filesystem reads/writes
- Devuelve el resultado en formato OpenAI que Hermes espera

## Files a modificar en Hermes (para PR)

| File | Cambio |
|------|--------|
| `hermes_cli/providers.py` | Agregar overlay `cursor-acp` en `HERMES_OVERLAYS` y alias |
| `hermes_cli/auth.py` | Agregar `cursor-acp` a `PROVIDER_REGISTRY` con `auth_type="external_process"` |
| `hermes_cli/runtime_provider.py` | Agregar resolucion de runtime para `cursor-acp` |
| `agent/cursor_acp_client.py` | **Nuevo archivo**: Cliente ACP para Cursor |
| `agent/chat_completion_helpers.py` | Registrar `CursorACPClient` como factory para `acp://cursor` |
| `hermes_cli/models.py` | Agregar modelos disponibles de Cursor |
| `hermes_cli/config.py` | Agregar env vars default (`CURSOR_ACP_COMMAND`, etc.) |

## Comparativa: Copilot ACP vs Cursor ACP

| Aspecto | Copilot ACP | Cursor ACP |
|---------|------------|------------|
| Comando | `copilot --acp --stdio` | `cursor --acp --stdio` |
| Auth | GitHub OAuth | Cursor OAuth (`cursor_login`) |
| Base URL marker | `acp://copilot` | `acp://cursor` |
| Tool calls | `<tool_call>{...}</tool_call>` | Similar (TBD) |
| Extension methods | `fs/read_text_file`, `fs/write_text_file` | Igual + `cursor/ask_question`, `cursor/create_plan`, etc. |
| Subagentes | No | Si (`cursor/task`) |

## Cursor Extension Methods (del protocolo)

Metodos adicionales que Cursor expone sobre ACP estandar:

- `cursor/ask_question` - Preguntar al usuario
- `cursor/create_plan` - Crear plan de trabajo
- `cursor/update_todos` - Actualizar lista de tareas
- `cursor/task` - Ejecutar subagente
- `cursor/generate_image` - Generar imagenes

## Implementacion

Ver [`cursor_acp_client.py`](cursor_acp_client.py) para el shim OpenAI-compatible.

Ver [`IMPLEMENTATION.md`](IMPLEMENTATION.md) para el plan de implementacion detallado paso a paso.

## Instalacion Cursor CLI

Para usar este provider necesitas el Cursor CLI instalado:

```bash
# Via npm (cuando este disponible)
npm install -g @cursor/agent

# O descargar desde cursor.com/downloads
```

El comando debe estar en PATH como `cursor` o configurar:
```bash
export CURSOR_ACP_COMMAND=/path/to/cursor
```

## Uso en Hermes

```bash
# Configurar provider
hermes model
# -> Seleccionar "Cursor ACP"

# O manualmente en config.yaml
hermes config set model.provider cursor-acp
hermes config set model.default "cursor-default"

# Chat
hermes chat
```

## License

MIT
