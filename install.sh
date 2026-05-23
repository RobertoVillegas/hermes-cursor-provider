#!/usr/bin/env bash
set -euo pipefail

# hermes-cursor-provider install script
# Aplica los patches necesarios al core de Hermes + copia archivos + instala plugin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------------------------------------------------------------------------
# Detect paths
# ---------------------------------------------------------------------------
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-${HOME}/.hermes/hermes-agent}"
HERMES_WEBUI_DIR="${HERMES_WEBUI_DIR:-${HOME}/.hermes/hermes-webui}"
PATCHES_DIR="${SCRIPT_DIR}/patches"

if [[ ! -d "$HERMES_AGENT_DIR" ]]; then
    log_error "Hermes agent not found at $HERMES_AGENT_DIR"
    log_info "Set HERMES_AGENT_DIR to override."
    exit 1
fi

if [[ ! -d "$HERMES_WEBUI_DIR" ]]; then
    log_warn "Hermes WebUI not found at $HERMES_WEBUI_DIR — WebUI patch will be skipped."
    HERMES_WEBUI_DIR=""
fi

log_info "Hermes agent:  $HERMES_AGENT_DIR"
log_info "Hermes WebUI:  ${HERMES_WEBUI_DIR:-<not found>}"

# ---------------------------------------------------------------------------
# Check for uncommitted changes
# ---------------------------------------------------------------------------
for dir in "$HERMES_AGENT_DIR"; do
    if git -C "$dir" status --porcelain | grep -q .; then
        log_warn "Uncommitted changes in $dir"
        log_warn "It's recommended to commit or stash before patching."
        read -rp "Continue anyway? [y/N] " ans
        [[ "${ans:-}" =~ [Yy] ]] || exit 0
    fi
done

if [[ -n "$HERMES_WEBUI_DIR" ]]; then
    if git -C "$HERMES_WEBUI_DIR" status --porcelain 2>/dev/null | grep -q .; then
        log_warn "Uncommitted changes in $HERMES_WEBUI_DIR"
        read -rp "Continue anyway? [y/N] " ans
        [[ "${ans:-}" =~ [Yy] ]] || exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Apply agent patches (001-012)
# ---------------------------------------------------------------------------
log_info "Applying agent patches..."
for patch_file in "$PATCHES_DIR"/001-*.patch "$PATCHES_DIR"/002-*.patch "$PATCHES_DIR"/003-*.patch \
                   "$PATCHES_DIR"/004-*.patch "$PATCHES_DIR"/005-*.patch \
                   "$PATCHES_DIR"/006-*.patch "$PATCHES_DIR"/007-*.patch \
                   "$PATCHES_DIR"/008-*.patch "$PATCHES_DIR"/009-*.patch \
                   "$PATCHES_DIR"/010-*.patch "$PATCHES_DIR"/011-*.patch \
                   "$PATCHES_DIR"/012-*.patch; do
    if [[ -f "$patch_file" ]]; then
        pname=$(basename "$patch_file")
        if git -C "$HERMES_AGENT_DIR" apply --check "$patch_file" 2>/dev/null; then
            git -C "$HERMES_AGENT_DIR" apply "$patch_file"
            log_info "  Applied $pname"
        else
            log_warn "  $pname already applied or conflicts — skipping"
        fi
    fi
done

# ---------------------------------------------------------------------------
# Copy cursor_acp_client.py into agent/
# ---------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/cursor_acp_client.py" ]]; then
    cp "${SCRIPT_DIR}/cursor_acp_client.py" "$HERMES_AGENT_DIR/agent/cursor_acp_client.py"
    log_info "Copied cursor_acp_client.py → agent/"
fi

# ---------------------------------------------------------------------------
# Apply WebUI patch (013)
# ---------------------------------------------------------------------------
if [[ -n "$HERMES_WEBUI_DIR" && -f "$PATCHES_DIR/013-hermes-webui-config.patch" ]]; then
    if git -C "$HERMES_WEBUI_DIR" apply --check "$PATCHES_DIR/013-hermes-webui-config.patch" 2>/dev/null; then
        git -C "$HERMES_WEBUI_DIR" apply "$PATCHES_DIR/013-hermes-webui-config.patch"
        log_info "Applied 013-hermes-webui-config.patch"
    else
        log_warn "013-hermes-webui-config.patch already applied or conflicts — skipping"
    fi
else
    log_warn "WebUI patch skipped (no WebUI dir or patch missing)"
fi

# ---------------------------------------------------------------------------
# Install plugin profile
# ---------------------------------------------------------------------------
PLUGIN_DEST="${HOME}/.hermes/plugins/model-providers/cursor-acp"
mkdir -p "$PLUGIN_DEST"
if [[ -d "${SCRIPT_DIR}/plugins/model-providers/cursor-acp" ]]; then
    cp -r "${SCRIPT_DIR}/plugins/model-providers/cursor-acp/"* "$PLUGIN_DEST/"
    log_info "Installed plugin profile → ~/.hermes/plugins/model-providers/cursor-acp/"
fi

# ---------------------------------------------------------------------------
# Clear caches
# ---------------------------------------------------------------------------
log_info "Clearing Python caches..."
find "$HERMES_AGENT_DIR" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$HERMES_WEBUI_DIR" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
rm -f "${HOME}/.hermes/webui/models_cache.json" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log_info ""
log_info "=========================================="
log_info "Installation complete!"
log_info "=========================================="
log_info ""
log_info "Next steps:"
log_info ""
log_info "1. Verify Cursor CLI is installed:"
log_info "   agent --version"
log_info ""
log_info "2. Authenticate (requires Cursor Individual/Pro subscription):"
log_info "   agent login"
log_info ""
log_info "3. Restart Hermes services to load changes:"
log_info "   kill $(lsof -t -i:8787) 2>/dev/null; sleep 2"
log_info "   # Then restart your WebUI server"
log_info ""
log_info "4. Open Hermes WebUI or run:"
log_info "   hermes chat"
log_info "   /model"
log_info "   # Select 'Cursor ACP'"
log_info ""
log_info "5. To use in WebUI, refresh your browser after restart."
log_info ""
log_info "For issues, see README.md and CONTRIBUTING.md"
