# Plan de Implementacion: Cursor ACP Provider para Hermes

Basado en:
- Codigo fuente de Hermes Agent (v0.14.0+)
- [Adding Providers docs](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)
- [Model Provider Plugins docs](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)

---

## Resumen

Implementar un provider ACP para Cursor en Hermes Agent, comparable en calidad y patrones a los providers existentes (`copilot-acp`, `openai-codex`, `github-copilot`).

**Tipo de provider:** Native / non-OpenAI (Path B en la terminologia de Hermes). Usa JSON-RPC 2.0 sobre stdin/stdout via subprocess.

---

## Pre-requisitos

1. Cursor CLI instalado localmente (`agent acp` funciona)
2. Sesion de Cursor autenticada (`agent login`)
3. Hermes Agent instalado desde source para desarrollo

---

## Fase 1: Scaffold y ACP Client (agent/cursor_acp_client.py)

Crear el cliente ACP para Cursor, basado en `agent/copilot_acp_client.py`.

### 1.1 Estructura base

```python
"""OpenAI-compatible shim que forward requests a `agent acp`."""
```

### 1.2 Diferencias clave vs Copilot ACP

| Item | Copilot | Cursor |
|------|---------|--------|
| Comando default | `copilot` | `agent` |
| Args default | `--acp --stdio` | `acp` (o `--model <m> acp`) |
| Env var comando | `HERMES_COPILOT_ACP_COMMAND` | `CURSOR_ACP_COMMAND` |
| Env var args | `HERMES_COPILOT_ACP_ARGS` | `CURSOR_ACP_ARGS` |
| Auth method ID | (none - usa GitHub token) | `cursor_login` |
| Pre-auth | `gh auth login` | `agent login` o `CURSOR_API_KEY` |
| Base URL marker | `acp://copilot` | `acp://cursor` |

### 1.3 Flujo JSON-RPC

El cliente debe implementar:

1. **initialize**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "initialize",
     "params": {
       "protocolVersion": 1,
       "clientCapabilities": {
         "fs": { "readTextFile": true, "writeTextFile": true },
         "terminal": false
       },
       "clientInfo": { "name": "hermes-agent", "version": "0.0.0" }
     }
   }
   ```

2. **authenticate** (Cursor requiere esto)
   ```json
   {
     "jsonrpc": "2.0",
     "id": 2,
     "method": "authenticate",
     "params": { "methodId": "cursor_login" }
   }
   ```

3. **session/new**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 3,
     "method": "session/new",
     "params": {
       "cwd": "/path/to/project",
       "mcpServers": []
     }
   }
   ```

4. **session/prompt**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 4,
     "method": "session/prompt",
     "params": {
       "sessionId": "...",
       "prompt": [{ "type": "text", "text": "..." }]
     }
   }
   ```

5. **session/update** (notificacion server -> client)
   - `agent_message_chunk` - chunks de respuesta
   - `agent_thought_chunk` - razonamiento

6. **session/request_permission** (server solicita permiso)
   - Responder con `allow-once` o `cancelled`

### 1.4 Mapeo de mensajes Hermes -> ACP

Hermes usa formato OpenAI (`messages` array con `role`/`content`). El ACP client debe:

1. Convertir el array de mensajes a un solo prompt de texto
2. Preservar el contexto de system prompt
3. Marcar tool calls como `<tool_call>{...}</tool_call>` (mismo formato que Copilot)

### 1.5 Extraccion de tool calls

Igual que Copilot ACP:
- Buscar bloques `<tool_call>{...}</tool_call>`
- Parsear JSON interno con `id`, `type`, `function` (name, arguments)
- Devolver como `SimpleNamespace` objects compatibles con OpenAI

---

## Fase 2: Provider Profile (plugin declarativo)

### 2.1 Plugin directory

```
plugins/model-providers/cursor-acp/
  __init__.py    # ProviderProfile + register_provider()
  plugin.yaml    # Manifest
```

### 2.2 Profile definition

```python
from providers import register_provider
from providers.base import ProviderProfile

cursor_acp = ProviderProfile(
    name="cursor-acp",
    aliases=("cursor", "cursor-agent"),
    api_mode="chat_completions",
    env_vars=(),
    base_url="acp://cursor",
    auth_type="external_process",
    display_name="Cursor ACP",
    description="Cursor Agent via Agent Client Protocol (ACP) subprocess",
    signup_url="https://cursor.com",
)
register_provider(cursor_acp)
```

---

## Fase 3: Auth Registry

### 3.1 hermes_cli/auth.py

Agregar a `PROVIDER_REGISTRY`:

```python
"cursor-acp": ProviderConfig(
    id="cursor-acp",
    name="Cursor ACP",
    auth_type="external_process",
    inference_base_url="acp://cursor",
    base_url_env_var="CURSOR_ACP_BASE_URL",
),
```

---

## Fase 4: Provider Overlay

### 4.1 hermes_cli/providers.py

Agregar a `HERMES_OVERLAYS`:

```python
"cursor-acp": HermesOverlay(
    transport="codex_responses",
    auth_type="external_process",
    base_url_override="acp://cursor",
    base_url_env_var="CURSOR_ACP_BASE_URL",
),
```

Agregar alias:
```python
"cursor": "cursor-acp",
"cursor-agent": "cursor-acp",
```

Agregar label:
```python
"cursor-acp": "Cursor ACP",
```

---

## Fase 5: Runtime Resolution

### 5.1 hermes_cli/runtime_provider.py

En `resolve_runtime_credentials()`, agregar branch para `cursor-acp`:

```python
if provider == "cursor-acp":
    creds = resolve_external_process_provider_credentials(provider)
    return {
        "provider": "cursor-acp",
        "api_mode": "chat_completions",
        "base_url": creds.get("base_url", "").rstrip("/") or "acp://cursor",
        "api_key": creds.get("api_key", ""),
    }
```

---

## Fase 6: Client Instantiation

### 6.1 agent/agent_runtime_helpers.py

En `create_openai_client()` o similar, agregar branch para URLs que empiecen con `acp://cursor`:

```python
if agent.provider == "cursor-acp" or str(client_kwargs.get("base_url", "")).startswith("acp://cursor"):
    from agent.cursor_acp_client import CursorACPClient
    client = CursorACPClient(**client_kwargs)
    _ra().logger.info(
        "Cursor ACP client created (%s, shared=%s) %s",
        reason, shared, agent._client_log_context(),
    )
    return client
```

---

## Fase 7: Modelos

### 7.1 hermes_cli/models.py

Definir modelos disponibles de Cursor. Para Composer 2.5 (requiere suscripcion Individual $20+):

```python
CURSOR_MODELS = [
    "cursor/composer-2.5",    # Composer 2.5 (Individual+)
    "cursor/composer-2",      # Composer 2 (legacy)
    "cursor/default",         # Default de la cuenta
    "cursor/auto",            # Auto-seleccion
]
```

### 7.2 Model selection en ACP

ACP no tiene parametro de modelo en el protocolo JSON-RPC. La seleccion se hace via flag `--model` del CLI:

```python
# agent --model <modelo> acp
args = ["--model", "composer-2.5", "acp"]
```

En el cliente ACP, esto se controla via:
- `CURSOR_ACP_MODEL` env var
- `acp_model` parametro en constructor
- Si no se especifica, usa el default de la cuenta de Cursor

### 7.3 Mapeo de modelos

```python
CURSOR_MODEL_ALIASES = {
    "cursor/composer-2.5": "composer-2.5",
    "cursor/composer-2": "composer-2",
    "cursor/default": None,  # None = no pasar --model
    "cursor/auto": None,
}
```

---

## Fase 8: CLI Wiring

### 8.1 hermes_cli/main.py

Agregar `cursor-acp` a:
- `provider_labels` dict
- Lista de providers en `select_provider_and_model()`
- `--provider` argument choices

Nota: `hermes_cli/setup.py` no necesita cambios porque delega a `main.py`.

---

## Fase 9: Aux Model

### 9.1 agent/auxiliary_client.py

Agregar default aux model si es relevante (probablemente no lo es para ACP ya que todo va al subprocess).

---

## Fase 10: Tests

### 10.1 Tests unitarios

- Mock del subprocess `cursor`
- Verificar formato JSON-RPC correcto
- Verificar extraccion de tool calls
- Verificar manejo de permisos

### 10.2 Tests de integracion

- `hermes chat --provider cursor-acp --model cursor/composer-2.5`
- Verificar que se inicia el subprocess
- Verificar que se autentica
- Verificar que responde correctamente

### 10.3 Tests de wiring

Segun la [documentacion oficial](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers):

```bash
pytest tests/test_runtime_provider_resolution.py -k cursor -n0 -q
pytest tests/test_cli_provider_resolution.py -k cursor -n0 -q
pytest tests/test_cli_model_command.py -k cursor -n0 -q
pytest tests/test_setup_model_selection.py -k cursor -n0 -q
```

---

## Fase 11: Live Verification

```bash
# Smoke test
python -m hermes_cli.main chat -q "Say hello" --provider cursor-acp --model cursor/composer-2.5

# Interactive flows
python -m hermes_cli.main model
python -m hermes_cli.main setup

# Tool call test
python -m hermes_cli.main chat -q "Lee el archivo README.md"
```

---

## Fase 12: Documentacion

### 12.1 Docs de Hermes

Agregar a `website/docs/integrations/providers.md`:
- Setup del provider
- Instalacion de Cursor CLI
- Autenticacion
- Troubleshooting

### 12.2 Otros docs

- `website/docs/getting-started/quickstart.md`
- `website/docs/user-guide/configuration.md`
- `website/docs/reference/environment-variables.md`

---

## Diagrama de flujo

```
Usuario -> hermes chat
  -> HermesCLI
    -> runtime_provider.resolve_runtime_credentials("cursor-acp")
      -> Devuelve base_url="acp://cursor"
    -> chat_completion_helpers.create_openai_client(base_url="acp://cursor")
      -> CursorACPClient (shim OpenAI-compatible)
        -> subprocess.Popen(["agent", "acp"])
          -> initialize -> authenticate -> session/new -> session/prompt
          <- session/update notifications (streaming)
        <- Response text
      <- OpenAI-format response
    <- Final answer
```

---

## Referencias

- [Cursor ACP Docs](https://cursor.com/docs/cli/acp)
- [Hermes Provider Docs](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [Lee Robinson Tweet](https://x.com/leerob/status/2057170644681277470?s=20)
- [Hermes: Adding Providers](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)
- [Hermes: Model Provider Plugins](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)
- [Copilot ACP Client en Hermes](https://github.com/NousResearch/hermes-agent/blob/main/agent/copilot_acp_client.py)
