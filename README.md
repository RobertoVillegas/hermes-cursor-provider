# hermes-cursor-provider

Provider de Cursor para Hermes Agent. Permite usar el agente de Cursor via ACP (Agent Client Protocol) como backend de inferencia en Hermes, igual que funciona GitHub Copilot ACP, OpenAI Codex, y los demas providers nativos.

**Repo:** https://github.com/RobertoVillegas/hermes-cursor-provider

---

## Estado

En desarrollo. Analisis de arquitectura completado. Implementacion lista para PR al upstream.

## Que es Cursor ACP?

Cursor expone su agente AI via **Agent Client Protocol (ACP)**, un protocolo JSON-RPC 2.0 sobre stdin/stdout. Esto permite que cualquier cliente (IDEs, CLI tools, etc.) se conecten al agente de Cursor.

El flujo basico:

1. Iniciar `cursor --acp --stdio` como subproceso
2. Enviar `initialize` con capabilities del cliente
3. Autenticar via `authenticate` (methodId: `cursor_login`)
4. Crear sesion via `session/new`
5. Enviar prompts via `session/prompt`
6. Recibir respuestas streaming via `session/update` notifications

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
| `ARCHITECTURE_ANALYSIS.md` | Analisis profundo de como funciona el sistema de providers en Hermes |
| `IMPLEMENTATION.md` | Plan de implementacion paso a paso |
| `cursor_acp_client.py` | Cliente ACP completo (shim OpenAI-compatible) |
| `plugins/model-providers/cursor-acp/` | Plugin profile declarativo |
| `patches/` | 5 archivos patch para los cambios minimos en el core |
| `CONTRIBUTING.md` | Guia para crear el PR al repo oficial |
| `setup.py` / `pyproject.toml` | Instalacion pip del plugin profile |

## Instalacion (solo plugin profile)

### Opcion A: Drop-in manual

```bash
mkdir -p ~/.hermes/plugins/model-providers/cursor-acp
cp -r plugins/model-providers/cursor-acp/* ~/.hermes/plugins/model-providers/cursor-acp/
```

### Opcion B: pip install (cuando este publicado)

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
hermes config set model.default "cursor-default"

# Chat
hermes chat
```

## Pre-requisitos

- [Cursor CLI](https://cursor.com/downloads) instalado (`cursor --acp --stdio` funciona)
- Sesion de Cursor autenticada (`cursor login`)

## Como contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para los pasos detallados para crear un PR al repo oficial de Hermes.

## Documentacion oficial de Hermes

- [Model Provider Plugins](https://hermes-agent.nousresearch.com/docs/developer-guide/model-provider-plugin)
- [Adding Providers](https://hermes-agent.nousresearch.com/docs/developer-guide/adding-providers)
- [Provider Runtime](https://hermes-agent.nousresearch.com/docs/developer-guide/provider-runtime)

## License

MIT
