---
name: distill
description: 最近の日記から knowledge/ と thoughts/ へ情報を蒸留する。具体層から抽象層への圧縮ワークフロー。
argument-hint: [対象期間 例:today, this-week, 2026-02-20..2026-02-27]
user-invocable: true
disable-model-invocation: true
---

# /distill — 具体層から抽象層への蒸留

日記（具体層）を読み込み、まだ抽象層に反映されていない情報を抽出・提案する。

## 手順

1. 対象期間を特定する（`$ARGUMENTS` で指定がなければ直近1週間）
2. 該当する日記ファイルをすべて読み込む
3. 日記から抽出した各トピックについて、`mcp__life-rag__search(query="トピックの要約", layer="knowledge")` および `layer="thoughts"` で類似の既存ファイルを検索し、新規作成か既存更新かを判定する
4. 日記の中から以下を抽出する:
   - **knowledge/ 候補**: 客観的な知識・学び・調査結果・手法
   - **thoughts/ 候補**: 主観的な考え・経験・教訓・内省
   - **profile/ 更新候補**: 価値観・目標の変化
5. 抽出した候補をオーナーに提示する:
   ```
   ## knowledge/ への蒸留候補
   - 「〇〇」→ knowledge/topic-name.md（新規 or 既存更新）

   ## thoughts/ への蒸留候補
   - 「〇〇」→ thoughts/topic-name.md（新規 or 既存更新）
   ```
6. オーナーの承認を得てから記録する
7. 変更をコミットする

## 蒸留のルール

- **knowledge/**: 「いつ」「どう感じた」を省き、「何が」「どう動く」を残す
- **thoughts/**: 具体的なエピソードを省き、そこから得た洞察・方針を残す
- 既存ファイルがあれば追記・更新（frontmatter の updated を更新）
- なければテンプレートから新規作成
