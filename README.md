# hermes-cursor-provider

Provider de Cursor para Hermes Agent. Permite usar el agente de Cursor via ACP (Agent Client Protocol) como backend de inferencia en Hermes, igual que funciona GitHub Copilot ACP, OpenAI Codex, y los demas providers nativos.

**Repo:** https://github.com/RobertoVillegas/hermes-cursor-provider

---

## Estado

En desarrollo. Analisis de arquitectura completado. Implementacion lista para PR al upstream.

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

## Composer 2.5 y suscripcion

Segun [Lee Robinson](https://x.com/leerob/status/2057170644681277470), Cursor **no ofrece acceso API directo** a su modelo Composer 2.5. La unica forma de usar Composer 2.5 es via ACP con `agent login` (autenticacion browser/suscripcion de Cursor). Las API keys de Cursor funcionan para otros modelos/flujos, pero Composer 2.5 requiere ACP.

| Auth method | Modelos disponibles | Requiere |
|-------------|-------------------|----------|
| `agent login` (browser) | **Todos incluyendo Composer 2.5** | Suscripcion de Cursor |
| `CURSOR_API_KEY` | Modelos basicos / API access | API key del dashboard |

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
| `patches/` | 5 archivos patch para los cambios minimos en el core |
| `CONTRIBUTING.md` | Guia para crear el PR al repo oficial |
| `pyproject.toml` | Config del paquete pip |
| `hermes_cursor_provider/` | Paquete pip-installable |

## Instalacion de Cursor CLI

```bash
# Via npm (recomendado)
npm install -g @cursor/agent

# Verificar
agent --help
agent login        # Browser auth para Composer 2.5
# o
export CURSOR_API_KEY=sk-...   # Para automation/flujos basicos
```

El binario se instala como `agent` (no `cursor`). Ubicacion tipica: `~/.local/bin/agent`.

## Instalacion del plugin profile (standalone)

### Opcion A: Drop-in manual

```bash
mkdir -p ~/.hermes/plugins/model-providers/cursor-acp
cp -r plugins/model-providers/cursor-acp/* ~/.hermes/plugins/model-providers/cursor-acp/
```

### Opcion B: pip install

```bash
pip install hermes-cursor-provider
```

**Nota:** El plugin profile solo registra metadata. Para que funcione completamente, necesitas el ACP client en el core de Hermes (ver CONTRIBUTING.md).

## Uso en Hermes (despues del PR)

```bash
# Configurar provider
hermes model
# -> Seleccionar "Cursor ACP"

# O manualmente en config.yaml
hermes config set model.provider cursor-acp

# Chat
hermes chat
```

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
