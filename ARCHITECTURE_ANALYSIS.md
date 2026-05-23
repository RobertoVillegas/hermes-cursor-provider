# Analisis de Arquitectura: Como integrar Cursor ACP en Hermes

Basado en:
- Codigo fuente de Hermes Agent (v0.14.0+)
- [Model Provider Plugins docs](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)
- [Adding Providers docs](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)

---

## Conclusion rapida

**Se necesita un PR al repo oficial de Hermes.** El provider de Cursor ACP requiere cambios en el core porque el cliente ACP debe vivir en `agent/` y ser importado por `agent_runtime_helpers.py`.

**PERO:** La parte declarativa (plugin profile) SI puede ser standalone - como paquete pip o drop-in en `~/.hermes/plugins/model-providers/`.

El patron exacto ya existe con `copilot-acp`. El `cursor-acp` es esencialmente un fork de ese patron.

---

## Como funciona el sistema de providers en Hermes

Hermes maneja providers en capas, segun la [documentacion oficial](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers):

```
1. Auth (hermes_cli/auth.py) -> como se encuentran credenciales
2. Runtime (hermes_cli/runtime_provider.py) -> datos de ejecucion (provider, api_mode, base_url, api_key)
3. Transport (run_agent.py) -> como se construyen y envian requests
4. CLI (hermes_cli/models.py, hermes_cli/main.py) -> menus y UX
5. Aux (agent/auxiliary_client.py, agent/model_metadata.py) -> tareas secundarias
```

La abstraccion clave es `api_mode`:
- `chat_completions` -> transporte HTTP OpenAI estandar
- `codex_responses` -> API de respuestas de Codex
- `anthropic_messages` -> protocolo nativo de Anthropic
- `bedrock_converse` -> AWS Bedrock
- **`external_process` -> subprocess ACP (solo `copilot-acp` hoy)**

---

## Path A vs Path B

### Path A: Provider OpenAI-compatible (fast path)

Para providers que aceptan requests estandar de chat-completions. Solo necesitas:
- `plugins/model-providers/<name>/__init__.py` (con `register_provider()`)
- `plugins/model-providers/<name>/plugin.yaml` (manifest)

**Zero cambios al core.** Ejemplos: GMI, Nvidia, DeepSeek.

### Path B: Provider nativo / non-OpenAI

Para providers que NO se comportan como chat-completions estandar. Necesitas:
- Todo lo de Path A
- **Un adapter en `agent/<provider>_adapter.py`**
- **Branches en `run_agent.py`** para request building, dispatch, usage extraction, etc.

Ejemplos en el arbol: `codex_responses`, `anthropic_messages`, `copilot-acp`.

**Cursor ACP es Path B** porque usa JSON-RPC sobre stdin/stdout, no HTTP.

---

## Por que NO puede ser solo un plugin standalone

Los model-provider plugins de Hermes son **declarativos** (describen el provider) pero **NO ejecutan codigo custom** que reemplace el transporte:

```python
# ProviderProfile hooks disponibles:
prepare_messages()        # pre-procesamiento de mensajes
build_extra_body()        # campos extra en extra_body
build_api_kwargs_extras() # split entre extra_body y top-level kwargs
fetch_models()            # fetch de catalogo de modelos
```

**Ningun hook permite decir "usa subprocess en vez de HTTP".**

Para ACP, Hermes necesita un cliente especial que spawnee subprocess y hable JSON-RPC, y eso solo se puede hacer desde el core:

```python
# agent/agent_runtime_helpers.py (linea ~1204)
if agent.provider == "copilot-acp" or base_url.startswith("acp://copilot"):
    from agent.copilot_acp_client import CopilotACPClient
    client = CopilotACPClient(**client_kwargs)
```

Para Cursor necesitariamos agregar:
```python
if agent.provider == "cursor-acp" or base_url.startswith("acp://cursor"):
    from agent.cursor_acp_client import CursorACPClient
    client = CursorACPClient(**client_kwargs)
```

Esto **debe estar en el core** porque:
1. `agent_runtime_helpers.py` importa desde `agent.*`
2. El cliente ACP necesita acceso a `agent.file_safety`, `agent.redact`, etc.
3. El ciclo de conversacion en `run_agent.py` necesita saber que no es un cliente HTTP estandar

---

## Estrategias posibles

### Opcion A: PR al repo oficial de Hermes (RECOMENDADA)

**Pros:**
- Integracion nativa y completa
- Comunidad de Hermes puede revisar y mantener
- Funciona out-of-the-box para todos los usuarios
- Reutiliza 90% del codigo de `copilot-acp`

**Cons:**
- Requiere review del equipo de Nous Research
- Puede tardar en mergearse

**Files a tocar (basado en la doc oficial "File checklist"):**

| File | Cambio | Complejidad |
|------|--------|-------------|
| `plugins/model-providers/cursor-acp/__init__.py` | Nuevo: provider profile | Baja |
| `plugins/model-providers/cursor-acp/plugin.yaml` | Nuevo: manifest | Baja |
| `agent/cursor_acp_client.py` | Nuevo: ~540 LOC (copia de copilot_acp_client.py adaptado) | Media |
| `agent/agent_runtime_helpers.py` | +5 lines: branch para cursor-acp | Baja |
| `hermes_cli/providers.py` | +10 lines: overlay + alias + label | Baja |
| `hermes_cli/auth.py` | +8 lines: PROVIDER_REGISTRY entry | Baja |
| `hermes_cli/runtime_provider.py` | +10 lines: runtime resolution | Baja |
| `hermes_cli/models.py` | +5 lines: modelos/aliases de cursor | Baja |
| `agent/auxiliary_client.py` | +3 lines: aux model default | Baja |
| `tests/` | Tests unitarios e integracion | Media |
| `website/docs/` | Documentacion del provider | Baja |

**Total: ~12 files. La mayoria son adiciones de 5-10 lineas. El trabajo real es el ACP client (~540 LOC).**

---

### Opcion B: Plugin pip + monkey-patch (NO recomendada)

Crear un plugin que solo declara el provider profile, y luego usar un script que:
1. Inyecta `CursorACPClient` en `sys.modules['agent.cursor_acp_client']`
2. Modifica `agent_runtime_helpers.py` en memoria

**Pros:** Ninguno real.
**Cons:** Fragil, dificil de instalar, no mantenible, no compartible.

---

### Opcion C: Repo independiente con referencia de implementacion (LO QUE ESTAMOS HACIENDO)

Este repo (`hermes-cursor-provider`) contiene:
1. El codigo completo del ACP client listo para copiar
2. El plugin profile listo para drop-in o pip install
3. Patches documentados para los cambios minimos del core
4. Guia de contribucion con pasos para el PR

**Pros:**
- Sirve como base para el PR
- Documenta exactamente que cambios se necesitan
- El plugin profile puede usarse standalone (aparece en `hermes doctor`)
- Facil de probar para usuarios avanzados

**Cons:**
- Requiere que alguien haga el PR al upstream
- El ACP client no funciona hasta que este en el core

---

## Recomendacion final

1. **Este repo** (`hermes-cursor-provider`) sirve como **referencia de implementacion**
2. **Fork de hermes-agent** y crear rama con todos los cambios
3. **Probar exhaustivamente** localmente con Cursor CLI instalado
4. **Enviar PR** al repo oficial de Nous Research
5. **Mantener este repo** como documentacion complementaria y como paquete pip del plugin profile

---

## Diferencias clave: Copilot ACP vs Cursor ACP

| Aspecto | Copilot ACP | Cursor ACP |
|---------|------------|------------|
| **Comando** | `copilot --acp --stdio` | `agent acp` |
| **Auth** | GitHub token (via `gh auth`) | `agent login` (browser) o `CURSOR_API_KEY` |
| **Auth en protocolo** | Ninguno (ya autenticado via CLI) | `authenticate` con `methodId: "cursor_login"` |
| **Base URL** | `acp://copilot` | `acp://cursor` |
| **Env var comando** | `HERMES_COPILOT_ACP_COMMAND` | `CURSOR_ACP_COMMAND` |
| **Model selection** | Interna (Copilot elige) | Interna (Cursor elige) |
| **Extensiones** | `fs/read`, `fs/write` | Igual + `cursor/ask_question`, `cursor/create_plan`, etc. |
| **Subagentes** | No | Si (`cursor/task`) |

---

## Files de referencia en Hermes

| File | Descripcion |
|------|-------------|
| `plugins/model-providers/copilot-acp/__init__.py` | Template del plugin profile |
| `plugins/model-providers/copilot-acp/plugin.yaml` | Template del manifest |
| `agent/copilot_acp_client.py` | Template del ACP client (~686 LOC) |
| `agent/agent_runtime_helpers.py:1204` | Donde se instancia el ACP client |
| `hermes_cli/auth.py:233` | Donde se registra el provider config |
| `hermes_cli/providers.py:87` | Donde se define el overlay |
| `hermes_cli/runtime_provider.py:1451` | Donde se resuelve el runtime |
| `providers/base.py` | `ProviderProfile` ABC con hooks |
| `providers/__init__.py` | `register_provider()` y discovery |

---

## Documentacion oficial relevante

- [Model Provider Plugins](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)
- [Adding Providers](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)
- [Provider Runtime](https://hermes-agent.nousresearch.com/docs/developer-guide/provider-runtime)
