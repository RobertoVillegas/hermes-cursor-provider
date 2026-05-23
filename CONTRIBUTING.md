# Como contribuir el provider de Cursor a Hermes

## Opcion recomendada: PR al repo oficial

### Paso 1: Fork de hermes-agent

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
git checkout -b feat/cursor-acp-provider
```

### Paso 2: Aplicar los cambios del core

Copia los archivos de este repo al checkout de Hermes:

```bash
# Desde el directorio de hermes-agent:

# 1. Plugin profile
cp -r ../hermes-cursor-provider/plugins/model-providers/cursor-acp \
       plugins/model-providers/

# 2. ACP client
cp ../hermes-cursor-provider/cursor_acp_client.py \
   agent/cursor_acp_client.py

# 3. Aplicar patches al core
patch -p1 < ../hermes-cursor-provider/patches/001-hermes_cli-providers.patch
patch -p1 < ../hermes-cursor-provider/patches/002-hermes_cli-auth.patch
patch -p1 < ../hermes-cursor-provider/patches/003-hermes_cli-runtime_provider.patch
patch -p1 < ../hermes-cursor-provider/patches/004-agent-agent_runtime_helpers.patch
```

### Paso 3: Pre-requisitos para probar

```bash
# Instalar Cursor CLI
npm install -g @cursor/agent
# o descargar desde cursor.com/downloads

# Verificar que funciona
cursor --help
cursor login  # Autenticar
```

### Paso 4: Probar localmente

```bash
# Activar venv de Hermes
source .venv/bin/activate

# Instalar en modo desarrollo
pip install -e .

# Probar el provider
hermes model
# -> Seleccionar "Cursor ACP"

hermes chat
# -> Deberia iniciar cursor --acp --stdio y funcionar
```

### Paso 5: Tests

```bash
# Copiar tests de referencia de copilot-acp y adaptar
# Ver tests/hermes_cli/test_api_key_providers.py para el patron

pytest tests/hermes_cli/test_api_key_providers.py -k cursor
pytest tests/run_agent/test_run_agent.py -k cursor_acp
```

### Paso 6: Commit y PR

```bash
git add plugins/model-providers/cursor-acp/
git add agent/cursor_acp_client.py
git add hermes_cli/providers.py
git add hermes_cli/auth.py
git add hermes_cli/runtime_provider.py
git add agent/agent_runtime_helpers.py
git commit -m "feat: add Cursor ACP provider

Add support for Cursor Agent via Agent Client Protocol (ACP).

- New plugin: plugins/model-providers/cursor-acp/
- New ACP client: agent/cursor_acp_client.py
- Register provider in auth.py, providers.py, runtime_provider.py
- Wire client instantiation in agent_runtime_helpers.py

Cursor ACP uses cursor --acp --stdio as a subprocess and
communicates via JSON-RPC 2.0. Authentication is handled
via cursor login (OAuth through the Cursor CLI)."

git push origin feat/cursor-acp-provider
```

## Estructura de archivos del PR

```
plugins/model-providers/cursor-acp/
  __init__.py          # ProviderProfile registration
  plugin.yaml          # Manifest
agent/
  cursor_acp_client.py # ACP client (OpenAI-compatible shim)
hermes_cli/
  providers.py         # +HermesOverlay, +aliases, +label
  auth.py              # +ProviderConfig in PROVIDER_REGISTRY
  runtime_provider.py  # +runtime resolution for cursor-acp
agent/
  agent_runtime_helpers.py  # +CursorACPClient instantiation
```

## Troubleshooting

### "cursor command not found"

Asegurate de que `cursor` este en PATH:
```bash
export CURSOR_ACP_COMMAND=/ruta/absoluta/a/cursor
```

### "Cursor ACP authentication failed"

Ejecuta `cursor login` primero. Cursor requiere sesion autenticada.

### El proceso ACP se cierra inmediatamente

Verifica stderr:
```bash
cursor --acp --stdio 2>&1 | head -20
```

### Los tool calls no se extraen correctamente

Si Cursor usa un formato diferente a `<tool_call>{...}</tool_call>`,
modifica `_TOOL_CALL_BLOCK_RE` en `cursor_acp_client.py`.
