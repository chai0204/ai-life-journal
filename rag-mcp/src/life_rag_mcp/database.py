"""SQLite + sqlite-vec database operations."""

from __future__ import annotations

import json
import sqlite3
import struct
from pathlib import Path

import sqlite_vec

from .config import EMBEDDING_DIM, LIFE_RAG_DB_PATH
from .models import Chunk, SearchResult


def _serialize_f32(vec: list[float]) -> bytes:
    """Serialize a list of floats to a compact binary format for sqlite-vec."""
    return struct.pack(f"{len(vec)}f", *vec)


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
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
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
        cur.execute(f"""
            CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
                embedding float[{EMBEDDING_DIM}]
            )
        """)
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
            "INSERT INTO vec_chunks (rowid, embedding) VALUES (?, ?)",
            (chunk_id, _serialize_f32(embedding)),
        )
        self.conn.commit()
        return chunk_id

    def delete_by_file(self, file_path: str) -> int:
        """Delete all chunks for a given file. Returns number of deleted rows."""
        cur = self.conn.cursor()
        # Get chunk ids to delete from vec table
        cur.execute("SELECT id FROM chunks WHERE file_path = ?", (file_path,))
        ids = [row[0] for row in cur.fetchall()]
        if not ids:
            return 0
        placeholders = ",".join("?" * len(ids))
        cur.execute(f"DELETE FROM vec_chunks WHERE rowid IN ({placeholders})", ids)
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
        """Two-phase search: vector candidates then metadata filtering."""
        # Phase 1: Get vector candidates (fetch more than limit to allow filtering)
        candidate_limit = limit * 10
        cur = self.conn.cursor()
        cur.execute(
            """
            SELECT rowid, distance
            FROM vec_chunks
            WHERE embedding MATCH ?
            ORDER BY distance
            LIMIT ?
            """,
            (_serialize_f32(query_embedding), candidate_limit),
        )
        candidates = cur.fetchall()

        if not candidates:
            return []

        # Phase 2: Fetch metadata and filter
        candidate_ids = [row[0] for row in candidates]
        distance_map = {row[0]: row[1] for row in candidates}

        placeholders = ",".join("?" * len(candidate_ids))
        cur.execute(
            f"""
            SELECT id, file_path, layer, heading, date, tags, content
            FROM chunks
            WHERE id IN ({placeholders})
            """,
            candidate_ids,
        )
        rows = cur.fetchall()

        results: list[SearchResult] = []
        for row in rows:
            chunk_id, file_path, row_layer, heading, date, tags_json, content = row
            row_tags = json.loads(tags_json) if tags_json else []

            # Apply filters
            if layer and row_layer != layer:
                continue
            if date_from and (not date or date < date_from):
                continue
            if date_until and (not date or date > date_until):
                continue
            if tags and not any(t in row_tags for t in tags):
                continue

            distance = distance_map[chunk_id]
            # Convert distance to similarity score (cosine distance → similarity)
            score = 1.0 - distance

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
