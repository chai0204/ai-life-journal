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

## セットアップ

### PC / VPS（Linux, macOS, WSL2）

#### 前提条件

| ソフトウェア | 備考 |
|---|---|
| **Git** | `apt install git` / `brew install git` 等 |
| **curl** | `apt install curl` 等（macOS は標準搭載） |

> **注意**: Python, Node.js, Ollama, Claude Code などは `setup.sh` が自動でインストールします。

#### 手順

```bash
# 1. リポジトリをクローン
git clone https://github.com/chai0204/ai-life-journal
cd ai-life-journal

# 2. セットアップ（すべての依存関係を一括インストール）
./setup.sh

# 3. Claude Code を起動
claude
```

`setup.sh` が以下を自動で行います:
1. システムパッケージのチェック（Python 3.12+, Node.js）
2. uv（Python パッケージマネージャ）のインストール
3. Ollama のインストール・起動
4. Claude Code のインストール
5. `.mcp.json` の生成（RAG サーバー設定）
6. Git post-commit hook のインストール
7. Python 依存関係のインストール
8. 埋め込みモデル（bge-m3, 約670MB）のダウンロード
9. 初回 RAG インデックスの構築

---

### スマートフォン（Android + Termux）

スマートフォンだけで使える構成。Termux 内の Ubuntu 仮想環境ですべてが動作する。

#### 全体の構成

```
┌──────────────────────────────────────────┐
│  Termux                                  │
│  └── proot-distro Ubuntu                 │
│      ├── Ollama + bge-m3                 │
│      ├── Claude Code                     │
│      ├── ai-life-journal                 │
│      └── RAG MCP サーバー                │
└──────────────────────────────────────────┘
```

すべてが Ubuntu 環境内で完結するため、セットアップと運用がシンプル。

#### Step 1: Termux をインストール

1. スマートフォンに [F-Droid](https://f-droid.org/) をインストールする
   - F-Droid は Android 用のオープンソースアプリストア
   - ブラウザで https://f-droid.org/ を開き、APK をダウンロードしてインストール
   - 「提供元不明のアプリ」の許可が必要（設定で有効にする）
2. F-Droid から **Termux** を検索してインストールする
   - Google Play 版の Termux は古く、正常に動作しないため **必ず F-Droid 版を使う**

> **注意**: Google Play 版の Termux は更新が停止しており、多くの機能が壊れています。必ず F-Droid 版を使用してください。

#### Step 2: Ubuntu 環境を構築

Termux アプリを開いて、以下を実行する。

```bash
# パッケージを更新
pkg update && pkg upgrade

# proot-distro をインストール
pkg install proot-distro

# Ubuntu をインストール
proot-distro install ubuntu
```

#### Step 3: Ubuntu 内でセットアップ

```bash
# Ubuntu 環境に入る
proot-distro login ubuntu

# ===== ここから先は Ubuntu 内 =====

# 最低限のパッケージをインストール（git と curl のみ）
apt update && apt install -y git curl ca-certificates

# リポジトリをクローン
git clone https://github.com/chai0204/ai-life-journal
cd ai-life-journal

# セットアップ（Python, Node.js, Ollama, Claude Code など全部入る）
./setup.sh
```

> **ポイント**: `setup.sh` が Python, Node.js, Ollama, Claude Code, RAG サーバーなど必要なものをすべて自動でインストールします。事前に入れるのは git と curl だけで OK です。

#### 日常的な使い方（毎回の起動手順）

```bash
# 1. Termux を開いて Ubuntu に入る
proot-distro login ubuntu

# 2. Ollama を起動して Claude Code を開始
cd ai-life-journal
ollama serve &
claude
```

> **ヒント**: Termux の通知バーで「Acquire wakelock」をタップすると、バックグラウンドでの強制終了を防げます。

---

### リモートサーバー経由（代替構成）

メイン PC やVPS で Ollama と Claude Code を動かし、スマートフォンからは SSH で接続する構成。パフォーマンスと安定性に優れる。

```bash
# スマートフォン（Termux）から SSH 接続
pkg install openssh
ssh user@your-server

# サーバー側で Claude Code を起動
cd ai-life-journal
claude
```

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

## トラブルシューティング

### Ollama が起動しない

```bash
# 手動で起動
ollama serve &

# ポートが使用中の場合
# → 既に起動しているので問題なし
# error: listen tcp 127.0.0.1:11434: bind: address already in use
```

### Embedding API が 500 エラーを返す

Ollama のモデルランナー (`serve`) が PATH に見つからない場合に発生する。`setup.sh` が自動修正するが、手動で修正する場合:

```bash
ln -sf "$(which ollama)" /usr/local/bin/serve
```

### setup.sh 実行後に RAG 検索が動かない

```bash
# Ollama が起動していることを確認してから再実行
ollama serve &
./setup.sh
```

### proot-distro で「cpu doesn't support 32-bit instructions」警告

```bash
# これは警告であり、インストール自体は正常に完了します
# 64-bit アプリケーションは問題なく動作します
```

## カスタマイズ

- **テンプレート**: `templates/` 配下のファイルを編集して日記・知識のフォーマットを変更
- **ルール**: `.claude/rules/` でAIの書き方ガイドラインを調整
- **スキル**: `.claude/skills/` でスラッシュコマンドの振る舞いを変更
- **タグ戦略**: `CLAUDE.md` のタグ戦略セクションを参照

## 技術スタック

- **Claude Code**: AIチャットインターフェース
- **MCP (Model Context Protocol)**: Claude Code とRAGサーバーの連携プロトコル
- **Ollama + bge-m3**: ローカル埋め込みモデル（セマンティック検索用）
- **SQLite**: ベクトルデータベース（純 Python ベクトル検索）
- **uv**: Python パッケージマネージャ

## ライセンス

MIT
