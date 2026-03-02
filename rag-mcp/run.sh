#!/bin/bash
# Wrapper script to launch life-rag-mcp
# Ensures Ollama is running before starting the MCP server
# Supports both uv and pip+venv

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

export LIFE_REPO_PATH="${LIFE_REPO_PATH:-$REPO_ROOT}"

# ── Resolve Ollama URL ──

IS_WSL2=false
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    IS_WSL2=true
    WIN_HOST=$(ip route show default | awk '{print $3}')
fi

if [ -z "${OLLAMA_URL:-}" ]; then
    if $IS_WSL2; then
        # WSL2: try Windows host first, then localhost
        if curl -sf --connect-timeout 2 "http://${WIN_HOST}:11434/api/tags" &>/dev/null; then
            export OLLAMA_URL="http://${WIN_HOST}:11434"
        else
            export OLLAMA_URL="http://localhost:11434"
        fi
    else
        export OLLAMA_URL="http://localhost:11434"
    fi
fi

# ── Ensure Ollama runner symlink ──
# Ollama 0.17+ spawns a subprocess called 'serve' for model inference.
# In some environments (proot-distro, containers), this binary is not in PATH.
ensure_ollama_runner() {
    command -v serve &>/dev/null && return 0
    local ollama_bin
    ollama_bin="$(command -v ollama 2>/dev/null)" || return 1
    if ln -sf "$ollama_bin" /usr/local/bin/serve 2>/dev/null; then
        return 0
    elif mkdir -p "$HOME/.local/bin" 2>/dev/null && ln -sf "$ollama_bin" "$HOME/.local/bin/serve" 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        return 0
    fi
    return 1
}

if command -v ollama &>/dev/null; then
    ensure_ollama_runner
fi

# ── Ensure Ollama is running ──

ensure_ollama() {
    # Already running?
    if curl -sf --connect-timeout 2 "$OLLAMA_URL/api/tags" &>/dev/null; then
        return 0
    fi

    # WSL2 with Windows Ollama: can't auto-start from here
    if $IS_WSL2 && [ "$OLLAMA_URL" = "http://${WIN_HOST}:11434" ]; then
        # Fall back to localhost if ollama is installed locally
        if command -v ollama &>/dev/null; then
            export OLLAMA_URL="http://localhost:11434"
            if curl -sf --connect-timeout 2 "$OLLAMA_URL/api/tags" &>/dev/null; then
                return 0
            fi
            ollama serve &>/dev/null &
            sleep 2
            if curl -sf --connect-timeout 2 "$OLLAMA_URL/api/tags" &>/dev/null; then
                return 0
            fi
        fi
        return 1
    fi

    # Local Ollama: try to start
    if command -v ollama &>/dev/null; then
        ollama serve &>/dev/null &
        # Wait up to 10 seconds for startup
        for i in $(seq 1 10); do
            if curl -sf --connect-timeout 1 "$OLLAMA_URL/api/tags" &>/dev/null; then
                return 0
            fi
            sleep 1
        done
    fi

    return 1
}

ensure_ollama
# Note: even if Ollama is unreachable, we still start the MCP server.
# The server handles this gracefully and returns helpful error messages.

# ── Launch MCP server ──

# Prefer uv, fall back to venv
if command -v uv &>/dev/null; then
    exec uv --directory "$SCRIPT_DIR" run life-rag-mcp
elif [ -x "$VENV_DIR/bin/life-rag-mcp" ]; then
    exec "$VENV_DIR/bin/life-rag-mcp"
else
    echo "Error: Neither uv nor venv found. Run setup.sh first." >&2
    exit 1
fi
