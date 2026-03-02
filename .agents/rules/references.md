---
paths:
  - "references/**/*.md"
---

# 外部資料のメタデータの書き方ルール

- 1資料につき1つの .md ファイルで管理する
- YAML frontmatter に title, authors, type, tags, created, updated を含める
- type: paper, book, article, video, other のいずれか
- PDF等バイナリファイルは手動追加が前提。AIはメタデータ .md の作成・更新を行う
- 読書メモから汎用知識を抽出できる場合は knowledge/ にも記録を提案する
- knowledge/ との違い: references/ は「この資料について」の記録、knowledge/ は「資料から抽出した汎用知識」の記録
- ファイル名: 資料を端的に表すケバブケース
- 言語: 内容に応じて日本語または英語
