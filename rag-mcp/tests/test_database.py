"""Tests for database module."""

from __future__ import annotations

from life_rag_mcp.database import Database
from life_rag_mcp.models import Chunk

# Use a small dimension for testing
FAKE_DIM = 1024


def _fake_embedding(seed: float = 0.0) -> list[float]:
    """Generate a deterministic fake embedding."""
    return [seed + i * 0.001 for i in range(FAKE_DIM)]


def _make_chunk(**overrides) -> Chunk:
    defaults = dict(
        file_path="journal/2026/02/2026-02-28.md",
        layer="journal",
        heading="SSH接続の構築",
        content="サーバーにSSH接続した。",
        date="2026-02-28",
        tags=["ssh", "infrastructure"],
    )
    defaults.update(overrides)
    return Chunk(**defaults)


def test_initialize(tmp_db: Database) -> None:
    """Tables should be created."""
    cur = tmp_db.conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = {row[0] for row in cur.fetchall()}
    assert "chunks" in tables
    assert "vec_chunks" in tables


def test_insert_and_count(tmp_db: Database) -> None:
    chunk = _make_chunk()
    chunk_id = tmp_db.insert_chunk(chunk, _fake_embedding(0.1))
    assert chunk_id is not None
    assert tmp_db.count_chunks() == 1


def test_delete_by_file(tmp_db: Database) -> None:
    c1 = _make_chunk(heading="Section 1")
    c2 = _make_chunk(heading="Section 2")
    c3 = _make_chunk(file_path="knowledge/rust.md", layer="knowledge", heading="Ownership")

    tmp_db.insert_chunk(c1, _fake_embedding(0.1))
    tmp_db.insert_chunk(c2, _fake_embedding(0.2))
    tmp_db.insert_chunk(c3, _fake_embedding(0.3))

    assert tmp_db.count_chunks() == 3
    deleted = tmp_db.delete_by_file("journal/2026/02/2026-02-28.md")
    assert deleted == 2
    assert tmp_db.count_chunks() == 1


def test_search_basic(tmp_db: Database) -> None:
    chunk = _make_chunk()
    embedding = _fake_embedding(0.5)
    tmp_db.insert_chunk(chunk, embedding)

    # Search with the same embedding should find it
    results = tmp_db.search(embedding, limit=5)
    assert len(results) == 1
    assert results[0].file_path == "journal/2026/02/2026-02-28.md"
    assert results[0].heading == "SSH接続の構築"


def test_search_layer_filter(tmp_db: Database) -> None:
    c1 = _make_chunk(layer="journal")
    c2 = _make_chunk(file_path="knowledge/ssh.md", layer="knowledge", heading="SSH")
    emb = _fake_embedding(0.5)

    tmp_db.insert_chunk(c1, emb)
    tmp_db.insert_chunk(c2, _fake_embedding(0.51))

    results = tmp_db.search(emb, layer="knowledge")
    assert len(results) == 1
    assert results[0].layer == "knowledge"


def test_search_date_filter(tmp_db: Database) -> None:
    c1 = _make_chunk(date="2026-02-01")
    c2 = _make_chunk(date="2026-03-01", heading="March entry")
    emb = _fake_embedding(0.5)

    tmp_db.insert_chunk(c1, emb)
    tmp_db.insert_chunk(c2, _fake_embedding(0.51))

    results = tmp_db.search(emb, date_from="2026-02-15")
    assert len(results) == 1
    assert results[0].date == "2026-03-01"


def test_search_tags_filter(tmp_db: Database) -> None:
    c1 = _make_chunk(tags=["ssh", "infrastructure"])
    c2 = _make_chunk(tags=["rust", "programming"], heading="Rust")
    emb = _fake_embedding(0.5)

    tmp_db.insert_chunk(c1, emb)
    tmp_db.insert_chunk(c2, _fake_embedding(0.51))

    results = tmp_db.search(emb, tags=["rust"])
    assert len(results) == 1
    assert "rust" in results[0].tags


def test_get_all_file_paths(tmp_db: Database) -> None:
    tmp_db.insert_chunk(_make_chunk(), _fake_embedding(0.1))
    tmp_db.insert_chunk(
        _make_chunk(file_path="knowledge/ssh.md", layer="knowledge"),
        _fake_embedding(0.2),
    )

    paths = tmp_db.get_all_file_paths()
    assert paths == {"journal/2026/02/2026-02-28.md", "knowledge/ssh.md"}
