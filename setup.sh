#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# ai-life-journal setup script
# One-command setup: prerequisites, RAG server, git hooks
# Supports: Linux, macOS, WSL2
# Android: use proot-distro (see README.md)
# ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RAG_DIR="$REPO_ROOT/rag-mcp"
VENV_DIR="$RAG_DIR/.venv"

# Package manager: "uv" or "pip"
PKG_MANAGER=""

# ── Android/Termux check ──
# Direct Termux is not supported due to Bionic libc incompatibility.
# proot-distro provides a full glibc Linux environment where everything works.
if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
    echo "=== Android (Termux) detected ==="
    echo ""
    echo "Direct Termux execution is not supported."
    echo "Please use proot-distro for a full Linux environment:"
    echo ""
    echo "  # Install proot-distro (one-time)"
    echo "  pkg install proot-distro"
    echo "  proot-distro install ubuntu"
    echo ""
    echo "  # Enter Ubuntu environment"
    echo "  proot-distro login ubuntu"
    echo ""
    echo "  # Inside Ubuntu: install prerequisites"
    echo "  apt update && apt install -y git python3 curl"
    echo ""
    echo "  # Then run setup normally"
    echo "  git clone https://github.com/chai0204/ai-life-journal"
    echo "  cd ai-life-journal"
    echo "  ./setup.sh"
    echo ""
    exit 1
fi

# Platform detection
IS_WSL2=false
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    IS_WSL2=true
fi

echo "=== ai-life-journal setup ==="
echo "Repository root: $REPO_ROOT"
if $IS_WSL2; then
    echo "Platform: WSL2"
else
    echo "Platform: $(uname -s)"
fi
echo ""

# ── 1. Check prerequisites ──

echo "[1/7] Checking prerequisites..."

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

# ── 2. Install uv (with pip fallback) ──

echo ""
echo "[2/7] Setting up Python package manager..."

if command -v uv &>/dev/null; then
    PKG_MANAGER="uv"
    echo "  uv: already installed ($(uv --version))"
else
    echo "  uv not found. Attempting to install..."
    if curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh 2>&1; then
        export PATH="$HOME/.local/bin:$PATH"
        if command -v uv &>/dev/null; then
            PKG_MANAGER="uv"
            echo "  uv: installed ($(uv --version))"
        fi
    fi

    if [ -z "$PKG_MANAGER" ]; then
        echo "  uv installation not available on this platform."
        echo "  Falling back to pip + venv..."
        if python3 -m pip --version &>/dev/null; then
            PKG_MANAGER="pip"
            echo "  pip: $(python3 -m pip --version)"
        else
            echo "ERROR: Neither uv nor pip is available."
            exit 1
        fi
    fi
fi

echo "  Using: $PKG_MANAGER"

# ── 3. Install Ollama ──

echo ""
echo "[3/7] Checking Ollama..."

OLLAMA_URL="${OLLAMA_URL:-}"

if $IS_WSL2; then
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
else
    # Linux / macOS
    if [ -z "$OLLAMA_URL" ]; then
        if command -v ollama &>/dev/null; then
            echo "  Ollama: already installed"
            OLLAMA_URL="http://localhost:11434"
        else
            echo "  Installing Ollama..."
            if curl -fsSL https://ollama.com/install.sh 2>/dev/null | sh 2>&1; then
                if command -v ollama &>/dev/null; then
                    echo "  Ollama: installed"
                    OLLAMA_URL="http://localhost:11434"
                fi
            fi
            if [ -z "$OLLAMA_URL" ]; then
                echo "  WARNING: Ollama installation failed."
                echo "  You can set OLLAMA_URL to point to a remote Ollama server."
                echo "  Example: export OLLAMA_URL=http://YOUR_SERVER:11434"
            fi
        fi
    fi
fi

# ── 4. Ensure Ollama runner & start service ──

echo ""
echo "[4/7] Checking Ollama service..."

# Ollama 0.17+ spawns a subprocess called 'serve' for model inference.
# In some environments (proot-distro, containers), this binary is not in PATH.
# Fix: create a symlink 'serve' -> 'ollama' so the runner can find itself.
ensure_ollama_runner() {
    command -v serve &>/dev/null && return 0
    local ollama_bin
    ollama_bin="$(command -v ollama 2>/dev/null)" || return 1
    if ln -sf "$ollama_bin" /usr/local/bin/serve 2>/dev/null; then
        echo "  Created runner symlink: /usr/local/bin/serve -> $ollama_bin"
    elif mkdir -p "$HOME/.local/bin" 2>/dev/null && ln -sf "$ollama_bin" "$HOME/.local/bin/serve" 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        echo "  Created runner symlink: $HOME/.local/bin/serve -> $ollama_bin"
    else
        echo "  WARNING: Could not create 'serve' symlink. Ollama model runner may fail."
        return 1
    fi
}

if [ -n "$OLLAMA_URL" ]; then
    # Ensure runner symlink before starting
    if command -v ollama &>/dev/null; then
        ensure_ollama_runner
    fi

    if curl -sf --connect-timeout 3 "$OLLAMA_URL/api/tags" &>/dev/null; then
        echo "  Ollama is running at $OLLAMA_URL"
    else
        if command -v ollama &>/dev/null; then
            echo "  Starting Ollama..."
            ollama serve &>/dev/null &
            # Wait up to 10 seconds for startup
            for i in $(seq 1 10); do
                if curl -sf --connect-timeout 1 "$OLLAMA_URL/api/tags" &>/dev/null; then
                    echo "  Ollama started successfully"
                    break
                fi
                sleep 1
            done
            if ! curl -sf --connect-timeout 1 "$OLLAMA_URL/api/tags" &>/dev/null; then
                echo "  WARNING: Ollama did not start. Try running 'ollama serve' manually."
            fi
        else
            echo "  WARNING: Cannot reach Ollama at $OLLAMA_URL"
        fi
    fi
else
    echo "  Skipped (Ollama not configured)"
fi

# ── 5. Generate .mcp.json & install git hooks ──

echo ""
echo "[5/7] Generating .mcp.json..."

if [ -f "$REPO_ROOT/.mcp.json" ]; then
    echo "  .mcp.json already exists, skipping (delete it to regenerate)"
else
    sed "s|__REPO_ROOT__|$REPO_ROOT|g" "$REPO_ROOT/.mcp.json.template" > "$REPO_ROOT/.mcp.json"
    echo "  Generated .mcp.json"
fi

echo ""
echo "[6/7] Installing git hooks..."

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
echo "[7/7] Installing Python dependencies..."

install_with_pip() {
    # Create venv if needed
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
    fi
    "$VENV_DIR/bin/pip" install --upgrade pip 2>&1 | tail -1
    "$VENV_DIR/bin/pip" install -e "$RAG_DIR" 2>&1 | tail -1
}

if [ "$PKG_MANAGER" = "uv" ]; then
    (cd "$RAG_DIR" && uv sync)
else
    install_with_pip
fi
echo "  Dependencies installed ($PKG_MANAGER)"

# ── 8. Pull embedding model & build index ──

echo ""
echo "Setting up embedding model and index..."

if [ -n "$OLLAMA_URL" ] && curl -sf --connect-timeout 3 "$OLLAMA_URL/api/tags" &>/dev/null; then
    echo "  Pulling bge-m3 embedding model (this may take a few minutes on first run)..."
    if $IS_WSL2 && [ "$OLLAMA_URL" != "http://localhost:11434" ]; then
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

    # Verify embed API end-to-end (catches runner issues early)
    echo "  Verifying embedding API..."
    EMBED_RESULT=$(curl -sf --max-time 30 "$OLLAMA_URL/api/embed" \
        -d '{"model":"bge-m3","input":"test"}' 2>&1)
    if echo "$EMBED_RESULT" | grep -q '"embeddings"'; then
        echo "  Embedding API OK"
    else
        echo "  WARNING: Embedding API test failed."
        echo "  Response: $EMBED_RESULT"
        echo "  RAG semantic search may not work until this is resolved."
    fi

    # Build initial index
    echo "  Building initial RAG index..."
    export OLLAMA_URL
    export LIFE_REPO_PATH="$REPO_ROOT"
    if [ "$PKG_MANAGER" = "uv" ]; then
        (cd "$REPO_ROOT" && uv --directory "$RAG_DIR" run life-rag-index --full) || {
            echo "  WARNING: Initial index build failed (this is OK for an empty repo)"
        }
    else
        "$VENV_DIR/bin/life-rag-index" --full || {
            echo "  WARNING: Initial index build failed (this is OK for an empty repo)"
        }
    fi
else
    echo "  Skipped (Ollama not reachable)."
    if [ -z "$OLLAMA_URL" ]; then
        echo "  To enable RAG search, set OLLAMA_URL and re-run setup.sh:"
        echo "    export OLLAMA_URL=http://YOUR_SERVER:11434"
        echo "    ./setup.sh"
    else
        echo "  Make sure Ollama is running at $OLLAMA_URL and re-run setup.sh."
    fi
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
