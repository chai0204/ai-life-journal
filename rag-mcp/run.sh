#!/bin/bash
# Wrapper script to launch life-rag-mcp
# On WSL2, automatically detects Windows host IP for Ollama

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect Ollama URL on WSL2
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    WIN_HOST=$(ip route show default | awk '{print $3}')
    export OLLAMA_URL="${OLLAMA_URL:-http://${WIN_HOST}:11434}"
fi

export LIFE_REPO_PATH="${LIFE_REPO_PATH:-$REPO_ROOT}"

UV="$(command -v uv)"
if [ -z "$UV" ]; then
    echo "Error: uv not found. Run setup.sh first." >&2
    exit 1
fi

exec "$UV" --directory "$SCRIPT_DIR" run life-rag-mcp
