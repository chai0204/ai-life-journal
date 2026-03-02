---
name: review-monthly
description: 今月の月次振り返りを生成する。該当月のjournal/とweekly reviewを分析し、月全体の傾向をまとめる。
argument-hint: [対象月 例:2026-02]
user-invocable: true
disable-model-invocation: true
---

# /review-monthly — 月次振り返りの生成

指定された月（デフォルトは今月）の日記と週次振り返りを分析し、月次レポートを生成する。

## 手順

1. 対象月を特定する（`$ARGUMENTS` で指定がなければ今月）
2. 以下のソースを読み込む:
   - `journal/YYYY/MM/` 配下の全日記
   - `reviews/weekly/` 配下の該当する週次振り返り
   - `mcp__life-rag__search(query="当月の重要トピック", layer="journal", date_from="月初", date_until="月末")` で月間の重要トピックを横断検索する
   - `mcp__life-rag__search(query="当月の学び", layer="knowledge")` で当月更新された knowledge/ も参照する
3. 以下の観点で分析・統合する:
   - **月のサマリー**: この月を一言で表すと
   - **主な出来事・成果**: 時系列でハイライトを整理
   - **学び・気づき**: knowledge/ や thoughts/ に記録された内容も参照
   - **目標への進捗**: `profile/goals.md` と照合
   - **来月への展望**: 次月に向けた方針・意識すべきこと
4. `reviews/monthly/YYYY-MM.md` に書き出す
5. 変更をコミットする

## フォーマット

```yaml
---
period: YYYY-MM
date: （生成日）
tags: [振り返り, 月次]
---
```

## 注意

- 週次振り返りが存在する場合はそれをベースにし、日記で補完する
- 存在しない場合は日記から直接分析する
- 定量的な情報（日記の日数、扱ったトピック数など）も含める
