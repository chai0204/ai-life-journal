---
name: record
description: 会話内容を具体層＋抽象層の両方に記録する。オーナーが「これを記録して」と言ったとき、またはセッション終了時の記録提案に使用。
argument-hint: [記録したい内容の要約]
user-invocable: true
---

# /record — 会話内容の記録実行

現在の会話から記録すべき内容を検出し、具体層と抽象層の両方に振り分けて記録する。

## 手順

1. これまでの会話内容を分析し、記録すべき情報を識別する
2. 以下の判断基準で分類する:

| シグナル | 具体層 | 抽象層 |
|---|---|---|
| 出来事・体験・感情 | journal/ | thoughts/ |
| 学び・知見 | journal/ | knowledge/ |
| 主観的な考え・内省 | journal/ | thoughts/ |
| 価値観・方針 | journal/ | profile/about.md |
| 目標の設定・変更 | journal/ | profile/goals.md |
| タスク・予定 | journal/ | GitHub Issue |
| 作成物への言及 | journal/ | works/ |
| 外部資料の読了 | journal/ | references/ |

3. 抽象層に記録する各項目について、`mcp__life-rag__search(query="記録内容の要約", layer="knowledge")` および `layer="thoughts"` で類似の既存ファイルを検索し、新規作成か既存更新かを判定する
4. 記録計画をオーナーに提示する:
   ```
   以下を記録します:
   - journal/2026/02/2026-02-27.md に追記
   - knowledge/topic.md を新規作成（RAG検索で類似ファイルなし）
   - thoughts/topic.md を更新（RAG検索で既存ファイルを発見）
   ```
5. 承認を得たら記録を実行する
6. 変更をコミットする

## ルール

- 具体層（journal/）ではオーナーの言葉をそのまま活かす
- 抽象層では意味を損なわない範囲で圧縮してよい
- 1回のコミットで関連する変更をまとめる
- タスク・予定が含まれていた場合は `gh issue create` で Issue を自動起票する
- **Issue 操作の報告**: Issue の作成・完了・編集などを行った場合は都度オーナーに報告する（確認は不要）
