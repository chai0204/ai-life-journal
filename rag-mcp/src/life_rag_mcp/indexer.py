"""Index builder for life repository."""

from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from .chunker import chunk_file, discover_files
from .config import LIFE_RAG_DB_PATH, LIFE_REPO_PATH
from .database import Database
from .embedder import Embedder

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


def build_full_index(
    repo_root: Path | None = None,
    db_path: Path | None = None,
) -> None:
    """Build a full index from scratch."""
    root = repo_root or LIFE_REPO_PATH
    db = Database(db_path=db_path or LIFE_RAG_DB_PATH)
    embedder = Embedder()

    try:
        db.initialize()
        files = discover_files(root)
        log.info("Found %d files to index", len(files))

        total_chunks = 0
        t0 = time.monotonic()

        for i, file_path in enumerate(files, 1):
            rel = file_path.relative_to(root)
            log.info("[%d/%d] Processing %s", i, len(files), rel)

            # Delete existing chunks for this file (idempotent rebuild)
            db.delete_by_file(str(rel))

            chunks = chunk_file(file_path, repo_root=root)
            if not chunks:
                log.info("  → 0 chunks (skipped)")
                continue

            # Batch embed all chunks for this file
            texts = [c.content for c in chunks]
            try:
                embeddings = embedder.embed_batch(texts)
            except Exception as e:
                log.error("  → Embedding failed: %s", e)
                continue

            for chunk, embedding in zip(chunks, embeddings):
                db.insert_chunk(chunk, embedding)

            total_chunks += len(chunks)
            log.info("  → %d chunks indexed", len(chunks))

        elapsed = time.monotonic() - t0
        log.info(
            "Full index complete: %d chunks from %d files in %.1fs",
            total_chunks, len(files), elapsed,
        )
        log.info("DB total: %d chunks", db.count_chunks())
    finally:
        embedder.close()
        db.close()


def update_incremental(
    changed_files: list[str],
    repo_root: Path | None = None,
    db_path: Path | None = None,
) -> None:
    """Incrementally update index for changed files.

    Args:
        changed_files: List of file paths relative to repo root.
    """
    root = repo_root or LIFE_REPO_PATH
    db = Database(db_path=db_path or LIFE_RAG_DB_PATH)
    embedder = Embedder()

    try:
        db.initialize()

        for rel_path_str in changed_files:
            file_path = root / rel_path_str
            log.info("Updating %s", rel_path_str)

            # Delete existing chunks
            deleted = db.delete_by_file(rel_path_str)
            if deleted:
                log.info("  → Deleted %d old chunks", deleted)

            if not file_path.exists():
                log.info("  → File removed, deletion only")
                continue

            chunks = chunk_file(file_path, repo_root=root)
            if not chunks:
                log.info("  → 0 chunks (skipped)")
                continue

            texts = [c.content for c in chunks]
            try:
                embeddings = embedder.embed_batch(texts)
            except Exception as e:
                log.error("  → Embedding failed: %s", e)
                continue

            for chunk, embedding in zip(chunks, embeddings):
                db.insert_chunk(chunk, embedding)

            log.info("  → %d chunks indexed", len(chunks))

        log.info("Incremental update complete. DB total: %d chunks", db.count_chunks())
    finally:
        embedder.close()
        db.close()


def main() -> None:
    """CLI entry point for life-rag-index."""
    parser = argparse.ArgumentParser(description="Index life repository for RAG search")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--full", action="store_true", help="Full reindex")
    group.add_argument("--files", nargs="+", help="Incremental update for specific files (relative paths)")

    parser.add_argument("--repo", type=Path, default=None, help="Life repo path")
    parser.add_argument("--db", type=Path, default=None, help="Database path")

    args = parser.parse_args()

    if args.full:
        build_full_index(repo_root=args.repo, db_path=args.db)
    else:
        update_incremental(args.files, repo_root=args.repo, db_path=args.db)


if __name__ == "__main__":
    main()
