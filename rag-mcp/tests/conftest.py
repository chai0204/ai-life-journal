"""Shared test fixtures."""

from __future__ import annotations

from pathlib import Path

import pytest

from life_rag_mcp.database import Database


@pytest.fixture
def tmp_db(tmp_path: Path) -> Database:
    """Create a temporary database for testing."""
    db = Database(db_path=tmp_path / "test.db")
    db.initialize()
    yield db
    db.close()
