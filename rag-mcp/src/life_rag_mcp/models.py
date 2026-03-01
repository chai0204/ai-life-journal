"""Data models for life-rag-mcp."""

from __future__ import annotations

import json
from dataclasses import dataclass, field


@dataclass
class Chunk:
    """A chunk of text extracted from a Markdown file."""

    file_path: str  # Relative to life repo root, e.g. 'journal/2026/02/2026-02-28.md'
    layer: str  # 'journal' | 'knowledge' | 'thoughts' | 'profile' | 'works' | 'references'
    heading: str  # Breadcrumb, e.g. 'SSH接続の構築 > 手順'
    content: str  # Full text of the chunk
    date: str | None = None  # YYYY-MM-DD from frontmatter
    tags: list[str] = field(default_factory=list)

    @property
    def tags_json(self) -> str:
        return json.dumps(self.tags, ensure_ascii=False)


@dataclass
class SearchResult:
    """A search result with score and chunk metadata."""

    chunk_id: int
    file_path: str
    layer: str
    heading: str
    content: str
    score: float
    date: str | None = None
    tags: list[str] = field(default_factory=list)

    def format(self) -> str:
        tags_str = ", ".join(self.tags) if self.tags else "none"
        date_str = self.date or "n/a"
        lines = [
            f"file: {self.file_path}",
            f"layer: {self.layer} | date: {date_str} | tags: {tags_str}",
            f"heading: {self.heading}",
            "",
            self.content,
        ]
        return "\n".join(lines)
