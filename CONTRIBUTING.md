# Como contribuir el provider de Cursor a Hermes

## Opcion recomendada: PR al repo oficial

Basado en la [documentacion oficial de Hermes](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers) sobre como agregar providers.

---

## Paso 0: Entender los dos niveles

Hermes maneja providers en dos capas:

1. **Plugin Profile** (`plugins/model-providers/<name>/`): Declara metadata. Puede ser standalone.
2. **ACP Client** (`agent/<name>_acp_client.py`): Logica de ejecucion. Requiere cambios en el core.

Para Cursor ACP necesitamos **ambos**.

---

## Paso 1: Fork de hermes-agent

```bash
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
git checkout -b feat/cursor-acp-provider
```

---

## Paso 2: Aplicar los cambios del core

### 2.1 Plugin profile (drop-in)

```bash
# Copiar plugin al repo de Hermes
cp -r ../hermes-cursor-provider/plugins/model-providers/cursor-acp \
       plugins/model-providers/
```

### 2.2 ACP client

```bash
# Copiar cliente ACP
cp ../hermes-cursor-provider/cursor_acp_client.py \
   agent/cursor_acp_client.py
```

### 2.3 Patches al core

Aplicar cada patch con `patch -p1 < archivo.patch` desde el directorio raiz de hermes-agent:

| Patch | Archivo modificado | Que hace |
|-------|-------------------|----------|
| `001-hermes_cli-providers.patch` | `hermes_cli/providers.py` | Agrega overlay `cursor-acp` + alias + label |
| `002-hermes_cli-auth.patch` | `hermes_cli/auth.py` | Agrega `cursor-acp` a `PROVIDER_REGISTRY` |
| `003-hermes_cli-runtime_provider.patch` | `hermes_cli/runtime_provider.py` | Agrega resolucion runtime para `cursor-acp` |
| `004-agent-agent_runtime_helpers.patch` | `agent/agent_runtime_helpers.py` | Instancia `CursorACPClient` cuando `base_url` es `acp://cursor` |
| `005-hermes_cli-models.patch` | `hermes_cli/models.py` | Agrega modelos/aliases de Cursor |

---

## Paso 3: Pre-requisitos para probar

```bash
# Instalar Cursor CLI
npm install -g @cursor/agent
# o descargar desde cursor.com/downloads

# Verificar que funciona
cursor --help
cursor login  # Autenticar
```

---

## Paso 4: Probar localmente

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

---

## Paso 5: Tests

Segun la [documentacion oficial](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers), los tests minimos deben cubrir:

- Auth resolution
- CLI menu / provider selection
- Runtime provider resolution
- Agent execution path
- `provider:model` parsing

```bash
# Tests de provider wiring
pytest tests/test_runtime_provider_resolution.py -k cursor -n0 -q
pytest tests/test_cli_provider_resolution.py -k cursor -n0 -q
pytest tests/test_cli_model_command.py -k cursor -n0 -q

# Smoke test
python -m hermes_cli.main chat -q "Say hello" --provider cursor-acp --model cursor-default
```

---

## Paso 6: Commit y PR

```bash
git add plugins/model-providers/cursor-acp/
git add agent/cursor_acp_client.py
git add hermes_cli/providers.py
git add hermes_cli/auth.py
git add hermes_cli/runtime_provider.py
git add agent/agent_runtime_helpers.py
git add hermes_cli/models.py  # si aplica

git commit -m "feat: add Cursor ACP provider

Add support for Cursor Agent via Agent Client Protocol (ACP).

- New plugin: plugins/model-providers/cursor-acp/
- New ACP client: agent/cursor_acp_client.py
- Register provider in auth.py, providers.py, runtime_provider.py
- Wire client instantiation in agent_runtime_helpers.py
- Add cursor models/aliases in models.py

Cursor ACP uses 'cursor --acp --stdio' as a subprocess and
communicates via JSON-RPC 2.0. Authentication is handled
via 'cursor login' (OAuth through the Cursor CLI).

Refs:
- https://cursor.com/docs/cli/acp
- https://x.com/leerob/status/2057170644681277470
- https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers"

git push origin feat/cursor-acp-provider
```

---

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
  models.py            # +cursor models/aliases (si aplica)
agent/
  agent_runtime_helpers.py  # +CursorACPClient instantiation
```

---

## Checklist segun la documentacion oficial de Hermes

### OpenAI-compatible provider checklist
- [ ] ProviderConfig added in `hermes_cli/auth.py`
- [ ] aliases added in `hermes_cli/auth.py` and `hermes_cli/models.py`
- [ ] model catalog added in `hermes_cli/models.py`
- [ ] runtime branch added in `hermes_cli/runtime_provider.py`
- [ ] CLI wiring added in `hermes_cli/main.py` (setup.py inherits automatically)
- [ ] aux model added in `agent/auxiliary_client.py`
- [ ] context lengths added in `agent/model_metadata.py`
- [ ] runtime / CLI tests updated
- [ ] user docs updated

### Native provider checklist (ACP = native)
- [ ] todo lo anterior
- [ ] adapter added in `agent/cursor_acp_client.py`
- [ ] new api_mode supported in `run_agent.py` (chat_completions ya existe)
- [ ] interrupt / rebuild path works
- [ ] usage and finish-reason extraction works
- [ ] fallback path works
- [ ] adapter tests added
- [ ] live smoke test passes

---

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

Si Cursor usa un formato diferente a `<tool_call>{...}</tool_call>`, modifica `_TOOL_CALL_BLOCK_RE` en `cursor_acp_client.py`.

---

## Nota sobre el plugin pip

Este repo (`hermes-cursor-provider`) incluye un paquete pip-installable que registra el **plugin profile declarativo**. Esto permite que los usuarios instalen:

```bash
pip install hermes-cursor-provider
```

Y el profile aparecera en `hermes doctor` y `hermes model`. **Pero no funcionara hasta que el ACP client este en el core.**
