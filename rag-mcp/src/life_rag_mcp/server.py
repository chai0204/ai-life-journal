"""MCP server for life repository RAG search."""

from __future__ import annotations

import logging

from mcp.server.fastmcp import FastMCP

from .config import LIFE_RAG_DB_PATH
from .database import Database
from .embedder import Embedder

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

    query_embedding = await embedder.aembed(query)

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
