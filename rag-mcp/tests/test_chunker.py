"""Tests for chunker module."""

from __future__ import annotations

from pathlib import Path
from textwrap import dedent

from life_rag_mcp.chunker import chunk_file, discover_files, parse_frontmatter


def test_parse_frontmatter_basic():
    text = dedent("""\
        ---
        date: 2026-02-28
        tags: [ssh, infrastructure]
        ---

        # Title

        Content here.
    """)
    meta, body = parse_frontmatter(text)
    assert str(meta["date"]) == "2026-02-28"
    assert meta["tags"] == ["ssh", "infrastructure"]
    assert "# Title" in body


def test_parse_frontmatter_missing():
    text = "# No frontmatter\n\nContent."
    meta, body = parse_frontmatter(text)
    assert meta == {}
    assert body == text


def test_chunk_journal(tmp_path: Path):
    journal_dir = tmp_path / "journal" / "2026" / "02"
    journal_dir.mkdir(parents=True)
    f = journal_dir / "2026-02-28.md"
    f.write_text(dedent("""\
        ---
        date: 2026-02-28
        tags: [ssh, infrastructure]
        ---

        # 2026-02-28

        ## SSH接続の構築

        サーバーにSSH接続を設定した。

        ### 出来事

        Tailscaleを導入した。

        ### 気づき・学び

        VPN経由だと安全。

        ## 振り返り

        今日は充実した一日だった。
    """), encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    assert len(chunks) == 2
    assert chunks[0].heading == "SSH接続の構築"
    assert chunks[0].layer == "journal"
    assert chunks[0].date == "2026-02-28"
    assert "Tailscale" in chunks[0].content
    assert "VPN" in chunks[0].content
    assert chunks[1].heading == "振り返り"


def test_chunk_knowledge(tmp_path: Path):
    knowledge_dir = tmp_path / "knowledge"
    knowledge_dir.mkdir()
    f = knowledge_dir / "ssh-remote-access.md"
    f.write_text(dedent("""\
        ---
        tags: [ssh, remote-access]
        created: 2026-03-01
        updated: 2026-03-01
        ---

        # SSH Remote Access

        ## 概要

        SSH接続の基本概念。

        ## 設定

        ### サーバー側

        サーバー設定の詳細。

        ### クライアント側

        クライアント設定の詳細。

        ## 参考

        参考リンク。
    """), encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    assert len(chunks) == 4
    assert chunks[0].heading == "概要"
    assert chunks[1].heading == "設定 > サーバー側"
    assert chunks[2].heading == "設定 > クライアント側"
    assert chunks[3].heading == "参考"
    assert all(c.layer == "knowledge" for c in chunks)
    assert all(c.date == "2026-03-01" for c in chunks)


def test_chunk_thoughts_small(tmp_path: Path):
    thoughts_dir = tmp_path / "thoughts"
    thoughts_dir.mkdir()
    f = thoughts_dir / "career.md"
    f.write_text(dedent("""\
        ---
        tags: [キャリア]
        created: 2026-02-28
        updated: 2026-02-28
        ---

        # キャリアの方向性

        ## 考えたこと

        技術を深めたい。

        ## 教訓

        焦らないことが大事。
    """), encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    # Small file → single chunk
    assert len(chunks) == 1
    assert chunks[0].heading == "キャリアの方向性"
    assert "技術を深めたい" in chunks[0].content


def test_chunk_profile(tmp_path: Path):
    profile_dir = tmp_path / "profile"
    profile_dir.mkdir()
    f = profile_dir / "about.md"
    f.write_text(dedent("""\
        # About

        ## 基本情報

        名前: テスト

        ## 価値観

        効率を重視する。
    """), encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    assert len(chunks) == 2
    assert chunks[0].heading == "基本情報"
    assert chunks[1].heading == "価値観"
    assert all(c.layer == "profile" for c in chunks)


def test_chunk_works(tmp_path: Path):
    works_dir = tmp_path / "works"
    works_dir.mkdir()
    f = works_dir / "my-paper.md"
    f.write_text(dedent("""\
        ---
        title: My Paper
        type: paper
        tags: [research]
        status: published
        created: 2026-01-15
        updated: 2026-01-15
        ---

        # My Paper

        ## 概要

        論文の概要。

        ## メモ

        執筆時の気づき。
    """), encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    assert len(chunks) == 1
    assert chunks[0].heading == "My Paper"
    assert chunks[0].layer == "works"


def test_skip_tags_file(tmp_path: Path):
    knowledge_dir = tmp_path / "knowledge"
    knowledge_dir.mkdir()
    f = knowledge_dir / "_tags.md"
    f.write_text("# Tags\n\n- tag1\n- tag2\n", encoding="utf-8")

    chunks = chunk_file(f, repo_root=tmp_path)
    assert chunks == []


def test_discover_files(tmp_path: Path):
    """Test file discovery with a synthetic repo."""
    (tmp_path / "journal" / "2026" / "02").mkdir(parents=True)
    (tmp_path / "journal" / "2026" / "02" / "2026-02-28.md").write_text("# test")
    (tmp_path / "knowledge").mkdir()
    (tmp_path / "knowledge" / "topic.md").write_text("# test")
    (tmp_path / "knowledge" / "_tags.md").write_text("# tags")
    (tmp_path / "knowledge" / ".gitkeep").touch()

    files = discover_files(tmp_path)
    assert len(files) == 2
    assert all(f.suffix == ".md" for f in files)
    assert all(f.name not in {"_tags.md", ".gitkeep"} for f in files)
