---
name: review-weekly
description: 今週の週次振り返りを生成する。該当週のjournal/を分析し、ハイライト・成果・改善点をまとめる。
argument-hint: [対象週 例:2026-W09]
user-invocable: true
disable-model-invocation: true
---

# /review-weekly — 週次振り返りの生成

指定された週（デフォルトは今週）の日記を分析し、振り返りレポートを生成する。

## 手順

1. 対象週を特定する（`$ARGUMENTS` で指定がなければ今週）
2. 対象週の月曜日〜日曜日の日付範囲を算出する
3. `journal/YYYY/MM/` から該当する日記ファイルをすべて読み込む
   - 加えて、`mcp__life-rag__search(query="今週の重要トピック", layer="journal", date_from="週初", date_until="週末")` で重要トピックを横断検索し、見落としがないか確認する
4. 以下の観点で分析する:
   - **今週のハイライト**: 特に印象的だった出来事・成果
   - **うまくいったこと**: ポジティブな結果・行動
   - **改善したいこと**: 課題・反省点
   - **来週の重点**: 次週に意識すべきこと
5. `reviews/weekly/YYYY-WXX.md` に `templates/review-weekly.md` のフォーマットで書き出す
6. `profile/goals.md` が記入されている場合、目標に対する進捗も言及する
7. 変更をコミットする

## 注意

- 日記のないフ日はスキップする
- オーナーの言葉をそのまま引用する箇所は「」で囲む
- 振り返りの文体はオーナーの口調に合わせる
