#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────
# ai-life-journal setup script for Windows
# One-command setup: all dependencies, RAG server, git hooks
# Supports: Windows 10/11 (PowerShell 5.1+)
# ──────────────────────────────────────────────

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RagDir = Join-Path $RepoRoot "rag-mcp"
$VenvDir = Join-Path $RagDir ".venv"

# Package manager: "uv" or "pip"
$PkgManager = ""

Write-Host "=== ai-life-journal setup (Windows) ===" -ForegroundColor Cyan
Write-Host "Repository root: $RepoRoot"
Write-Host "Platform: Windows"
Write-Host ""

# ── 1. Check system packages ──

Write-Host "[1/9] Checking system packages..." -ForegroundColor Yellow

$Missing = @()

# Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $Missing += "git"
}

# Python 3.12+
$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = "python"
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $pythonCmd = "python3"
}

if (-not $pythonCmd) {
    $Missing += "python"
} else {
    $pyVersionStr = & $pythonCmd --version 2>&1
    if ($pyVersionStr -match "Python (\d+)\.(\d+)") {
        $pyMajor = [int]$Matches[1]
        $pyMinor = [int]$Matches[2]
        if ($pyMajor -lt 3 -or ($pyMajor -eq 3 -and $pyMinor -lt 12)) {
            Write-Host "  ERROR: Python 3.12+ required (found $pyVersionStr)" -ForegroundColor Red
            exit 1
        }
    }
}

# Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    $Missing += "node"
}

if ($Missing.Count -gt 0) {
    Write-Host "  Missing: $($Missing -join ', ')" -ForegroundColor Red
    Write-Host ""
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Install with winget:" -ForegroundColor Yellow
        foreach ($pkg in $Missing) {
            switch ($pkg) {
                "git"    { Write-Host "    winget install Git.Git" }
                "python" { Write-Host "    winget install Python.Python.3.12" }
                "node"   { Write-Host "    winget install OpenJS.NodeJS.LTS" }
            }
        }
        Write-Host ""
    }
    Write-Host "  Or download from:" -ForegroundColor Yellow
    foreach ($pkg in $Missing) {
        switch ($pkg) {
            "git"    { Write-Host "    https://git-scm.com/download/win" }
            "python" { Write-Host "    https://www.python.org/downloads/" }
            "node"   { Write-Host "    https://nodejs.org/" }
        }
    }
    Write-Host ""
    Write-Host "  Please install the missing packages, restart PowerShell, and re-run setup.ps1" -ForegroundColor Red
    exit 1
}

Write-Host "  git: $(git --version)"
Write-Host "  python: $(& $pythonCmd --version 2>&1)"
Write-Host "  node: $(node --version)"
Write-Host "  All prerequisites found"

# ── 2. Install uv (Python package manager) ──

Write-Host ""
Write-Host "[2/9] Setting up Python package manager..." -ForegroundColor Yellow

if (Get-Command uv -ErrorAction SilentlyContinue) {
    $PkgManager = "uv"
    Write-Host "  uv: already installed ($(uv --version))"
} else {
    Write-Host "  Installing uv..."
    try {
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        # Refresh PATH to pick up newly installed uv
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if (Get-Command uv -ErrorAction SilentlyContinue) {
            $PkgManager = "uv"
            Write-Host "  uv: installed ($(uv --version))"
        }
    } catch {
        Write-Host "  uv installation failed." -ForegroundColor Yellow
    }

    if (-not $PkgManager) {
        Write-Host "  Falling back to pip..."
        try {
            & $pythonCmd -m pip --version 2>&1 | Out-Null
            $PkgManager = "pip"
            Write-Host "  pip: $(& $pythonCmd -m pip --version 2>&1)"
        } catch {
            Write-Host "ERROR: Neither uv nor pip is available." -ForegroundColor Red
            exit 1
        }
    }
}
Write-Host "  Using: $PkgManager"

# ── 3. Install Ollama ──

Write-Host ""
Write-Host "[3/9] Installing Ollama..." -ForegroundColor Yellow

$OllamaUrl = $env:OLLAMA_URL

if ($OllamaUrl) {
    Write-Host "  OLLAMA_URL is set: $OllamaUrl"
} elseif (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Host "  Ollama: already installed"
    $OllamaUrl = "http://localhost:11434"
} else {
    # Try winget install
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Installing via winget..."
        try {
            winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            if (Get-Command ollama -ErrorAction SilentlyContinue) {
                $OllamaUrl = "http://localhost:11434"
                Write-Host "  Ollama: installed"
            }
        } catch {
            Write-Host "  winget install failed." -ForegroundColor Yellow
        }
    }

    if (-not $OllamaUrl) {
        Write-Host "  WARNING: Ollama not installed." -ForegroundColor Yellow
        Write-Host "  Install manually:"
        Write-Host "    1. winget install Ollama.Ollama"
        Write-Host "    2. Or download from https://ollama.com/download/windows"
        Write-Host "  You can also set OLLAMA_URL to point to a remote server."
    }
}

# ── 4. Install Claude Code ──

Write-Host ""
Write-Host "[4/9] Installing Claude Code..." -ForegroundColor Yellow

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "  Claude Code: already installed"
} else {
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "  Installing via npm..."
        npm install -g @anthropic-ai/claude-code 2>&1 | Select-Object -Last 5
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            Write-Host "  Claude Code: installed"
        } else {
            Write-Host "  WARNING: Claude Code installation may have failed." -ForegroundColor Yellow
            Write-Host "  Try manually: npm install -g @anthropic-ai/claude-code"
        }
    } else {
        Write-Host "  WARNING: npm not found. Install Node.js first, then:" -ForegroundColor Yellow
        Write-Host "    npm install -g @anthropic-ai/claude-code"
    }
}

# ── 5. Start Ollama service ──

Write-Host ""
Write-Host "[5/9] Starting Ollama service..." -ForegroundColor Yellow

if ($OllamaUrl) {
    $ollamaRunning = $false
    try {
        Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 3 -ErrorAction Stop | Out-Null
        $ollamaRunning = $true
        Write-Host "  Ollama is running at $OllamaUrl"
    } catch {
        if (Get-Command ollama -ErrorAction SilentlyContinue) {
            Write-Host "  Starting Ollama..."
            Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
            for ($i = 1; $i -le 15; $i++) {
                Start-Sleep -Seconds 1
                try {
                    Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 1 -ErrorAction Stop | Out-Null
                    $ollamaRunning = $true
                    Write-Host "  Ollama started successfully"
                    break
                } catch { }
            }
            if (-not $ollamaRunning) {
                Write-Host "  WARNING: Ollama did not start. Try running 'ollama serve' manually." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  WARNING: Cannot reach Ollama at $OllamaUrl" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  Skipped (Ollama not configured)"
}

# ── 6. Generate .mcp.json ──

Write-Host ""
Write-Host "[6/9] Generating .mcp.json..." -ForegroundColor Yellow

$McpJsonPath = Join-Path $RepoRoot ".mcp.json"
if (Test-Path $McpJsonPath) {
    Write-Host "  .mcp.json already exists, skipping (delete it to regenerate)"
} else {
    # On Windows, call uv/python directly instead of run.sh
    $RagDirJson = ($RagDir -replace '\\', '\\\\')
    $RepoRootJson = ($RepoRoot -replace '\\', '\\\\')

    if ($PkgManager -eq "uv") {
        $mcpJson = @"
{
  "mcpServers": {
    "life-rag": {
      "type": "stdio",
      "command": "uv",
      "args": ["--directory", "$RagDirJson", "run", "life-rag-mcp"],
      "env": {
        "LIFE_REPO_PATH": "$RepoRootJson"
      }
    }
  }
}
"@
    } else {
        $mcpExeJson = ((Join-Path $VenvDir "Scripts" "life-rag-mcp.exe") -replace '\\', '\\\\')
        $mcpJson = @"
{
  "mcpServers": {
    "life-rag": {
      "type": "stdio",
      "command": "$mcpExeJson",
      "env": {
        "LIFE_REPO_PATH": "$RepoRootJson"
      }
    }
  }
}
"@
    }
    $mcpJson | Set-Content -Path $McpJsonPath -Encoding UTF8
    Write-Host "  Generated .mcp.json"
}

# ── 7. Install git hooks ──

Write-Host ""
Write-Host "[7/9] Installing git hooks..." -ForegroundColor Yellow

# Git for Windows uses Git Bash to run hooks, so the bash script works as-is
$HooksDir = Join-Path $RepoRoot ".git" "hooks"
if (Test-Path $HooksDir) {
    Copy-Item (Join-Path $RepoRoot "scripts" "post-commit") (Join-Path $HooksDir "post-commit") -Force
    Write-Host "  Installed post-commit hook"
    Write-Host "  (Git for Windows runs hooks via built-in bash)"
} else {
    Write-Host "  WARNING: .git/hooks not found. Run 'git init' first." -ForegroundColor Yellow
}

# ── 8. Install Python dependencies ──

Write-Host ""
Write-Host "[8/9] Installing Python dependencies..." -ForegroundColor Yellow

if ($PkgManager -eq "uv") {
    Push-Location $RagDir
    try {
        uv sync
    } finally {
        Pop-Location
    }
} else {
    # pip with venv
    if (-not (Test-Path $VenvDir)) {
        & $pythonCmd -m venv $VenvDir
    }
    $pipExe = Join-Path $VenvDir "Scripts" "pip.exe"
    & $pipExe install --upgrade pip 2>&1 | Select-Object -Last 1
    & $pipExe install -e $RagDir 2>&1 | Select-Object -Last 1
}
Write-Host "  Dependencies installed ($PkgManager)"

# ── 9. Pull embedding model & build index ──

Write-Host ""
Write-Host "[9/9] Setting up embedding model and index..." -ForegroundColor Yellow

$ollamaReachable = $false
if ($OllamaUrl) {
    try {
        Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 3 -ErrorAction Stop | Out-Null
        $ollamaReachable = $true
    } catch { }
}

if ($ollamaReachable) {
    Write-Host "  Pulling bge-m3 embedding model (this may take a few minutes on first run)..."
    if ((Get-Command ollama -ErrorAction SilentlyContinue) -and $OllamaUrl -eq "http://localhost:11434") {
        ollama pull bge-m3
    } else {
        Write-Host "  Using Ollama API at $OllamaUrl"
        try {
            $body = '{"name":"bge-m3"}'
            Invoke-RestMethod -Uri "$OllamaUrl/api/pull" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 600 | Out-Null
        } catch {
            Write-Host "  WARNING: Failed to pull bge-m3 model" -ForegroundColor Yellow
        }
    }

    # Verify embed API
    Write-Host "  Verifying embedding API..."
    try {
        $embedBody = '{"model":"bge-m3","input":"test"}'
        $result = Invoke-RestMethod -Uri "$OllamaUrl/api/embed" -Method Post -Body $embedBody -ContentType "application/json" -TimeoutSec 30
        if ($result.embeddings) {
            Write-Host "  Embedding API OK"
        } else {
            Write-Host "  WARNING: Embedding API test failed." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  WARNING: Embedding API test failed." -ForegroundColor Yellow
        Write-Host "  RAG semantic search may not work until this is resolved."
    }

    # Build initial index
    Write-Host "  Building initial RAG index..."
    $env:OLLAMA_URL = $OllamaUrl
    $env:LIFE_REPO_PATH = $RepoRoot
    if ($PkgManager -eq "uv") {
        Push-Location $RepoRoot
        try {
            uv --directory $RagDir run life-rag-index --full
        } catch {
            Write-Host "  WARNING: Initial index build failed (this is OK for an empty repo)" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    } else {
        $indexerExe = Join-Path $VenvDir "Scripts" "life-rag-index.exe"
        try {
            & $indexerExe --full
        } catch {
            Write-Host "  WARNING: Initial index build failed (this is OK for an empty repo)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  Skipped (Ollama not reachable)."
    if (-not $OllamaUrl) {
        Write-Host "  To enable RAG search, install Ollama and re-run setup.ps1"
    } else {
        Write-Host "  Make sure Ollama is running at $OllamaUrl and re-run setup.ps1"
    }
}

# ── 10. GitHub integration (optional) ──

Write-Host ""
Write-Host "=== Core setup complete! ===" -ForegroundColor Green
Write-Host ""

$SetupGitHub = $false
Write-Host "GitHub に接続しますか？（任意）"
Write-Host "ブラウザから記録を閲覧・バックアップできるようになります。"
Write-Host "GitHub アカウントが必要です（https://github.com/signup）"
Write-Host ""
$answer = Read-Host "[y/N]"
if ($answer -match '^[yY]') {
    $SetupGitHub = $true
}

if ($SetupGitHub) {
    Write-Host ""
    Write-Host "[10] Connecting to GitHub..." -ForegroundColor Yellow

    # Install gh CLI if needed
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "  Installing GitHub CLI..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget install GitHub.cli --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            } catch { }
        }

        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Host "  WARNING: GitHub CLI installation failed." -ForegroundColor Yellow
            Write-Host "  Install manually: https://cli.github.com/"
            Write-Host "  Then run:"
            Write-Host "    gh auth login --web"
            Write-Host "    gh repo create ai-life-journal --private --source=. --push"
            $SetupGitHub = $false
        } else {
            Write-Host "  GitHub CLI: installed"
        }
    } else {
        Write-Host "  GitHub CLI: already installed"
    }
}

if ($SetupGitHub) {
    # Authenticate
    $ghAuthed = $false
    try {
        gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
    } catch { }

    if (-not $ghAuthed) {
        Write-Host ""
        Write-Host "  ブラウザで GitHub にログインします。"
        Write-Host "  表示される URL を開き、コードを入力してください。"
        Write-Host ""
        gh auth login --web --git-protocol https
    } else {
        Write-Host "  GitHub: already authenticated"
    }

    # Verify auth
    $ghAuthed = $false
    try {
        gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
    } catch { }

    if ($ghAuthed) {
        $GhUser = gh api user -q .login 2>$null
        $RepoName = "ai-life-journal"
        $NewOrigin = "https://github.com/$GhUser/$RepoName.git"
        $CurrentBranch = git branch --show-current

        Write-Host ""

        # Create repo on GitHub if it doesn't exist
        $repoExists = $false
        try {
            gh repo view "$GhUser/$RepoName" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $repoExists = $true }
        } catch { }

        if ($repoExists) {
            Write-Host "  Repository $GhUser/$RepoName already exists"
        } else {
            Write-Host "  Creating private repository: $GhUser/$RepoName"
            gh repo create $RepoName --private 2>&1 | Out-Null

            try {
                gh repo view "$GhUser/$RepoName" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "not found" }
            } catch {
                Write-Host "  WARNING: Repository creation failed." -ForegroundColor Yellow
                Write-Host "  Try manually: gh repo create $RepoName --private"
                $SetupGitHub = $false
            }
        }

        if ($SetupGitHub) {
            # Switch origin from template repo to user's repo
            Write-Host "  Updating remote origin -> $NewOrigin"
            git remote set-url origin $NewOrigin 2>$null
            if ($LASTEXITCODE -ne 0) {
                git remote add origin $NewOrigin 2>$null
            }

            # Push all content
            Write-Host "  Pushing..."
            git push -u origin $CurrentBranch 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Done! https://github.com/$GhUser/$RepoName"
            } else {
                Write-Host "  WARNING: Push failed." -ForegroundColor Yellow
                Write-Host "  Try manually: git push -u origin $CurrentBranch"
            }
        }
    } else {
        Write-Host "  WARNING: GitHub authentication failed." -ForegroundColor Yellow
        Write-Host "  Try manually: gh auth login --web"
    }
}

# ── Done ──

Write-Host ""
Write-Host "=== All done! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Fill in profile/about.md with your information"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "  2. Install Claude Code: npm install -g @anthropic-ai/claude-code"
    Write-Host "  3. Run 'claude' in this directory"
} else {
    Write-Host "  2. Run 'claude' in this directory"
}
Write-Host ""
Write-Host "Available commands:"
Write-Host "  /journal   - Record daily events"
Write-Host "  /recall    - AI-guided daily reflection"
Write-Host "  /record    - Save conversation to journal + knowledge"
Write-Host "  /distill   - Extract knowledge from journals"
Write-Host "  /status    - View progress summary"
if (-not $SetupGitHub) {
    Write-Host ""
    Write-Host "GitHub 連携を後から設定する場合:"
    Write-Host "  gh auth login --web"
    Write-Host "  gh repo create ai-life-journal --private --source=. --push"
}
Write-Host ""
