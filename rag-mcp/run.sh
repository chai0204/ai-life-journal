#!/bin/bash
# Wrapper script to launch life-rag-mcp
# Ensures Ollama is running before starting the MCP server

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export LIFE_REPO_PATH="${LIFE_REPO_PATH:-$REPO_ROOT}"

# ── Resolve Ollama URL ──

IS_WSL2=false
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    IS_WSL2=true
    WIN_HOST=$(ip route show default | awk '{print $3}')
fi

if [ -z "$OLLAMA_URL" ]; then
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

UV="$(command -v uv)"
if [ -z "$UV" ]; then
    echo "Error: uv not found. Run setup.sh first." >&2
    exit 1
fi

exec "$UV" --directory "$SCRIPT_DIR" run life-rag-mcp
