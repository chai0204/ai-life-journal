"""MCP server for life repository RAG search."""

from __future__ import annotations

import logging
import subprocess
import sys

from mcp.server.fastmcp import FastMCP

from .config import LIFE_RAG_DB_PATH, OLLAMA_URL
from .database import Database
from .embedder import Embedder, OllamaConnectionError

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

mcp = FastMCP(
    "life-rag",
    instructions=(
        "life リポジトリ（日記・知識・思考・プロフィール・作成物・参考資料）を"
        "セマンティック検索するためのツール。"
        "過去の記録を参照したいとき、関連する知識や経験を探したいときに使用する。"
    ),
)

# Lazy-initialized singletons
_db: Database | None = None
_embedder: Embedder | None = None


def _get_db() -> Database:
    global _db
    if _db is None:
        _db = Database(db_path=LIFE_RAG_DB_PATH)
        _db.initialize()
    return _db


def _get_embedder() -> Embedder:
    global _embedder
    if _embedder is None:
        _embedder = Embedder()
    return _embedder


def _ollama_error_guide(url: str) -> str:
    """Generate a troubleshooting guide when Ollama is unreachable."""
    lines = [
        "# Ollama 接続エラー",
        "",
        f"Ollama ({url}) に接続できません。セマンティック検索が利用できない状態です。",
        "",
        "## AIへの指示",
        "",
        "以下の手順でオーナーに状況を伝え、自動修復を試みてください：",
        "",
        "1. まず以下のコマンドで Ollama の状態を確認する:",
        "   ```",
        f"   curl -sf {url}/api/tags",
        "   ```",
        "",
        "2. 接続できない場合、環境に応じて対処する:",
        "",
        "### Linux / WSL2（ローカル Ollama）",
        "   ```bash",
        "   # Ollama が起動しているか確認",
        "   pgrep -x ollama || echo 'Ollama is not running'",
        "",
        "   # 起動する",
        "   ollama serve &",
        "",
        "   # 起動を待って確認",
        "   sleep 3 && curl -sf http://localhost:11434/api/tags",
        "   ```",
        "",
        "### WSL2（Windows 側 Ollama を使用）",
        "   Windows 側で Ollama が起動していることを確認してください。",
        "   タスクトレイに Ollama アイコンがあるか確認してください。",
        "   ```bash",
        "   # Windows ホスト IP を確認",
        "   ip route show default | awk '{print $3}'",
        "",
        "   # Windows 側 Ollama に接続テスト",
        "   WIN_HOST=$(ip route show default | awk '{print $3}')",
        "   curl -sf http://${WIN_HOST}:11434/api/tags",
        "   ```",
        "",
        "### Ollama が未インストールの場合",
        "   ```bash",
        "   curl -fsSL https://ollama.com/install.sh | sh",
        "   ollama serve &",
        "   sleep 3",
        "   ollama pull bge-m3",
        "   ```",
        "",
        "3. Ollama 復旧後、再度検索を試みてください。",
    ]
    return "\n".join(lines)


@mcp.tool()
async def search(
    query: str,
    layer: str | None = None,
    date_from: str | None = None,
    date_until: str | None = None,
    tags: list[str] | None = None,
    limit: int = 5,
) -> str:
    """life リポジトリをセマンティック検索する。

    過去の日記、知識、思考、プロフィールなどを意味的に近い順で検索する。

    Args:
        query: 検索クエリ（自然言語）
        layer: フィルタ。'journal','knowledge','thoughts','profile','works','references' のいずれか
        date_from: 日付フィルタ開始（YYYY-MM-DD）
        date_until: 日付フィルタ終了（YYYY-MM-DD）
        tags: タグフィルタ（いずれか1つでもマッチすれば含める）
        limit: 返却件数（デフォルト5）
    """
    db = _get_db()
    embedder = _get_embedder()

    try:
        query_embedding = await embedder.aembed(query)
    except OllamaConnectionError as e:
        log.error("Ollama connection failed: %s", e)
        return _ollama_error_guide(e.url)

    results = db.search(
        query_embedding,
        limit=limit,
        layer=layer,
        date_from=date_from,
        date_until=date_until,
        tags=tags,
    )

    if not results:
        return "検索結果なし。"

    parts: list[str] = []
    for i, r in enumerate(results, 1):
        header = f"── Result {i} (score: {r.score:.2f}) {'─' * 30}"
        parts.append(header)
        parts.append(r.format())
        parts.append("")

    return "\n".join(parts)


def main() -> None:
    """Entry point for life-rag-mcp server."""
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
