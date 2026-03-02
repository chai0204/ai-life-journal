---
paths:
  - "thoughts/**/*.md"
---

# 思考・経験（抽象層・主観）の書き方ルール

- 主観的な思考・経験・内省・教訓を記録する
- 具体的なエピソードは省き、そこから得た洞察・方針を残す
- 「〇〇についてこう考える」「〇〇という教訓を得た」という形で蒸留する
- YAML frontmatter に tags, created, updated を含める
- 新規作成前に `mcp__life-rag__search(query="内容の要約", layer="thoughts")` で類似ファイルを検索し、既存ファイルへの統合を優先する
- 既存ファイルの更新時は frontmatter の updated を更新する
- ファイル名: トピックを端的に表すケバブケース
- 言語: 日本語
