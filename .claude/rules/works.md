---
paths:
  - "works/**/*.md"
---

# 作成物のメタデータの書き方ルール

- 1作品につき1つの .md ファイルで管理する
- YAML frontmatter に title, type, tags, status, created, updated を含める
- type: paper, blog, slide, code, other のいずれか
- status: draft, published, archived のいずれか
- PDF等バイナリファイルは手動追加が前提。AIはメタデータ .md の作成・更新を行う
- ファイル名: 作品を端的に表すケバブケース
- 言語: 内容に応じて日本語または英語
