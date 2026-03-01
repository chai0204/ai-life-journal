"""Configuration for life-rag-mcp."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

# Default: monorepo root (rag-mcp/ is inside the life repo)
# __file__ → src/life_rag_mcp/config.py
# parents[2] → rag-mcp/
# parents[2].parent → repo root
_DEFAULT_REPO_PATH = str(Path(__file__).resolve().parents[2].parent)

LIFE_REPO_PATH: Path = Path(
    os.environ.get("LIFE_REPO_PATH", _DEFAULT_REPO_PATH)
)

LIFE_RAG_DB_PATH: Path = Path(
    os.environ.get("LIFE_RAG_DB_PATH", str(Path(__file__).resolve().parents[2] / "data" / "life.db"))
)


def _detect_ollama_url() -> str:
    """Detect Ollama URL. On WSL2, use the Windows host IP."""
    env = os.environ.get("OLLAMA_URL")
    if env:
        return env
    if Path("/proc/sys/fs/binfmt_misc/WSLInterop").exists():
        try:
            out = subprocess.check_output(
                ["ip", "route", "show", "default"],
                text=True,
            )
            host_ip = out.split()[2]
            return f"http://{host_ip}:11434"
        except (subprocess.SubprocessError, IndexError):
            pass
    return "http://localhost:11434"


OLLAMA_URL: str = _detect_ollama_url()

OLLAMA_MODEL: str = os.environ.get("OLLAMA_MODEL", "bge-m3")

EMBEDDING_DIM: int = 1024

# Directories to index (relative to LIFE_REPO_PATH)
TARGET_DIRS: list[str] = [
    "journal",
    "knowledge",
    "thoughts",
    "profile",
    "works",
    "references",
]

# Files to skip
SKIP_FILES: set[str] = {"_tags.md", ".gitkeep"}
