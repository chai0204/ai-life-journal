#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# ai-life-journal setup script
# One-command setup: all dependencies, RAG server, git hooks
# Supports: Linux, macOS, WSL2, proot-distro (Android)
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
    echo "  # Inside Ubuntu: install minimum prerequisites"
    echo "  apt update && apt install -y git curl ca-certificates"
    echo ""
    echo "  # Clone and run setup"
    echo "  git clone https://github.com/chai0204/ai-life-journal"
    echo "  cd ai-life-journal"
    echo "  ./setup.sh"
    echo ""
    exit 1
fi

# Platform detection
IS_WSL2=false
IS_PROOT=false
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    IS_WSL2=true
fi
# proot-distro: the process is traced by PRoot (TracerPid > 0)
if [ -f /proc/self/status ] && grep -q "TracerPid:[[:space:]]*[1-9]" /proc/self/status 2>/dev/null; then
    IS_PROOT=true
fi

echo "=== ai-life-journal setup ==="
echo "Repository root: $REPO_ROOT"
if $IS_PROOT; then
    echo "Platform: proot-distro ($(uname -s))"
elif $IS_WSL2; then
    echo "Platform: WSL2"
else
    echo "Platform: $(uname -s)"
fi
echo ""

# ── 1. Install system packages ──

echo "[1/9] Checking system packages..."

if $IS_PROOT; then
    # proot-distro (Ubuntu): auto-install all system dependencies
    echo "  Updating package list..."
    apt update -qq 2>/dev/null

    # Python 3
    if ! command -v python3 &>/dev/null; then
        echo "  Installing Python 3..."
        apt install -y python3 python3-venv 2>/dev/null
    fi

    # Node.js (for Claude Code)
    if ! command -v node &>/dev/null; then
        echo "  Installing Node.js 22.x..."
        curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh 2>/dev/null
        rm -f /tmp/nodesource_setup.sh
        apt install -y nodejs 2>/dev/null
    fi

    echo "  System packages: OK"
else
    # Other platforms: check prerequisites and report missing
    MISSING=""
    if ! command -v python3 &>/dev/null; then
        MISSING="${MISSING} python3"
    fi
    if ! command -v node &>/dev/null; then
        MISSING="${MISSING} node"
    fi

    if [ -n "$MISSING" ]; then
        echo "  Missing:${MISSING}"
        if [ "$(uname -s)" = "Darwin" ]; then
            echo "  Install with: brew install python node"
        elif command -v apt &>/dev/null; then
            echo "  Install with: sudo apt install -y python3 nodejs"
        fi
        echo ""
        echo "  Please install the missing packages and re-run ./setup.sh"
        exit 1
    fi
    echo "  All prerequisites found"
fi

# Version checks
echo "  git: $(git --version)"

PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]; }; then
    echo "  ERROR: Python 3.12+ required (found $PY_VERSION)"
    exit 1
fi
echo "  python3: $PY_VERSION"
echo "  node: $(node --version)"

# ── 2. Install uv (Python package manager) ──

echo ""
echo "[2/9] Setting up Python package manager..."

if command -v uv &>/dev/null; then
    PKG_MANAGER="uv"
    echo "  uv: already installed ($(uv --version))"
else
    echo "  Installing uv..."
    if curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh 2>&1; then
        export PATH="$HOME/.local/bin:$PATH"
        if command -v uv &>/dev/null; then
            PKG_MANAGER="uv"
            echo "  uv: installed ($(uv --version))"
        fi
    fi

    if [ -z "$PKG_MANAGER" ]; then
        echo "  uv installation failed. Falling back to pip..."
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
echo "[3/9] Installing Ollama..."

OLLAMA_URL="${OLLAMA_URL:-}"

if [ -n "$OLLAMA_URL" ]; then
    echo "  OLLAMA_URL is set: $OLLAMA_URL"
elif command -v ollama &>/dev/null; then
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
        if $IS_WSL2; then
            echo "  TIP: Install Ollama on Windows (https://ollama.com) or inside WSL2."
        else
            echo "  You can set OLLAMA_URL to point to a remote Ollama server."
            echo "  Example: export OLLAMA_URL=http://YOUR_SERVER:11434"
        fi
    fi
fi

# WSL2 fallback: check Windows host if local Ollama not available
if $IS_WSL2 && [ -z "$OLLAMA_URL" ]; then
    WIN_HOST=$(ip route show default | awk '{print $3}')
    if curl -sf --connect-timeout 3 "http://${WIN_HOST}:11434/api/tags" &>/dev/null; then
        OLLAMA_URL="http://${WIN_HOST}:11434"
        echo "  Ollama found on Windows host: $OLLAMA_URL"
    fi
fi

# ── 4. Install Claude Code ──

echo ""
echo "[4/9] Installing Claude Code..."

if command -v claude &>/dev/null; then
    echo "  Claude Code: already installed"
else
    if command -v npm &>/dev/null; then
        echo "  Installing via npm..."
        npm install -g @anthropic-ai/claude-code 2>&1 | tail -5
        if command -v claude &>/dev/null; then
            echo "  Claude Code: installed"
        else
            echo "  WARNING: Claude Code installation may have failed."
            echo "  Try manually: npm install -g @anthropic-ai/claude-code"
        fi
    else
        echo "  WARNING: npm not found. Install Node.js first, then:"
        echo "    npm install -g @anthropic-ai/claude-code"
    fi
fi

# ── 5. Ensure Ollama runner & start service ──

echo ""
echo "[5/9] Starting Ollama service..."

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
            # Wait up to 15 seconds for startup
            for i in $(seq 1 15); do
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

    # Ensure Ollama key exists (required for ollama pull).
    # ollama serve generates the key on first startup, but it may take a moment.
    OLLAMA_KEY="$HOME/.ollama/id_ed25519"
    if [ ! -f "$OLLAMA_KEY" ]; then
        echo "  Waiting for Ollama key generation..."
        for i in $(seq 1 10); do
            [ -f "$OLLAMA_KEY" ] && break
            sleep 1
        done
        if [ ! -f "$OLLAMA_KEY" ]; then
            echo "  Key not found. Triggering generation..."
            # Briefly start ollama serve to generate the key (stops if port already in use)
            ollama serve &>/dev/null &
            OLLAMA_KEYGEN_PID=$!
            sleep 3
            kill "$OLLAMA_KEYGEN_PID" 2>/dev/null || true
        fi
    fi
else
    echo "  Skipped (Ollama not configured)"
fi

# ── 6. Generate .mcp.json ──

echo ""
echo "[6/9] Generating .mcp.json..."

if [ -f "$REPO_ROOT/.mcp.json" ]; then
    echo "  .mcp.json already exists, skipping (delete it to regenerate)"
else
    sed "s|__REPO_ROOT__|$REPO_ROOT|g" "$REPO_ROOT/.mcp.json.template" > "$REPO_ROOT/.mcp.json"
    echo "  Generated .mcp.json"
fi

# ── 7. Install git hooks ──

echo ""
echo "[7/9] Installing git hooks..."

HOOKS_DIR="$REPO_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    cp "$REPO_ROOT/scripts/post-commit" "$HOOKS_DIR/post-commit"
    chmod +x "$HOOKS_DIR/post-commit"
    echo "  Installed post-commit hook"
else
    echo "  WARNING: .git/hooks not found. Run 'git init' first."
fi

# ── 8. Install Python dependencies ──

echo ""
echo "[8/9] Installing Python dependencies..."

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

# ── 9. Pull embedding model & build index ──

echo ""
echo "[9/9] Setting up embedding model and index..."

if [ -n "$OLLAMA_URL" ] && curl -sf --connect-timeout 3 "$OLLAMA_URL/api/tags" &>/dev/null; then
    echo "  Pulling bge-m3 embedding model (this may take a few minutes on first run)..."
    if command -v ollama &>/dev/null && [ "$OLLAMA_URL" = "http://localhost:11434" ]; then
        # Local Ollama: use CLI directly
        ollama pull bge-m3
    else
        # Remote Ollama: use API
        echo "  Using Ollama API at $OLLAMA_URL"
        curl -sf "$OLLAMA_URL/api/pull" -d '{"name":"bge-m3"}' | while IFS= read -r line; do
            status=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
            if [ -n "$status" ]; then
                printf "\r  %s" "$status"
            fi
        done
        echo ""
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
        echo "  To enable RAG search, install Ollama and re-run ./setup.sh"
    else
        echo "  Make sure Ollama is running at $OLLAMA_URL and re-run ./setup.sh"
    fi
fi

# ── 10. GitHub integration (optional) ──

echo ""
echo "=== Core setup complete! ==="
echo ""

# Ask user about GitHub integration
SETUP_GITHUB=false
echo "GitHub に接続しますか？（任意）"
echo "ブラウザから記録を閲覧・バックアップできるようになります。"
echo "GitHub アカウントが必要です（https://github.com/signup）"
echo ""
printf "[y/N]: "
read -r GITHUB_ANSWER </dev/tty || GITHUB_ANSWER=""
case "$GITHUB_ANSWER" in
    [yY]|[yY][eE][sS]) SETUP_GITHUB=true ;;
esac

if $SETUP_GITHUB; then
    echo ""
    echo "[10] Connecting to GitHub..."

    # Install gh CLI if needed
    if ! command -v gh &>/dev/null; then
        echo "  Installing GitHub CLI..."
        if $IS_PROOT || command -v apt &>/dev/null; then
            # Debian/Ubuntu: use GitHub's official repo
            (
                apt install -y -qq software-properties-common 2>/dev/null || true
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                    > /etc/apt/sources.list.d/github-cli.list
                apt update -qq 2>/dev/null
                apt install -y -qq gh 2>/dev/null
            )
        elif [ "$(uname -s)" = "Darwin" ] && command -v brew &>/dev/null; then
            brew install gh
        fi

        if ! command -v gh &>/dev/null; then
            echo "  WARNING: GitHub CLI installation failed."
            echo "  Install manually: https://cli.github.com/"
            echo "  Then run:"
            echo "    gh auth login --web"
            echo "    gh repo create ai-life-journal --private --source=. --push"
            SETUP_GITHUB=false
        else
            echo "  GitHub CLI: installed"
        fi
    else
        echo "  GitHub CLI: already installed"
    fi
fi

if $SETUP_GITHUB; then
    # Authenticate
    if ! gh auth status &>/dev/null 2>&1; then
        echo ""
        echo "  ブラウザで GitHub にログインします。"
        echo "  表示される URL を開き、コードを入力してください。"
        echo ""
        gh auth login --web --git-protocol https < /dev/tty
    else
        echo "  GitHub: already authenticated"
    fi

    # Create private repo and push
    if gh auth status &>/dev/null 2>&1; then
        GH_USER=$(gh api user -q .login 2>/dev/null)
        REPO_NAME="ai-life-journal"

        echo ""
        echo "  Creating private repository: $GH_USER/$REPO_NAME"

        # Check if repo already exists
        if gh repo view "$GH_USER/$REPO_NAME" &>/dev/null 2>&1; then
            echo "  Repository already exists. Updating remote..."
            git remote set-url origin "https://github.com/$GH_USER/$REPO_NAME.git" 2>/dev/null \
                || git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git" 2>/dev/null
        else
            # Create new private repo
            gh repo create "$REPO_NAME" --private --source=. --remote=origin --push 2>&1 \
                && echo "  Repository created and pushed!" \
                || {
                    echo "  WARNING: Repository creation failed."
                    echo "  Try manually: gh repo create $REPO_NAME --private --source=. --push"
                }
        fi

        # Ensure latest is pushed
        if git remote get-url origin &>/dev/null 2>&1; then
            git push -u origin "$(git branch --show-current)" 2>/dev/null && \
                echo "  Pushed to: https://github.com/$GH_USER/$REPO_NAME"
        fi
    else
        echo "  WARNING: GitHub authentication failed."
        echo "  Try manually: gh auth login --web"
    fi
fi

# ── Done ──

echo ""
echo "=== All done! ==="
echo ""
echo "Next steps:"
echo "  1. Fill in profile/about.md with your information"
if ! command -v claude &>/dev/null; then
    echo "  2. Install Claude Code: npm install -g @anthropic-ai/claude-code"
    echo "  3. Run 'claude' in this directory"
else
    echo "  2. Run 'claude' in this directory"
fi
echo ""
echo "Available commands:"
echo "  /journal   - Record daily events"
echo "  /recall    - AI-guided daily reflection"
echo "  /record    - Save conversation to journal + knowledge"
echo "  /distill   - Extract knowledge from journals"
echo "  /status    - View progress summary"
if ! $SETUP_GITHUB; then
    echo ""
    echo "GitHub 連携を後から設定する場合:"
    echo "  gh auth login --web"
    echo "  gh repo create ai-life-journal --private --source=. --push"
fi
echo ""
