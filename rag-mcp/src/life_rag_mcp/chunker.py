"""Markdown parser and chunker for life repository files."""

from __future__ import annotations

import re
from pathlib import Path

import yaml

from .config import LIFE_REPO_PATH, SKIP_FILES, TARGET_DIRS
from .models import Chunk

# Regex for YAML frontmatter
_FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n?", re.DOTALL)

# Regex for markdown headings
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Extract YAML frontmatter and return (metadata, body)."""
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        meta = {}
    body = text[m.end():]
    return meta, body


def _detect_layer(file_path: str) -> str:
    """Detect layer from relative file path."""
    first_dir = file_path.split("/")[0]
    if first_dir in {"journal", "knowledge", "thoughts", "profile", "works", "references"}:
        return first_dir
    return "unknown"


def _extract_date(meta: dict, layer: str) -> str | None:
    """Extract date string from frontmatter."""
    if "date" in meta:
        return str(meta["date"])
    if "created" in meta:
        return str(meta["created"])
    return None


def _extract_tags(meta: dict) -> list[str]:
    """Extract tags list from frontmatter."""
    tags = meta.get("tags", [])
    if isinstance(tags, list):
        return [str(t) for t in tags]
    return []


def _split_by_headings(body: str, level: int) -> list[tuple[str, str]]:
    """Split body text by headings at the given level.

    Returns list of (heading_text, section_content) tuples.
    Content before the first heading is returned with heading_text="".
    """
    pattern = re.compile(rf"^({'#' * level})\s+(.+)$", re.MULTILINE)
    matches = list(pattern.finditer(body))

    if not matches:
        return [("", body.strip())]

    sections: list[tuple[str, str]] = []

    # Content before first heading
    pre = body[:matches[0].start()].strip()
    if pre:
        sections.append(("", pre))

    for i, m in enumerate(matches):
        heading_text = m.group(2).strip()
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        content = body[start:end].strip()
        sections.append((heading_text, content))

    return sections


def _chunk_journal(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk journal files by ## (event) sections, including ### subsections."""
    date = _extract_date(meta, "journal")
    tags = _extract_tags(meta)
    chunks: list[Chunk] = []

    sections = _split_by_headings(body, 2)
    for heading, content in sections:
        if not heading and not content.strip():
            continue
        # Skip H1 title line if it's the only content before first ##
        if not heading:
            # Check if it's just the H1 title
            lines = [l for l in content.split("\n") if l.strip() and not l.strip().startswith("# ")]
            if not lines:
                continue
            content = "\n".join(lines).strip()
            if not content:
                continue
            heading = "(intro)"

        chunks.append(Chunk(
            file_path=rel_path,
            layer="journal",
            heading=heading,
            content=content,
            date=date,
            tags=tags,
        ))

    return chunks


def _chunk_knowledge(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk knowledge files by lowest-level ## or ### sections with breadcrumbs."""
    date = _extract_date(meta, "knowledge")
    tags = _extract_tags(meta)
    chunks: list[Chunk] = []

    h2_sections = _split_by_headings(body, 2)
    for h2_heading, h2_content in h2_sections:
        if not h2_heading:
            # Skip H1 or preamble
            continue

        # Check for ### subsections within this ## section
        h3_sections = _split_by_headings(h2_content, 3)
        has_h3 = any(h for h, _ in h3_sections if h)

        if has_h3:
            for h3_heading, h3_content in h3_sections:
                if not h3_content.strip():
                    continue
                if h3_heading:
                    breadcrumb = f"{h2_heading} > {h3_heading}"
                else:
                    # Content before first ### in this ## section
                    breadcrumb = h2_heading
                chunks.append(Chunk(
                    file_path=rel_path,
                    layer="knowledge",
                    heading=breadcrumb,
                    content=h3_content,
                    date=date,
                    tags=tags,
                ))
        else:
            if not h2_content.strip():
                continue
            chunks.append(Chunk(
                file_path=rel_path,
                layer="knowledge",
                heading=h2_heading,
                content=h2_content,
                date=date,
                tags=tags,
            ))

    return chunks


def _chunk_thoughts(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk thoughts files. Small files → whole file; larger files → ## sections."""
    date = _extract_date(meta, "thoughts")
    tags = _extract_tags(meta)

    # Strip H1 title
    body_no_h1 = re.sub(r"^#\s+.+$", "", body, count=1, flags=re.MULTILINE).strip()

    # If small enough, return as single chunk
    if body_no_h1.count("\n") < 40:
        # Extract H1 for heading
        h1_match = re.search(r"^#\s+(.+)$", body, re.MULTILINE)
        heading = h1_match.group(1) if h1_match else "(全体)"
        return [Chunk(
            file_path=rel_path,
            layer="thoughts",
            heading=heading,
            content=body_no_h1,
            date=date,
            tags=tags,
        )]

    # Split by ## for larger files
    chunks: list[Chunk] = []
    sections = _split_by_headings(body, 2)
    for heading, content in sections:
        if not heading or not content.strip():
            continue
        chunks.append(Chunk(
            file_path=rel_path,
            layer="thoughts",
            heading=heading,
            content=content,
            date=date,
            tags=tags,
        ))
    return chunks


def _chunk_profile(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk profile files by ## sections."""
    tags = _extract_tags(meta)
    chunks: list[Chunk] = []

    sections = _split_by_headings(body, 2)
    for heading, content in sections:
        if not heading or not content.strip():
            continue
        chunks.append(Chunk(
            file_path=rel_path,
            layer="profile",
            heading=heading,
            content=content,
            date=None,
            tags=tags,
        ))
    return chunks


def _chunk_works(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk works files as whole file."""
    date = _extract_date(meta, "works")
    tags = _extract_tags(meta)

    # Strip H1 for heading
    h1_match = re.search(r"^#\s+(.+)$", body, re.MULTILINE)
    heading = h1_match.group(1) if h1_match else Path(rel_path).stem

    body_no_h1 = re.sub(r"^#\s+.+$", "", body, count=1, flags=re.MULTILINE).strip()
    if not body_no_h1:
        return []

    return [Chunk(
        file_path=rel_path,
        layer="works",
        heading=heading,
        content=body_no_h1,
        date=date,
        tags=tags,
    )]


def _chunk_references(body: str, meta: dict, rel_path: str) -> list[Chunk]:
    """Chunk references files by ## sections."""
    date = _extract_date(meta, "references")
    tags = _extract_tags(meta)
    chunks: list[Chunk] = []

    sections = _split_by_headings(body, 2)
    for heading, content in sections:
        if not heading or not content.strip():
            continue
        chunks.append(Chunk(
            file_path=rel_path,
            layer="references",
            heading=heading,
            content=content,
            date=date,
            tags=tags,
        ))
    return chunks


_CHUNKERS = {
    "journal": _chunk_journal,
    "knowledge": _chunk_knowledge,
    "thoughts": _chunk_thoughts,
    "profile": _chunk_profile,
    "works": _chunk_works,
    "references": _chunk_references,
}


def chunk_file(file_path: Path, repo_root: Path | None = None) -> list[Chunk]:
    """Parse and chunk a single Markdown file.

    Args:
        file_path: Absolute path to the file.
        repo_root: Root of the life repository. Defaults to config.

    Returns:
        List of Chunk objects.
    """
    root = repo_root or LIFE_REPO_PATH
    rel_path = str(file_path.relative_to(root))
    layer = _detect_layer(rel_path)

    if file_path.name in SKIP_FILES:
        return []

    if not file_path.suffix == ".md":
        return []

    text = file_path.read_text(encoding="utf-8")
    meta, body = parse_frontmatter(text)

    chunker = _CHUNKERS.get(layer)
    if chunker is None:
        return []

    return chunker(body, meta, rel_path)


def discover_files(repo_root: Path | None = None) -> list[Path]:
    """Discover all indexable Markdown files in the life repository."""
    root = repo_root or LIFE_REPO_PATH
    files: list[Path] = []
    for dir_name in TARGET_DIRS:
        dir_path = root / dir_name
        if not dir_path.exists():
            continue
        for md_file in sorted(dir_path.rglob("*.md")):
            if md_file.name in SKIP_FILES:
                continue
            files.append(md_file)
    return files
