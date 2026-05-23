# Plan de Implementacion: Cursor ACP Provider para Hermes

## Resumen

Implementar un provider ACP para Cursor en Hermes Agent, comparable en calidad y patrones a los providers existentes (`copilot-acp`, `openai-codex`, `github-copilot`).

## Pre-requisitos

1. Cursor CLI instalado localmente (`cursor --acp --stdio` funciona)
2. Sesion de Cursor autenticada (`cursor login`)
3. Hermes Agent instalado desde source para desarrollo

## Fase 1: Scaffold y ACP Client (agent/cursor_acp_client.py)

Crear el cliente ACP para Cursor, basado en `agent/copilot_acp_client.py`.

### 1.1 Estructura base

```python
"""OpenAI-compatible shim que forward requests a `cursor --acp`."""
```

### 1.2 Diferencias clave vs Copilot ACP

| Item | Copilot | Cursor |
|------|---------|--------|
| Comando default | `copilot` | `cursor` |
| Args default | `--acp --stdio` | `--acp --stdio` |
| Env var comando | `HERMES_COPILOT_ACP_COMMAND` | `CURSOR_ACP_COMMAND` |
| Env var args | `HERMES_COPILOT_ACP_ARGS` | `CURSOR_ACP_ARGS` |
| Auth method ID | (none - usa GitHub token) | `cursor_login` |
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

## Fase 2: Provider Registry

### 2.1 hermes_cli/providers.py

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
"cursor-acp": "cursor-acp",
```

Agregar label:
```python
"cursor-acp": "Cursor ACP",
```

### 2.2 hermes_cli/auth.py

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

## Fase 3: Runtime Resolution

### 3.1 hermes_cli/runtime_provider.py

En `resolve_runtime_credentials()` o similar, agregar branch para `cursor-acp` que:
1. Verifique que `cursor` (o `CURSOR_ACP_COMMAND`) existe en PATH
2. Verifique que el usuario tiene sesion autenticada
3. Devuelva `base_url="acp://cursor"` y `api_mode="codex_responses"`

### 3.2 agent/chat_completion_helpers.py

En `create_openai_client()` o similar, agregar branch para URLs que empiecen con `acp://cursor`:

```python
if base_url.startswith("acp://cursor"):
    from agent.cursor_acp_client import CursorACPClient
    return CursorACPClient(
        api_key=api_key,
        base_url=base_url,
        acp_command=...,
        acp_args=...,
    )
```

## Fase 4: Modelos

### 4.1 hermes_cli/models.py

Definir modelos disponibles de Cursor. Cursor no expone model names tradicionales, pero podemos definir aliases:

```python
CURSOR_MODELS = [
    "cursor-default",
    "cursor-agent",
]
```

En la practica, el modelo se selecciona internamente por Cursor basado en el prompt y contexto.

## Fase 5: Testing

### 5.1 Tests unitarios

- Mock del subprocess `cursor`
- Verificar formato JSON-RPC correcto
- Verificar extraccion de tool calls
- Verificar manejo de permisos

### 5.2 Tests de integracion

- `hermes chat --provider cursor-acp --model cursor-default`
- Verificar que se inicia el subprocess
- Verificar que se autentica
- Verificar que responde correctamente

## Fase 6: Documentacion

### 6.1 Docs de Hermes

Agregar a `website/docs/integrations/providers.md`:
- Setup del provider
- Instalacion de Cursor CLI
- Autenticacion
- Troubleshooting

### 6.2 Este repo

Mantener actualizado con cambios del upstream.

## Diagrama de flujo

```
Usuario -> hermes chat
  -> HermesCLI
    -> runtime_provider.resolve_runtime_credentials("cursor-acp")
      -> Devuelve base_url="acp://cursor"
    -> chat_completion_helpers.create_openai_client(base_url="acp://cursor")
      -> CursorACPClient (shim OpenAI-compatible)
        -> subprocess.Popen(["cursor", "--acp", "--stdio"])
          -> initialize -> authenticate -> session/new -> session/prompt
          <- session/update notifications (streaming)
        <- Response text
      <- OpenAI-format response
    <- Final answer
```

## Referencias

- [Cursor ACP Docs](https://cursor.com/docs/cli/acp)
- [Hermes Provider Docs](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [Lee Robinson Tweet](https://x.com/leerob/status/2057170644681277470?s=20)
- [Copilot ACP Client en Hermes](https://github.com/NousResearch/hermes-agent/blob/main/agent/copilot_acp_client.py)
