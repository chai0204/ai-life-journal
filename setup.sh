#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# ai-life-journal setup script
# One-command setup: prerequisites, RAG server, git hooks
# Supports: Linux, macOS, WSL2, Termux (Android)
# ──────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
RAG_DIR="$REPO_ROOT/rag-mcp"
VENV_DIR="$RAG_DIR/.venv"

# Package manager: "uv" or "pip"
PKG_MANAGER=""

# Platform detection
IS_ANDROID=false
IS_WSL2=false
if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
    IS_ANDROID=true
elif [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    IS_WSL2=true
fi

echo "=== ai-life-journal setup ==="
echo "Repository root: $REPO_ROOT"
if $IS_ANDROID; then
    echo "Platform: Android (Termux)"
elif $IS_WSL2; then
    echo "Platform: WSL2"
else
    echo "Platform: $(uname -s)"
fi
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

# ── 2. Install uv (with pip fallback) ──

echo ""
echo "[2/8] Setting up Python package manager..."

if command -v uv &>/dev/null; then
    PKG_MANAGER="uv"
    echo "  uv: already installed ($(uv --version))"
elif $IS_ANDROID; then
    # uv has no Android binary; go straight to pip
    PKG_MANAGER="pip"
    echo "  uv: not available on Android, using pip"
    echo "  pip: $(python3 -m pip --version 2>/dev/null || echo 'not found')"
    if ! python3 -m pip --version &>/dev/null; then
        echo "ERROR: pip is not available. Run: pkg install python-pip"
        exit 1
    fi
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
echo "[3/8] Checking Ollama..."

OLLAMA_URL="${OLLAMA_URL:-}"

install_ollama_binary() {
    # Download Ollama binary directly from ollama.com.
    # Used on Termux where the official install script requires root.
    local INSTALL_DIR="$HOME/.local/bin"
    local ARCH
    ARCH=$(uname -m)

    # Map to Ollama release names
    case "$ARCH" in
        aarch64|arm64) ARCH="arm64" ;;
        x86_64|amd64)  ARCH="amd64" ;;
        *)
            echo "  WARNING: Unsupported architecture for Ollama: $ARCH"
            return 1
            ;;
    esac

    mkdir -p "$INSTALL_DIR"
    echo "  Downloading ollama-linux-${ARCH}..."
    if curl -fL -o "$INSTALL_DIR/ollama" \
        "https://ollama.com/download/ollama-linux-${ARCH}" 2>&1; then
        chmod +x "$INSTALL_DIR/ollama"
        export PATH="$INSTALL_DIR:$PATH"
        if command -v ollama &>/dev/null; then
            echo "  Ollama: installed to $INSTALL_DIR/ollama"
            return 0
        fi
    fi
    echo "  WARNING: Ollama binary download failed."
    return 1
}

if $IS_ANDROID; then
    # Termux: use pkg (Termux package manager) first, fall back to direct binary download
    if command -v ollama &>/dev/null; then
        echo "  Ollama: already installed"
        OLLAMA_URL="http://localhost:11434"
    else
        echo "  Installing Ollama for Termux..."
        if command -v pkg &>/dev/null && pkg install -y ollama 2>&1; then
            if command -v ollama &>/dev/null; then
                echo "  Ollama: installed via pkg"
                OLLAMA_URL="http://localhost:11434"
            fi
        fi
        # Fallback: direct binary download
        if [ -z "$OLLAMA_URL" ]; then
            echo "  pkg install failed, trying direct binary download..."
            if install_ollama_binary; then
                OLLAMA_URL="http://localhost:11434"
            else
                echo "  Ollama could not be installed. RAG search will be unavailable."
                echo "  TIP: Try manually: pkg install ollama"
            fi
        fi
    fi
elif $IS_WSL2; then
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

# ── 4. Start Ollama service ──

echo ""
echo "[4/8] Checking Ollama service..."

if [ -n "$OLLAMA_URL" ]; then
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

install_with_pip() {
    # Create venv if needed
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
    fi
    "$VENV_DIR/bin/pip" install --upgrade pip 2>&1 | tail -1

    # On Android/Termux, manylinux .so files are incompatible with Bionic libc.
    # Strategy: build native extensions from source using Rust/C compilers,
    # except sqlite-vec (no source dist, but its simple C .so works via manylinux).
    if $IS_ANDROID; then
        # Install build tools for native extensions (Rust for pydantic-core etc.)
        echo "  Installing build tools (rust, binutils)..."
        pkg install -y rust binutils 2>&1 | tail -3

        # Set Android API level for maturin (Rust build tool)
        export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo "24")
        echo "  Android API level: $ANDROID_API_LEVEL"

        # Install dependencies — native extensions build from source
        echo "  Installing dependencies (building native extensions from source)..."
        echo "  NOTE: First run may take 10+ minutes for Rust compilation."
        "$VENV_DIR/bin/pip" install httpx "mcp>=1.2.0" pyyaml 2>&1

        # sqlite-vec: no source distribution available, but its simple C extension
        # works via manylinux wheel on Termux (confirmed working)
        echo "  Installing sqlite-vec via manylinux wheel..."
        TMPDIR_WHL=$(mktemp -d)
        PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')
        SITE_PACKAGES=$("$VENV_DIR/bin/python3" -c "import site; print(site.getsitepackages()[0])")

        "$VENV_DIR/bin/pip" download sqlite-vec \
            --only-binary=:all: \
            --platform manylinux_2_17_aarch64 \
            --python-version "$PY_VER" \
            -d "$TMPDIR_WHL" 2>&1 | tail -1

        for whl in "$TMPDIR_WHL"/*.whl; do
            [ -f "$whl" ] || continue
            unzip -o "$whl" -d "$SITE_PACKAGES" >/dev/null
        done
        rm -rf "$TMPDIR_WHL"
        echo "  sqlite-vec: installed"

        # Install the project itself
        "$VENV_DIR/bin/pip" install --no-deps -e "$RAG_DIR" 2>&1 | tail -1
    else
        "$VENV_DIR/bin/pip" install -e "$RAG_DIR" 2>&1 | tail -1
    fi
}

if [ "$PKG_MANAGER" = "uv" ]; then
    (cd "$RAG_DIR" && uv sync)
else
    install_with_pip
fi
echo "  Dependencies installed ($PKG_MANAGER)"

# ── 8. Pull embedding model & build index ──

echo ""
echo "[8/8] Setting up embedding model and index..."

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
