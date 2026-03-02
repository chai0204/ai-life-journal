"""SQLite database with pure-Python vector similarity search."""

from __future__ import annotations

import json
import math
import sqlite3
import struct
from pathlib import Path

from .config import EMBEDDING_DIM, LIFE_RAG_DB_PATH
from .models import Chunk, SearchResult


def _serialize_f32(vec: list[float]) -> bytes:
    """Serialize a list of floats to a compact binary format."""
    return struct.pack(f"{len(vec)}f", *vec)


def _deserialize_f32(data: bytes) -> list[float]:
    """Deserialize a binary blob back to a list of floats."""
    n = len(data) // 4
    return list(struct.unpack(f"{n}f", data))


def _cosine_similarity(a: list[float], b: list[float]) -> float:
    """Compute cosine similarity between two vectors."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


class Database:
    def __init__(self, db_path: Path | None = None) -> None:
        self.db_path = db_path or LIFE_RAG_DB_PATH
        self._conn: sqlite3.Connection | None = None

    @property
    def conn(self) -> sqlite3.Connection:
        if self._conn is None:
            self._conn = self._connect()
        return self._conn

    def _connect(self) -> sqlite3.Connection:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(self.db_path))
        return conn

    def initialize(self) -> None:
        """Create tables if they don't exist."""
        cur = self.conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT NOT NULL,
                layer TEXT NOT NULL,
                heading TEXT NOT NULL,
                date TEXT,
                tags TEXT,
                content TEXT NOT NULL
            )
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_chunks_file_path ON chunks(file_path)
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS embeddings (
                chunk_id INTEGER PRIMARY KEY,
                embedding BLOB NOT NULL,
                FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
            )
        """)
        # Migrate from old vec_chunks virtual table if it exists
        cur.execute("""
            SELECT name FROM sqlite_master
            WHERE type='table' AND name='vec_chunks'
        """)
        if cur.fetchone():
            cur.execute("DROP TABLE vec_chunks")
        self.conn.commit()

    def insert_chunk(self, chunk: Chunk, embedding: list[float]) -> int:
        """Insert a chunk and its embedding. Returns the chunk id."""
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO chunks (file_path, layer, heading, date, tags, content)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                chunk.file_path,
                chunk.layer,
                chunk.heading,
                chunk.date,
                chunk.tags_json,
                chunk.content,
            ),
        )
        chunk_id = cur.lastrowid
        cur.execute(
            "INSERT INTO embeddings (chunk_id, embedding) VALUES (?, ?)",
            (chunk_id, _serialize_f32(embedding)),
        )
        self.conn.commit()
        return chunk_id

    def delete_by_file(self, file_path: str) -> int:
        """Delete all chunks for a given file. Returns number of deleted rows."""
        cur = self.conn.cursor()
        cur.execute("SELECT id FROM chunks WHERE file_path = ?", (file_path,))
        ids = [row[0] for row in cur.fetchall()]
        if not ids:
            return 0
        placeholders = ",".join("?" * len(ids))
        cur.execute(f"DELETE FROM embeddings WHERE chunk_id IN ({placeholders})", ids)
        cur.execute("DELETE FROM chunks WHERE file_path = ?", (file_path,))
        self.conn.commit()
        return len(ids)

    def search(
        self,
        query_embedding: list[float],
        *,
        limit: int = 5,
        layer: str | None = None,
        date_from: str | None = None,
        date_until: str | None = None,
        tags: list[str] | None = None,
    ) -> list[SearchResult]:
        """Search by cosine similarity with optional metadata filtering."""
        cur = self.conn.cursor()

        # Build query with optional filters for pre-filtering
        where_clauses = []
        params: list[str] = []
        if layer:
            where_clauses.append("c.layer = ?")
            params.append(layer)
        if date_from:
            where_clauses.append("c.date >= ?")
            params.append(date_from)
        if date_until:
            where_clauses.append("c.date <= ?")
            params.append(date_until)

        where_sql = ""
        if where_clauses:
            where_sql = "WHERE " + " AND ".join(where_clauses)

        cur.execute(
            f"""
            SELECT c.id, c.file_path, c.layer, c.heading, c.date, c.tags,
                   c.content, e.embedding
            FROM chunks c
            JOIN embeddings e ON e.chunk_id = c.id
            {where_sql}
            """,
            params,
        )
        rows = cur.fetchall()

        # Compute similarity and filter
        results: list[SearchResult] = []
        for row in rows:
            chunk_id, file_path, row_layer, heading, date, tags_json, content, emb_blob = row
            row_tags = json.loads(tags_json) if tags_json else []

            # Tag filter (not easily done in SQL with JSON)
            if tags and not any(t in row_tags for t in tags):
                continue

            emb = _deserialize_f32(emb_blob)
            score = _cosine_similarity(query_embedding, emb)

            results.append(
                SearchResult(
                    chunk_id=chunk_id,
                    file_path=file_path,
                    layer=row_layer,
                    heading=heading,
                    content=content,
                    score=score,
                    date=date,
                    tags=row_tags,
                )
            )

        # Sort by score descending, take top limit
        results.sort(key=lambda r: r.score, reverse=True)
        return results[:limit]

    def get_all_file_paths(self) -> set[str]:
        """Get all unique file paths in the database."""
        cur = self.conn.cursor()
        cur.execute("SELECT DISTINCT file_path FROM chunks")
        return {row[0] for row in cur.fetchall()}

    def count_chunks(self) -> int:
        """Return total number of chunks."""
        cur = self.conn.cursor()
        cur.execute("SELECT COUNT(*) FROM chunks")
        return cur.fetchone()[0]

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None
