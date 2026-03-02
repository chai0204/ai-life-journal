# ai-life-journal

AIチャットを通じて人生を記録・整理するシステム。[Claude Code](https://docs.anthropic.com/en/docs/claude-code)と会話するだけで、日記・知識・思考が自動的に構造化される。

## コンセプト

```
あなた ──(チャット)──> Claude Code ──> 日記（具体層）
                                   ──> 知識・思考（抽象層）
                                   ──> セマンティック検索（RAG）
```

- **チャットするだけ**: 「今日こういうことがあった」と話すだけで、日記と知識の両方に自動記録
- **2層構造**: 具体層（journal/）に時系列の記録、抽象層（knowledge/, thoughts/）にトピック別の蒸留
- **セマンティック検索**: 過去の記録をAIが意味ベースで検索。「あの時の考え」を自然言語で探せる
- **分身モード**: 蓄積された記録をもとに、AIがあなたの考え方・価値観を再現して応答（将来拡張）

## 前提条件

- **Claude Code**: [インストール手順](https://docs.anthropic.com/en/docs/claude-code/getting-started)
- **Git**
- **Python 3.12+**
- **uv**: セットアップ時に自動インストール
- **Ollama**: セットアップ時に自動インストール（セマンティック検索用の埋め込みモデルを実行）

## セットアップ

```bash
git clone https://github.com/chai0204/ai-life-journal
cd ai-life-journal
./setup.sh
```

`setup.sh` が以下を自動で行います:
1. uv のインストール（未インストールの場合）
2. Ollama のインストール（未インストールの場合）
3. `.mcp.json` の生成（Claude Code がRAGサーバーを認識するための設定）
4. Git post-commit hook のインストール（コミット時にRAGインデックスを自動更新）
5. Python依存関係のインストール
6. 埋め込みモデル（bge-m3）のダウンロード（約670MB）
7. 初回RAGインデックスの構築

## 使い方

### 基本的な使い方

```bash
# このディレクトリで Claude Code を起動
claude

# あとはチャットするだけ
# 「今日の出来事を話す」「学んだことを共有する」「考えを整理したい」
```

### スラッシュコマンド

| コマンド | 説明 |
|---|---|
| `/journal` | 日記を作成・追記する |
| `/recall` | AIの質問に答えながら今日を振り返り、日記を作成する |
| `/record` | 会話内容をまとめて記録する |
| `/distill` | 日記から知識・思考を抽出する |
| `/interviewer` | AIのインタビューで思考を引き出し、記録する |
| `/review-weekly` | 週次振り返りを生成する |
| `/review-monthly` | 月次振り返りを生成する |
| `/status` | 目標進捗・記録状況を表示する |

### 最初にやること

1. `profile/about.md` に自分の情報を記入する（AIがあなたを理解するための基盤）
2. `profile/goals.md` に中長期の目標を記入する（振り返り時に進捗を照合）
3. `/journal` や `/recall` で日記を書き始める

## ディレクトリ構成

```
ai-life-journal/
├── profile/       自分の情報（価値観・目標）
├── journal/       【具体層】日記（年/月/日付.md）
├── knowledge/     【抽象層・客観】ナレッジベース
├── thoughts/      【抽象層・主観】思考・経験・内省
├── works/         自分の作成物
├── references/    外部資料
├── reviews/       振り返り（週次・月次）
├── templates/     テンプレート集
├── rag-mcp/       RAGセマンティック検索サーバー
└── .claude/       Claude Code設定（skills, rules）
```

## 記憶の2層モデル

```
┌──────────────────────────────────────────┐
│  具体層（journal/）                      │
│  その日の出来事・考え・感情を時系列で記録 │
│  重複OK、感情・ニュアンスを保持          │
└───────────────┬──────────────────────────┘
                │ AIが要約・抽出・圧縮
┌───────────────▼──────────────────────────┐
│  抽象層                                  │
│  knowledge/ — 客観的な知識（事実・手法）  │
│  thoughts/  — 主観的な思考（教訓・方針）  │
└──────────────────────────────────────────┘
```

- 日記に書いた内容は、AIが知識（knowledge/）と思考（thoughts/）に自動で蒸留
- 抽象層はトピック別に整理され、継続的に更新される

## Termux（Android）でのセットアップ

スマートフォンからも使用可能。Termux の **proot-distro** を使って Ubuntu 環境内で実行する。

### proot-distro を使ったセットアップ

Termux は Android の Bionic libc を使用しており、多くの Python ネイティブ拡張（pydantic-core 等）が動作しない。proot-distro は root 不要で完全な glibc Linux 環境を提供し、すべてが通常の Linux と同様に動作する。

```bash
# Termux で proot-distro をインストール（初回のみ）
pkg install proot-distro
proot-distro install ubuntu

# Ubuntu 環境に入る
proot-distro login ubuntu

# Ubuntu 内で前提条件をインストール
apt update && apt install -y git python3 python3-pip python3-venv curl

# あとは通常のセットアップ
git clone https://github.com/chai0204/ai-life-journal
cd ai-life-journal
./setup.sh
```

### 日常的な使い方

```bash
# Termux を開いたら
proot-distro login ubuntu

# Ubuntu 内で Claude Code を起動
cd ai-life-journal
claude
```

### SSH 経由の場合（代替）

メインPCで Ollama と Claude Code を動かし、Termux からは SSH で接続する構成。パフォーマンスと安定性に優れる。

## カスタマイズ

- **テンプレート**: `templates/` 配下のファイルを編集して日記・知識のフォーマットを変更
- **ルール**: `.claude/rules/` でAIの書き方ガイドラインを調整
- **スキル**: `.claude/skills/` でスラッシュコマンドの振る舞いを変更
- **タグ戦略**: `CLAUDE.md` のタグ戦略セクションを参照

## 技術スタック

- **Claude Code**: AIチャットインターフェース
- **MCP (Model Context Protocol)**: Claude Code とRAGサーバーの連携プロトコル
- **Ollama + bge-m3**: ローカル埋め込みモデル（セマンティック検索用）
- **SQLite + sqlite-vec**: ベクトルデータベース
- **uv**: Python パッケージマネージャ

## ライセンス

MIT

