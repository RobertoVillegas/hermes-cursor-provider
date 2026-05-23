# Analisis de Arquitectura: Como integrar Cursor ACP en Hermes

## Conclusion rapida

**Se necesita un PR al repo oficial de Hermes.** El provider de Cursor ACP requiere cambios en el core de Hermes (no puede ser solo un plugin standalone) porque el cliente ACP debe vivir en `agent/` y ser importado por `agent_runtime_helpers.py`.

Sin embargo, la **mayor parte del trabajo** es copiar y adaptar el patron ya existente de `copilot-acp`. No es complejo.

---

## Como funciona el sistema de providers en Hermes

Hermes maneja providers en **5 capas**:

```
1. Plugin Profile (plugins/model-providers/<name>/)
   -> Declara metadata: nombre, alias, auth_type, base_url, api_mode
   -> Se auto-registra con register_provider() al importarse
   -> PUEDE ser standalone (user plugin en ~/.hermes/plugins/)

2. Auth Registry (hermes_cli/auth.py -> PROVIDER_REGISTRY)
   -> Mapea provider -> como se autentica
   -> Necesita entry para "external_process"
   -> **Requiere cambio en core**

3. Provider Overlay (hermes_cli/providers.py -> HERMES_OVERLAYS)
   -> Metadata extra sobre transporte y auth
   -> **Requiere cambio en core**

4. Runtime Resolution (hermes_cli/runtime_provider.py)
   -> Resuelve credenciales en tiempo de ejecucion
   -> Para ACP devuelve base_url="acp://cursor"
   -> **Requiere cambio en core**

5. ACP Client (agent/<name>_acp_client.py)
   -> El shim OpenAI-compatible que spawnea el subprocess
   -> Se instancia en agent_runtime_helpers.py
   -> **Requiere cambio en core** (nuevo archivo + 1 linea en runtime helpers)
```

---

## Por que NO puede ser solo un plugin standalone

Los model-provider plugins de Hermes son **declarativos** (describen el provider) pero **NO ejecutan codigo custom**:

```python
# Plugin: solo metadata, no logica de ejecucion
class ProviderProfile:
    name: str
    api_mode: str
    auth_type: str  # "api_key" | "oauth_*" | "external_process"
    base_url: str
    # ... hooks para transformar requests, pero NO para reemplazar el transporte
```

El `ProviderProfile` tiene hooks como `prepare_messages()` y `build_extra_body()`, pero **no puede reemplazar el cliente HTTP/transporte**.

Para ACP, Hermes necesita un cliente especial (subprocess JSON-RPC), y eso solo se puede hacer desde el core:

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
- Puede reutilizar 90% del codigo de copilot-acp

**Cons:**
- Requiere review del equipo de Nous Research
- Puede tardar en mergearse
- Necesita seguir los estandares de calidad del proyecto

**Files a tocar:**
| File | Cambio | Complejidad |
|------|--------|-------------|
| `plugins/model-providers/cursor-acp/__init__.py` | Nuevo: provider profile | Baja |
| `plugins/model-providers/cursor-acp/plugin.yaml` | Nuevo: manifest | Baja |
| `agent/cursor_acp_client.py` | Nuevo: ~680 LOC (copia de copilot_acp_client.py adaptado) | Media |
| `agent/agent_runtime_helpers.py` | +5 lines: branch para cursor-acp | Baja |
| `hermes_cli/providers.py` | +10 lines: overlay + alias + label | Baja |
| `hermes_cli/auth.py` | +8 lines: PROVIDER_REGISTRY entry | Baja |
| `hermes_cli/runtime_provider.py` | +10 lines: runtime resolution | Baja |
| `hermes_cli/models.py` | +5 lines: modelos/aliases de cursor | Baja |
| `tests/` | Tests unitarios e integracion | Media |
| `website/docs/` | Documentacion del provider | Baja |

**Total: ~12 files, la mayoria son adiciones pequenas. El trabajo real es el ACP client (~680 LOC).**

---

### Opcion B: Plugin standalone + monkey-patch (NO recomendada)

Crear un plugin que solo declara el provider profile, y luego usar un script/hook que:
1. Inyecta `CursorACPClient` en `sys.modules['agent.cursor_acp_client']`
2. Modifica `agent_runtime_helpers.py` en memoria

**Pros:**
- No esperar PR

**Cons:**
- Extremadamente fragil (se rompe con cualquier update de Hermes)
- Dificil de instalar
- No es mantenible
- No es compartible con la comunidad

---

### Opcion C: Repo independiente con "install script" (Intermedia)

Crear este repo (`hermes-cursor-provider`) con:
1. El codigo completo del ACP client
2. Un script `install.sh` que copia los archivos al checkout de Hermes
3. Un `patch` file que aplica los cambios minimos al core

**Pros:**
- Facil de probar para usuarios avanzados
- Sirve como base para el PR
- Documenta exactamente que cambios se necesitan

**Cons:**
- Requiere que el usuario tenga el repo de Hermes clonado
- Aun asi necesita tocar archivos del core

---

## Recomendacion final

1. **Crear este repo** (`hermes-cursor-provider`) como **referencia de implementacion** y para probar localmente
2. **Fork de hermes-agent** y crear una rama con todos los cambios
3. **Probar exhaustivamente** localmente con Cursor CLI instalado
4. **Enviar PR** al repo oficial de Nous Research
5. **Mantener este repo** como documentacion complementaria

El patron `copilot-acp` ya existe y funciona perfectamente. El `cursor-acp` seria esencialmente un "fork" de ese patron con:
- `cursor` en vez de `copilot` como comando
- `cursor_login` como auth method (vs GitHub OAuth de Copilot)
- Posiblemente extensiones extra del protocolo Cursor

---

## Diferencias clave: Copilot ACP vs Cursor ACP

| Aspecto | Copilot ACP | Cursor ACP |
|---------|------------|------------|
| **Comando** | `copilot --acp --stdio` | `cursor --acp --stdio` |
| **Auth** | GitHub token (via `gh auth`) | `cursor login` (OAuth propietario) |
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
| `agent/copilot_acp_client.py` | Template del ACP client (~686 LOC) |
| `agent/agent_runtime_helpers.py:1204` | Donde se instancia el ACP client |
| `hermes_cli/auth.py:233` | Donde se registra el provider config |
| `hermes_cli/providers.py:87` | Donde se define el overlay |
| `hermes_cli/runtime_provider.py:1451` | Donde se resuelve el runtime |
