---
name: status
description: 現在の目標進捗・最近の記録状況をサマリー表示する。リポジトリの全体像を把握したいときに使用。
user-invocable: true
disable-model-invocation: true
---

# /status — 状況サマリーの表示

リポジトリの現在の状態と活動状況をまとめて報告する。

## 手順

1. 以下の情報を収集する:

### 目標の進捗
- `profile/goals.md` を読み、現在の目標一覧を表示する
- 各目標について `mcp__life-rag__search(query="目標キーワード", layer="journal")` および `layer="thoughts"` で関連する記述を検索し、進捗状況を把握する

### 最近の記録活動
- 直近1週間の journal/ ファイルの有無と日数
- knowledge/ の最終更新ファイル上位3件
- thoughts/ の最終更新ファイル上位3件
- works/ の最近の変更
- references/ の最近の変更

### 未処理の項目
- 未クローズの GitHub Issues（`gh issue list` で取得）
- 最後の週次振り返りからの経過日数
- 最後の月次振り返りからの経過日数

2. 以下のフォーマットで報告する:

```
## 📊 ステータスサマリー（YYYY-MM-DD）

### 目標
- [ ] 目標1 — 進捗メモ
- [ ] 目標2 — 進捗メモ

### 最近の活動（直近7日間）
- 日記: X/7日 記録済み
- knowledge: 更新X件
- thoughts: 更新X件

### 未処理
- オープンなIssue: X件
- 週次振り返り: 最終YYYY-WXX（X日前）
- 月次振り返り: 最終YYYY-MM（X日前）

### 提案
- （状況に応じた提案があれば）
```

## 注意

- 表示のみ。ファイルの変更やコミットは行わない
- 情報が存在しないセクションは「まだ記録がありません」と表示する
