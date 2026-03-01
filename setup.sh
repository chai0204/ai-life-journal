#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# ai-life-journal setup script
# One-command setup: prerequisites, RAG server, git hooks
# ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RAG_DIR="$REPO_ROOT/rag-mcp"

echo "=== ai-life-journal setup ==="
echo "Repository root: $REPO_ROOT"
echo ""

# ── 1. Check prerequisites ──

echo "[1/8] Checking prerequisites..."

# git
if ! command -v git &>/dev/null; then
    echo "ERROR: git is not installed. Please install git first."
    exit 1
fi
echo "  git: $(git --version)"

# python 3.12+
if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
    if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]; }; then
        echo "ERROR: Python 3.12+ is required (found $PY_VERSION)"
        exit 1
    fi
    echo "  python3: $PY_VERSION"
else
    echo "ERROR: python3 is not installed. Please install Python 3.12+."
    exit 1
fi

# ── 2. Install uv ──

echo ""
echo "[2/8] Checking uv..."

if command -v uv &>/dev/null; then
    echo "  uv: already installed ($(uv --version))"
else
    echo "  Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Source the updated PATH
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv &>/dev/null; then
        echo "  uv: installed ($(uv --version))"
    else
        echo "ERROR: uv installation failed."
        exit 1
    fi
fi

# ── 3. Install Ollama ──

echo ""
echo "[3/8] Checking Ollama..."

OLLAMA_URL=""

# WSL2 detection: check if Windows-side Ollama is reachable
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    WIN_HOST=$(ip route show default | awk '{print $3}')
    echo "  WSL2 detected. Checking Windows host ($WIN_HOST) for Ollama..."
    if curl -sf "http://${WIN_HOST}:11434/api/tags" &>/dev/null; then
        OLLAMA_URL="http://${WIN_HOST}:11434"
        echo "  Ollama found on Windows host: $OLLAMA_URL"
    else
        echo "  Ollama not found on Windows host."
        echo "  TIP: Install Ollama on Windows (https://ollama.com) and restart setup."
        echo "  Alternatively, install Ollama in WSL2 directly."
    fi
fi

if [ -z "$OLLAMA_URL" ]; then
    if command -v ollama &>/dev/null; then
        echo "  Ollama: already installed"
        OLLAMA_URL="http://localhost:11434"
    else
        echo "  Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        if command -v ollama &>/dev/null; then
            echo "  Ollama: installed"
            OLLAMA_URL="http://localhost:11434"
        else
            echo "WARNING: Ollama installation failed. You can install it manually later."
            echo "         RAG search will not work without Ollama."
        fi
    fi
fi

# ── 4. Start Ollama service ──

echo ""
echo "[4/8] Checking Ollama service..."

if [ -n "$OLLAMA_URL" ]; then
    if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
        echo "  Ollama is running at $OLLAMA_URL"
    else
        echo "  Starting Ollama..."
        ollama serve &>/dev/null &
        sleep 2
        if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
            echo "  Ollama started successfully"
        else
            echo "WARNING: Could not start Ollama. Start it manually with: ollama serve"
        fi
    fi
else
    echo "  Skipped (Ollama not available)"
fi

# ── 5. Generate .mcp.json ──

echo ""
echo "[5/8] Generating .mcp.json..."

if [ -f "$REPO_ROOT/.mcp.json" ]; then
    echo "  .mcp.json already exists, skipping (delete it to regenerate)"
else
    sed "s|__REPO_ROOT__|$REPO_ROOT|g" "$REPO_ROOT/.mcp.json.template" > "$REPO_ROOT/.mcp.json"
    echo "  Generated .mcp.json"
fi

# ── 6. Install git hooks ──

echo ""
echo "[6/8] Installing git hooks..."

HOOKS_DIR="$REPO_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    cp "$REPO_ROOT/scripts/post-commit" "$HOOKS_DIR/post-commit"
    chmod +x "$HOOKS_DIR/post-commit"
    echo "  Installed post-commit hook"
else
    echo "  WARNING: .git/hooks not found. Run 'git init' first."
fi

# ── 7. Install Python dependencies ──

echo ""
echo "[7/8] Installing Python dependencies..."

(cd "$RAG_DIR" && uv sync)
echo "  Dependencies installed"

# ── 8. Pull embedding model & build index ──

echo ""
echo "[8/8] Setting up embedding model and index..."

if [ -n "$OLLAMA_URL" ]; then
    echo "  Pulling bge-m3 embedding model (this may take a few minutes on first run)..."
    if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] && [ "$OLLAMA_URL" != "http://localhost:11434" ]; then
        # WSL2 with Windows Ollama: use API to pull
        echo "  Using Windows Ollama at $OLLAMA_URL"
        curl -sf "$OLLAMA_URL/api/pull" -d '{"name":"bge-m3"}' | while IFS= read -r line; do
            status=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
            if [ -n "$status" ]; then
                printf "\r  %s" "$status"
            fi
        done
        echo ""
    else
        ollama pull bge-m3
    fi

    # Verify Ollama connectivity
    echo "  Verifying Ollama connection..."
    if curl -sf "$OLLAMA_URL/api/tags" &>/dev/null; then
        echo "  Ollama connection OK"
    else
        echo "  WARNING: Cannot reach Ollama at $OLLAMA_URL"
    fi

    # Build initial index
    echo "  Building initial RAG index..."
    export OLLAMA_URL
    export LIFE_REPO_PATH="$REPO_ROOT"
    (cd "$REPO_ROOT" && uv --directory "$RAG_DIR" run life-rag-index --full) || {
        echo "  WARNING: Initial index build failed (this is OK for an empty repo)"
    }
else
    echo "  Skipped (Ollama not available). Run setup.sh again after installing Ollama."
fi

# ── Done ──

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Fill in profile/about.md with your information"
echo "  2. Open Claude Code in this directory"
echo "  3. Start chatting! Use /journal to record your day"
echo ""
echo "Available commands:"
echo "  /journal   - Record daily events"
echo "  /recall    - AI-guided daily reflection"
echo "  /record    - Save conversation to journal + knowledge"
echo "  /distill   - Extract knowledge from journals"
echo "  /status    - View progress summary"
echo ""
