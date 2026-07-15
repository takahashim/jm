# jm

`jm`は、複数のソフトウェアプロジェクトにまたがる開発情報を、
ローカルの単一 SQLite データベースで一元管理する CLI ツールである。

タスク・不具合・設計課題・設計判断・調査・アイデア・疑問・検証・メモを同じ「Item」
モデルで扱い、リポジトリ・Git コミット・ファイル・他の Item と関連付ける。中心は
リポジトリではなく Item であり、リポジトリは関連付け対象の一つにすぎない。

詳細な設計は [SPEC.md](SPEC.md)、実装計画は [PLAN.md](PLAN.md) を参照。

## 特徴

- **リポジトリ非依存** — どのリポジトリにも属さない Item を持て、一つの Item を複数の
  リポジトリに関連付けられる。
- **人間と coding agent の両方が書く** — すべての書き込みはフラグ・`--stdin` で完結でき、
  TTY がなければハングせず失敗する。書き込みは冪等。作成者を記録する。
- **横断検索** — SQLite FTS5(trigram)で日本語を含む部分一致検索。
- **ready 判定** — `depends_on` を満たした着手可能な Item を計算で抽出。
- **JSON 出力** — `--json` を coding agent 向けの正式インターフェースとする。

## インストール

Ruby 3.2 以降と `git` が必要。

開発版を使う場合は、リポジトリを clone して Bundler 経由で実行する。

```bash
git clone <this-repo> ~/src/jm
cd ~/src/jm
bundle install
bundle exec jm init
```

RubyGems への公開後は `gem install jm` でインストールできる。

```bash
gem install jm
jm init
```

## クイックスタート

```bash
# 思いついたことを最短で捕捉(既定 type=note, state=inbox)
jm add "preceding axisでSIGSEGVする"

# type を指定して作成
jm add "WebSocketイベントをどのtask sourceへ配送するか" --type design

# 整理して着手
jm open 1
jm start 1

# 調査項目を作り、依存を張る
jm add "WPT調査" --type research      # => JM-000002
jm link 1 depends_on 2

# 調査を記録して完了
jm start 2
jm log 2 --kind finding --message "messageはPromise jobの後に配送される"
jm done 2 --resolution completed

# 1 が着手可能になる
jm list --ready
jm next --start

# 実装をコミット・ファイルと関連付ける
cd ~/src/dommy
jm repo add dommy .
jm repo link 1 dommy
jm ref add 1 file lib/dommy/websocket.rb --repo dommy
jm ref add 1 commit HEAD --repo dommy
jm done 1 --resolution accepted
```

## コマンド一覧

### Item

| コマンド | 説明 |
|---|---|
| `jm add [TITLE] [--type T] [--priority P] [--message M \| --stdin]` | Item 作成。TITLE 省略時は TTY があればエディタ |
| `jm show ID [--all]` | Item 詳細(tag/repo/relation/reference/entry)。`--all` で全 Entry |
| `jm list [フィルタ]` | 一覧。既定は inbox/open/active/blocked |
| `jm edit ID [--title T] [--type T] [--message M \| --stdin]` | 編集。無指定で本文をエディタ |
| `jm open/start/block/done/archive ID` | 状態遷移 |
| `jm priority ID <値\|別名>` | 優先度(別名: lowest/low/normal/high/highest) |
| `jm delete ID [--force]` | 物理削除(確認あり) |

`jm list` のフィルタ: `--state`, `--type`, `--tag`, `--repo`, `--ready`, `--archived`,
`--by NAME`, `--since 1d`, `--priority-min N`。複数条件は AND。

状態遷移のオプション: `done`/`archive` は `--resolution`、`block` は `--reason`(Entry 化)。

### 関連付け・履歴

| コマンド | 説明 |
|---|---|
| `jm log ID [--kind K] [--message M \| --stdin]` | Entry(時系列記録)を追加 |
| `jm link A <relation> B` / `jm unlink A <relation> B` | Item 間の関係。relation: `depends_on`(別名 `blocks`), `parent_of`(別名 `child_of`), `relates_to` |
| `jm links ID` | 関係を両方向で表示 |
| `jm tag add/remove ID NAME...` / `jm tag list` | タグ |
| `jm ref add ID KIND VALUE [--repo NAME]` / `jm ref list ID` / `jm ref remove ID REF_ID` | 参照(commit は完全 SHA へ解決、file はリポジトリ相対で保存) |
| `jm history ID [--show REV_ID]` | title/body の変更履歴 |

### Repository

| コマンド | 説明 |
|---|---|
| `jm repo add NAME PATH` | 登録(Git なら remote/既定ブランチを自動取得) |
| `jm repo list/show/edit/remove NAME` | 管理(remove しても Item は残る) |
| `jm repo link/unlink ID NAME` | Item との関連付け |

### 検索・ワークフロー

| コマンド | 説明 |
|---|---|
| `jm search QUERY [--type/--state/--tag/--repo]` | title/body/Entry を全文検索。引数をクォートするとフレーズ検索 |
| `jm next [--repo NAME] [--start]` | 着手可能な Item を1件(優先度高→古い順)。`--start` で active 化 |
| `jm stats` | state 別カウントと ready 数 |

### 保守

| コマンド | 説明 |
|---|---|
| `jm init` | DB 初期化・マイグレーション適用(スキーマを変更するのは init のみ) |
| `jm backup` | SQLite Backup API でスナップショット |
| `jm doctor [--rebuild-fts]` | 整合性検査(DB 内部)。`--rebuild-fts` で FTS 再構築 |

## 出力とスクリプト連携

- すべてのコマンドは `--json` で機械可読出力(`schema_version` 付き)。
- `--quiet`, `--no-color` も共通。
- エラーは標準エラー出力へ。終了コード: `0` 成功 / `1` 一般 / `2` 引数 / `3` 対象なし /
  `4` 整合性違反 / `5` DB / `6` Git。

## 設定

`~/.config/jm/config.toml`(環境変数が優先):

```toml
database = "~/.local/share/jm/jm.sqlite3"
editor = "nvim"

[defaults]
type = "note"
state = "inbox"
priority = 0
```

環境変数: `JM_DATABASE`, `JM_EDITOR`, `JM_AUTHOR`(作成者)。エディタ優先順位は
`JM_EDITOR` > config の `editor` > `VISUAL` > `EDITOR` > プラットフォーム既定。

## coding agent 向け

coding agent は SQLite を直接操作せず、`jm` コマンドと `--json` 出力のみを使う。
詳細は [AGENTS.md](AGENTS.md) を参照。

## 開発

```bash
bundle exec rake test     # テスト
bundle exec rubocop       # Lint
bundle exec rake install  # ローカルの gem を更新(下記参照)
```

本体を更新しても、インストール済みの `jm` コマンド(および各エージェントの `jm guide`)は
gem を入れ直すまで古いままになる。開発版を使っているときは `bundle exec rake install`
(または `gem build jm.gemspec && gem install ./jm-0.0.1.gem`)で入れ直す。RubyGems 公開後は
利用者が `gem update jm` で追従する。

データは `~/.local/share/jm/jm.sqlite3` に保存される(Git 管理しない)。バックアップは
同ディレクトリの `backups/` に置かれる。
