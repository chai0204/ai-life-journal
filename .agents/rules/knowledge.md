---
paths:
  - "knowledge/**/*.md"
---

# ナレッジ（抽象層・客観）の書き方ルール

- 客観的な知識を記録する（事実・仕組み・手法・調査結果）
- 「いつ」「どう感じた」は省き、「何が」「どう動く」を残す
- 時制に依存しない、汎用的な記述を心がける
- YAML frontmatter に tags, created, updated を含める
- 新規作成前に `mcp__life-rag__search(query="内容の要約", layer="knowledge")` で類似ファイルを検索し、既存ファイルへの統合を優先する
- 既存ファイルの更新時は frontmatter の updated を更新する
- ファイル名: トピックを端的に表すケバブケース
- 言語: 内容に応じて日本語または英語
