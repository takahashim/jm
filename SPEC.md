# jm 仕様案

## 1. 概要

`jm` は、複数のソフトウェアプロジェクトにまたがる開発情報を、ローカルの単一データベースで一元管理するためのコマンドラインツールである。

管理対象は、一般的なIssueやTODOに限定しない。

* 実装タスク
* 不具合
* 設計上の課題
* 設計判断
* 調査
* アイデア
* 未解決の疑問
* 検証事項
* プロジェクト横断の知見
* coding agentへの作業指示
* 作業履歴
* Gitコミット、Pull Request、ファイルなどへの参照

データはリポジトリ内に配置せず、ユーザー単位のSQLiteデータベースに保存する。

リポジトリは情報の所有主体ではなく、開発項目に関連付けられる対象の一つとして扱う。

---

## 2. 目的

### 2.1 主目的

複数のリポジトリやプロジェクトに分散している開発上の情報を、一つの検索可能なローカルデータベースに集約する。

### 2.2 解決する問題

通常のリポジトリ単位のIssue管理では、次のような情報を扱いにくい。

* どのリポジトリに属するか未確定のアイデア
* 複数リポジトリにまたがる設計課題
* 実装前の調査や比較検討
* 個人的な設計メモ
* coding agentに渡す作業条件
* GitHub Issueにするほどではない作業
* 実装完了後にも参照したい調査結果
* リポジトリを移動・分割・統合しても残したい知識
* 複数プロジェクトを横断した優先順位
* 「今すぐ着手可能な項目」の抽出

`jm` はこれらを、リポジトリから独立した「開発項目」として管理する。

---

## 3. 非目標

初期バージョンでは、以下を目的としない。

* チーム向けのリアルタイム共同編集
* GitHub Issuesの完全な代替
* Webベースのプロジェクト管理
* CI/CDジョブキュー
* coding agentのプロセス管理
* 長大なビルドログの保存
* ソースコードそのもののバージョン管理
* 複数端末からの同時書き込み
* 複雑なワークフローエンジン
* Jiraのような任意項目・任意状態のカスタマイズ

初期段階では、単一ユーザー、単一SQLiteデータベース、CLI中心の運用に限定する。

---

## 4. 基本概念

### 4.1 Item

`jm` に保存される情報の基本単位をItemと呼ぶ。

Itemは次のような開発情報を表す。

* task
* bug
* design
* decision
* research
* idea
* question
* verification
* note

Itemは特定のリポジトリに所属しなくてもよい。

一つのItemを複数のリポジトリに関連付けてもよい。

### 4.2 Repository

ローカルまたはリモートのソースコードリポジトリを表す。

RepositoryはItemの格納場所ではなく、Itemとの関連付け対象である。

### 4.3 Relation

Item同士の意味的な関係を表す。

* depends_on（blocksは入力時の別名）
* parent_of
* relates_to

種類は意図的に3つに絞る。「実装する」「置き換える」「矛盾する」「重複する」などの意味は、relates_toで結んだうえで本文に書けば表現できる。ready判定に構造として必要なのはdepends_onだけである。

### 4.4 Reference

Itemと外部対象との関連を表す。

例:

* Gitコミット
* Pull Request
* GitHub Issue
* ローカルファイル
* リポジトリ内ファイル
* URL
* テスト
* ドキュメント
* 実行ログ

### 4.5 Entry

Itemに追記される時系列の記録をEntryと呼ぶ。

Item本文が現在の整理された情報を表すのに対し、Entryは調査、進捗、判断、失敗、発見などの履歴を表す。

---

## 5. 情報モデル

### 5.1 Itemの主要属性

各Itemは最低限、次の属性を持つ。

| 属性           | 内容            |
| ------------ | ------------- |
| ID           | 人間が扱える一意な識別子  |
| type         | Itemの種類       |
| title        | 短い題名          |
| body         | Markdown形式の本文 |
| state        | 現在の状態         |
| priority     | 優先度           |
| resolution   | 終了理由または結論     |
| created_by   | 作成者（人間またはagent名） |
| created_at   | 作成日時          |
| updated_at   | 更新日時          |
| started_at   | 着手日時          |
| completed_at | 完了日時          |
| archived_at  | アーカイブ日時       |

### 5.2 ID

IDは、データベース内部の整数ID（`items.id`）を唯一の一次キーとし、人間向けの公開IDはそこから**導出**する。公開IDを別カラムとして保存しない。

これは、`AUTOINCREMENT`で採番される`items.id`はINSERT前に確定しないため、`JM-000042`をINSERT時に格納しようとすると二段階更新や採番競合が必要になる問題を避けるためである。公開IDは`id`から都度整形すればよく、UNIQUE制約も採番競合も不要になる。

公開IDの標準表記は次の形式とする。

```text
JM-000001
JM-000002
JM-000003
```

表示時には先頭のゼロを省略してもよい。

```text
JM-1
JM-42
```

#### 正規化ルール

CLIが受け取るID文字列は、次の手順で内部整数IDへ正規化する。すべて同一のItemを指す。

```text
42
JM-42
jm-42
JM-000042
```

1. 前後の空白を除去する。
2. 先頭の`JM-`プレフィックスは**大文字小文字を区別せず**、あれば除去する。
3. 残りは10進整数として解釈する（先頭ゼロは無視する）。
4. 解釈できない場合は引数エラー（終了コード2）とする。

標準表記へ整形する場合は`JM-` + 6桁ゼロ埋めとする（桁あふれ時はゼロ埋めせずそのまま桁を伸ばす）。

連番は一つの中央データベース内で一意とする。

ランダムIDは採用しない。単一ユーザー・単一DBを前提とする限り、連番の方が入力しやすく、会話や作業指示でも扱いやすいためである。

### 5.3 Item type

初期状態では次のtypeを提供する。

```text
task
bug
design
decision
research
idea
question
verification
note
```

#### task

具体的な作業を表す。

#### bug

期待される動作と実際の動作の不一致を表す。

#### design

設計上の課題、制約、選択肢、方針案を表す。

#### decision

採用済みまたは却下済みの設計判断を表す。

#### research

調査対象、調査過程、結果を表す。

#### idea

まだ実施・設計・調査に分類できない着想を表す。

#### question

回答が必要な未解決事項を表す。

#### verification

仕様適合性、性能、互換性、再現性などの検証項目を表す。

#### note

他のtypeに分類しにくい開発上のメモを表す。

typeは後から変更可能とする。

### 5.4 State

初期状態では、全typeに共通の状態モデルを使用する。

```text
inbox
open
active
blocked
done
archived
```

#### inbox

未整理の状態。

タイトルや本文はあるが、分類、優先順位、関連付けなどが不十分でもよい。

#### open

整理済みだが未着手の状態。

#### active

現在取り組んでいる状態。

#### blocked

依存関係、外部条件、判断待ちなどにより進行できない状態。

#### done

作業、調査、判断などが完了した状態。

#### archived

現在の作業対象ではなく、通常の一覧から除外する状態。

状態遷移は厳密には強制しない。

ただし、CLIは通常、次の遷移を案内する。

```text
inbox → open → active → done → archived
                  ↓
               blocked
```

### 5.5 Resolution

`done`または`archived`になったItemには、任意でresolutionを設定できる。

resolutionは自由文字列とし、値のバリデーションは行わない。次を推奨値として例示するが、CLIは任意の値を受け付ける。

```text
completed
accepted
rejected
wontfix
duplicate
superseded
inconclusive
obsolete
```

typeとresolutionは独立している。

例:

```text
type=decision
state=done
resolution=accepted
```

```text
type=research
state=done
resolution=inconclusive
```

```text
type=bug
state=done
resolution=wontfix
```

### 5.6 created_by

ItemとEntryには作成者を記録する。

`jm`は人間とcoding agentの両方が書き込むツールであり、後から情報を読むときに「誰が書いたか」で信頼度と扱いを判断できる必要があるためである。

作成者は次の優先順で決定する。

1. `--by <name>`オプション
2. 環境変数`JM_AUTHOR`
3. どちらもなければNULL（人間による直接操作とみなす）

coding agentを起動する際は`JM_AUTHOR=claude`のように環境変数を設定させる。

`jm show`ではEntryごとに作成者を表示する。`jm list --by claude`のように作成者でフィルタできる。

---

## 6. 本文

Item本文はMarkdown形式の自由記述とする。

本文の構造はデータベース側で厳密には解釈しない。

例:

```markdown
## 背景

WebSocketから受信したイベントを、QuickJS上のイベントループへ
どの順序で配送するかが未定義になっている。

## 制約

- Promise jobとの順序が説明可能であること
- WPTの期待値と整合すること
- Rackバックエンドでも再現できること

## 選択肢

1. すべて通常のtask queueへ投入する
2. network task sourceを独立して持つ

## 現在の判断

未決定。

## 次の作業

関連するWPTを抽出する。
```

typeごとに推奨テンプレートを提供してもよいが、必須にはしない。

---

## 7. Entry

Itemには時系列でEntryを追加できる。

EntryはItem本文を書き換えず、調査過程や作業履歴を残すために使用する。

### 7.1 Entryの属性

| 属性         | 内容         |
| ---------- | ---------- |
| id         | Entryの内部ID |
| item_id    | 対象Item     |
| kind       | Entryの種類   |
| body       | Markdown本文 |
| created_by | 作成者（5.6参照） |
| created_at | 作成日時       |

### 7.2 Entry kind

kindは自由文字列とし、値のバリデーションは行わない。省略時は`comment`とする。

推奨値:

```text
comment
progress
finding
decision
failure
result
```

### 7.3 使用例

```bash
jm log JM-42 --kind finding
```

```markdown
WPTではWebSocket固有のtask source名は要求されていない。
ただし、messageイベントがmicrotask checkpointより後になることは確認できた。
```

Item本文には整理された現在の理解を記述し、Entryには時系列の詳細を残す。

---

## 8. Repository管理

### 8.1 Repositoryの属性

| 属性             | 内容      |
| -------------- | ------- |
| id             | 内部ID    |
| name           | 識別名     |
| path           | ローカルパス  |
| remote_url     | リモートURL |
| default_branch | 既定ブランチ  |
| created_at     | 登録日時    |
| updated_at     | 更新日時    |

### 8.2 Repository登録

```bash
jm repo add dommy ~/src/dommy
```

現在のディレクトリを登録する場合:

```bash
cd ~/src/dommy
jm repo add dommy .
```

Gitリポジトリの場合、可能であれば次を自動取得する。

* 絶対パス
* remote URL
* 既定ブランチ
* Gitのトップレベルディレクトリ

Gitリポジトリでないディレクトリも登録可能とする。

### 8.3 RepositoryとItemの関連

一つのItemに複数のRepositoryを関連付けられる。

関連は「関連しているかどうか」のみを表し、種類（primary/affectedなど）は持たない。主従や影響範囲のような意味は、必要なら本文に書く。分類語彙を減らし、関連付けの判断コストを下げるためである。

例:

```bash
jm repo link JM-42 dommy
jm repo link JM-42 dommy-js-quickjs
jm repo link JM-42 quickjs.rb
```

---

## 9. Item間の関係

Item間には有向関係を設定できる。

### 9.1 relation type

保存される正規形は次の3種のみとする。

```text
depends_on
parent_of
relates_to
```

入力時には`blocks`と`child_of`を別名として受け付ける（9.3で正規化）。これ以外の意味的関係（実装、置き換え、矛盾、重複など）は`relates_to` + 本文で表現する。

### 9.2 コマンド例

```bash
jm link JM-42 depends_on JM-12
jm link JM-42 relates_to JM-30
jm link JM-42 parent_of JM-51
```

### 9.3 逆関係と正規化

同じ意味を二重に保存しないよう、**保存時に正規形へ変換する**。

* `jm link A blocks B` は `B depends_on A` として保存する。
* `jm link A child_of B` は `B parent_of A` として保存する。
* `relates_to`は対称的な関係のため、`(source, target)`を昇順に並べ替えて重複保存を防ぐ。

表示時には、必要に応じて逆方向の意味を導出する。

```text
保存: JM-42 depends_on JM-12
表示: JM-42 depends_on JM-12
      JM-12 blocks JM-42
```

### 9.4 循環依存

`depends_on`関係については循環を禁止する。9.3により`blocks`も`depends_on`へ正規化されるため、循環検査は正規形の`depends_on`のみを対象とすればよい。

検査は再帰CTEでリンク追加時に行い、次のような閉路を作る操作はエラー（整合性違反、終了コード4）とする。

```text
JM-1 depends_on JM-2
JM-2 depends_on JM-3
JM-3 depends_on JM-1
```

`relates_to`など、循環しても問題ない関係は許可する。

---

## 10. Reference

Itemは外部対象への参照を複数持てる。

### 10.1 Reference kind

kindは自由文字列とし、値のバリデーションは行わない。推奨値:

```text
url
commit
branch
pr
issue
file
test
document
log
command
```

ただし`commit`と`file`は、10.3・10.4の保存規則（完全SHA解決、repository相対パス化）の対象として特別に扱う。

### 10.2 参照例

```bash
jm ref add JM-42 commit abc1234 --repo dommy
jm ref add JM-42 file lib/dommy/event_loop.rb --repo dommy
jm ref add JM-42 test test/websocket/message_test.rb --repo dommy
jm ref add JM-42 url https://example.com/spec
jm ref add JM-42 pr 123 --repo dommy
```

### 10.3 リポジトリ内ファイル

リポジトリ内ファイルは、絶対パスではなく次の組として保存する。

```text
repository_id
relative_path
```

これにより、リポジトリの移動に耐えられるようにする。

### 10.4 Git参照

commit、branch、PRなどは、可能な限りRepositoryと関連付ける。

コミット参照には、短縮SHAではなく完全なSHAを保存する。

表示時には短縮してよい。

---

## 11. Tag

Itemには複数のTagを付与できる。

Tagは自由入力とする。

例:

```text
event-loop
websocket
xpath
performance
wpt
quickjs
compatibility
security
agent-ready
```

コマンド例:

```bash
jm tag add JM-42 websocket event-loop wpt
jm tag remove JM-42 wpt
```

Tag名は小文字化しない。入力値を保存する。

ただし検索・一意性判定は大文字小文字を区別しない（`tags.name`は`COLLATE NOCASE UNIQUE`）。

このため、`WebSocket`と`websocket`は同一Tagとして扱われ、**最初に登録された表記が保存される**（後続の異なる表記では既存行を再利用し、表記は更新しない）。表記を変更したい場合は明示的なリネーム操作を用いる。

---

## 12. 優先度

priorityは整数として保存する。

初期値は0とする。

推奨範囲は次のとおり。

```text
-100 ～ 100
```

CLIでは別名として次を提供してもよい。

| 名前      |   値 |
| ------- | --: |
| lowest  | -20 |
| low     | -10 |
| normal  |   0 |
| high    |  10 |
| highest |  20 |

例:

```bash
jm priority JM-42 high
jm priority JM-42 15
```

値が大きいほど優先度が高い。

---

## 13. Ready判定

「着手可能なItem」をreadyと呼ぶ。

Itemは次の条件をすべて満たす場合にreadyである。

* stateが`open`
* `depends_on`先がすべて`done`または`archived`
* blocked状態ではない
* アーカイブされていない

readyは保存される状態ではなく、問い合わせ時に計算される属性とする。

```bash
jm list --ready
```

---

## 14. CLI仕様

## 14.1 基本形式

```text
jm <command> [arguments] [options]
```

### 14.1.1 非対話実行の保証

主な書き手はcoding agentである。すべての書き込み操作は、エディタや対話プロンプトなしにフラグと`--stdin`だけで完結できることを保証する。

* エディタ起動が必要な状況（引数不足）で標準入力がTTYでない場合、エディタを起動せず引数エラー（終了コード2）で即座に失敗する。ハングさせない。
* 確認プロンプト（`jm delete`など）は、TTYでない場合は`--force`がなければエラーとする。

### 14.1.2 冪等性

エージェントはリトライする。すでに目的の状態にある操作は、エラーではなく成功（no-op）とする。

* `jm tag add`: すでに付与済みのTag → 成功
* `jm ref add`: 同一kind・同一値のReferenceが存在 → 成功（重複行を作らない）
* `jm link`: 同一関係が存在 → 成功
* `jm repo link`: すでに関連付け済み → 成功
* `jm start`: すでにactive → 成功（started_atは変更しない）
* `jm done`: すでにdone → 成功（completed_atは変更しない）

### 14.1.3 本文入力の排他

本文（Item body、Entry body）を受け取るコマンドでは、入力方法は次の3つのうち**ちょうど一つ**とする。

1. `--message "..."` — 引数で直接指定
2. `--stdin` — 標準入力から読む
3. 無指定 — エディタを起動（TTYがある場合のみ。なければ14.1.1により終了コード2）

複数を同時に指定した場合（例: `--stdin`と`--message`の併用）は引数エラー（終了コード2）とする。これによりAgent利用・エディタ利用・Web経由の更新のいずれでも入力経路が一意に定まる。

## 14.2 Item作成

最速の作成手段を最短にする。位置引数1つをtitleとして受け取る。

```bash
jm add "preceding axisでSIGSEGVする"
```

typeは既定で`note`、stateは既定で`inbox`となる（21章 defaults）。思いつきを捨てないため、フラグなしで保存できることを保証する。

typeやその他の属性を指定する場合:

```bash
jm add "preceding axisでSIGSEGVする" --type bug
jm add "WebSocketイベント配送" --type design --repo dommy
```

本文を標準入力から受け取る場合:

```bash
cat note.md | jm add "WPT調査" --type research --stdin
```

titleを省略してエディタで作成する場合（TTYがある場合のみ）:

```bash
jm add
```

作成結果は標準出力に公開IDを出す。

```text
Created JM-42
```

`--json`指定時は、作成されたItem全体（id含む）をJSONで返す。エージェントに`Created JM-42`のテキストをパースさせない。

```bash
jm add "..." --type task --json
```

---

## 14.3 表示

```bash
jm show JM-42
jm show 42
```

表示内容:

* ID
* type
* state
* resolution
* priority
* title
* tags
* repositories
* relations
* references
* created_at
* updated_at
* 本文
* 最近のEntry

Entryをすべて表示する場合:

```bash
jm show JM-42 --all
```

機械可読形式:

```bash
jm show JM-42 --json
```

---

## 14.4 編集

```bash
jm edit JM-42
```

エディタでMarkdown本文のみを開く。frontmatterによるメタデータ編集は行わない（15章）。

メタデータはフラグまたは専用コマンドで変更する。

```bash
jm edit JM-42 --title "WebSocket event delivery"
jm edit JM-42 --type design
jm priority JM-42 high
```

本文を標準入力から置き換える場合:

```bash
cat body.md | jm edit JM-42 --stdin
```

タイムスタンプの訂正もフラグで行う。`--started-at` / `--completed-at` / `--archived-at`は、`--at`(14.6.1)と同じ日時形式を受け付け、`done`/`start`/`archive`の`--at`が「未設定のときだけ打刻」する冪等な挙動なのに対し、**既存値を上書きする**。stateは変更しない。誤った打刻の訂正や、後から正確な日時が判明したときに使う。

```bash
jm edit JM-42 --completed-at 2026-07-15
```

タイムスタンプ変更はRevision化しない（Revisionはtitle/bodyのみ、17章）。

---

## 14.5 一覧

```bash
jm list
```

既定では、`inbox`、`open`、`active`、`blocked`を表示する。

フィルタ例:

```bash
jm list --state open
jm list --type design
jm list --repo dommy
jm list --tag event-loop
jm list --ready
jm list --priority-min 10
jm list --archived
jm list --by claude
jm list --since 1d
```

`--by`は作成者（5.6）で、`--since`は更新日時で絞り込む。組み合わせることで「エージェントが今日触ったItem」のようなレビュー用途に使える。

複数条件はANDとして扱う。

```bash
jm list --type task --repo dommy --state open
```

並び順の既定値:

1. state（業務順ランク昇順）
2. priority降順
3. updated_at降順
4. ID昇順

stateはテキストenumのため、文字列順ではなく次の**業務順ランク**で並べる。

| state   | rank |
| ------- | ---: |
| inbox   |    0 |
| active  |    1 |
| blocked |    2 |
| open    |    3 |
| done    |    4 |
| archived |   5 |

実装上は`CASE state WHEN ... END`で数値ランクへ写像してソートする。

並び順指定:

```bash
jm list --sort priority
jm list --sort updated
jm list --sort created
jm list --sort id
```

---

## 14.6 状態変更

```bash
jm open JM-42
jm start JM-42
jm block JM-42
jm done JM-42
jm archive JM-42
```

`start`はstateを`active`にし、未設定ならstarted_atを記録する。

`done`はstateを`done`にし、completed_atを記録する。

resolutionを指定できる。

```bash
jm done JM-42 --resolution completed
jm done JM-42 --resolution accepted
jm archive JM-42 --resolution obsolete
```

blocked理由をEntryとして追加できる。

```bash
jm block JM-42 --reason "QuickJS側のAPI決定待ち"
```

### 14.6.1 タイムスタンプのバックデート

すでに終わった作業を後から記録する場合など、タイムスタンプを打刻する遷移（`start` / `done` / `archive`）は`--at`で日時を上書きできる。粗い粒度を許容し、欠けた桁は最も早い時刻へ丸める（`--at 2026` → `2026-01-01T00:00:00Z`、`--at 2026-01` → `2026-01-01T00:00:00Z`、`--at 2026-01-20` → `2026-01-20T00:00:00Z`）。完全なISO8601（`2026-01-20T09:00:00Z`）も受け付け、UTCへ正規化して保存する。解釈できない値は引数エラー（終了コード2）とする。

```bash
jm done JM-42 --resolution completed --at 2026-01
```

`--at`は対象のタイムスタンプが未設定の場合のみ適用する。すでに打刻済みのItemでは上書きしない（14.1.2の冪等性と整合）。作成日時（created_at）は常に記録時刻とし、バックデートの対象としない。

---

## 14.7 Entry追加

```bash
jm log JM-42
```

エディタを起動する。

直接指定:

```bash
jm log JM-42 --kind progress --message "WPTを12件確認した"
```

標準入力:

```bash
cat findings.md | jm log JM-42 --kind finding --stdin
```

---

## 14.8 検索

```bash
jm search websocket
```

全文検索の対象は次の3つに限定する。

* title
* body
* Entry本文

Tag、Repository、Reference値は全文検索の対象とせず、専用フィルタで絞り込む。これらは構造化された属性であり、単一のFTSクエリに混ぜると順位付けと重複排除を仕様化する必要が生じるためである。

```bash
jm search websocket --tag event-loop --repo dommy
```

完全一致フレーズ:

```bash
jm search '"event loop"'
```

typeやstateとの組み合わせ:

```bash
jm search websocket --type design --state open
```

入力は常に安全にエスケープして検索する。FTS5の生クエリ構文を公開する高度なモードは初期版では提供しない（構文・エラー表示・検索意味論をAPIとして背負わないため）。

---

## 14.9 Item間リンク

```bash
jm link JM-42 depends_on JM-12
jm unlink JM-42 depends_on JM-12
```

関連一覧:

```bash
jm links JM-42
```

---

## 14.10 Repository操作

```bash
jm repo list
jm repo add dommy ~/src/dommy
jm repo show dommy
jm repo edit dommy
jm repo remove dommy
jm repo link JM-42 dommy
jm repo unlink JM-42 dommy
```

Repository削除時もItemは削除しない。

関連付けだけを削除する。

---

## 14.11 Reference操作

```bash
jm ref list JM-42
jm ref add JM-42 url https://example.com
jm ref add JM-42 commit abc123 --repo dommy
jm ref remove JM-42 REF_ID
```

---

## 14.12 Tag操作

```bash
jm tag add JM-42 websocket event-loop
jm tag remove JM-42 event-loop
jm tag list
```

---

## 14.13 次に着手するItem

```bash
jm next
```

readyなItemから、次の基準で一件を選ぶ。

1. priorityが高い
2. 更新日時が古い
3. IDが小さい

`jm list`の既定ソートが更新日時**降順**（新しい順）であるのに対し、`jm next`は更新日時**昇順**（古い順）で選ぶ。これは「長く放置され着手可能なもの」を優先的に拾い上げるためであり、意図的な差である。

Repositoryを限定できる。

```bash
jm next --repo dommy
```

`jm next`は自動的にはstateを変更しない。

開始する場合:

```bash
jm next --start
```

---

## 14.14 統計

```bash
jm stats
```

表示例:

```text
Inbox:    12
Open:     31
Active:    3
Blocked:   5
Done:    248
Archived: 87

Ready:    19
```

state別カウントとready数のみを提供する。Repository別・type別などの集計軸は持たない。

---

## 14.15 Doctor

データベースや参照の整合性を確認する。

```bash
jm doctor
```

v1の検査項目は、DB内部で完結するものに限定する。

* SQLite integrity check
* 外部キー整合性
* FTSインデックスの不整合
* depends_on循環
* 存在しないRepository参照
* doneだがcompleted_atがないItem
* activeだがstarted_atがないItem

次の**外部状態の検査**は後回しとする（30章）。ファイルシステムやGitの状態はDBと独立に変化し、検査の維持コストが高いためである。

* 存在しないローカルパス
* 存在しないファイル参照
* Gitリポジトリのremote変更

doctorは検査と報告のみを行う。自動修復（`--fix`）は提供しない。修復はエラー内容に基づき手動（またはエージェント経由の通常コマンド）で行う。例外としてFTSインデックスの再構築のみ`jm doctor --rebuild-fts`を提供する（19.1）。

---

## 15. エディタ連携

エディタは次の優先順で決定する。

1. `JM_EDITOR`（環境変数）
2. 設定ファイルの`editor`（21章 config.toml）
3. `VISUAL`（環境変数）
4. `EDITOR`（環境変数）
5. プラットフォーム既定値

環境変数`JM_EDITOR`が設定ファイルより優先される点は、21章「環境変数は設定ファイルより優先する」と整合する。

編集時は一時Markdownファイルを作成し、**本文のみ**を編集対象とする。

frontmatterによるメタデータ編集は提供しない。type、state、priority、tagなどのメタデータはCLIのフラグ・コマンドで変更する。frontmatterの解析・検証・カラムへの分解という実装を持たないためであり、また主な書き手であるcoding agentにとってはフラグの方が確実である。

エディタで開かれる一時ファイルは本文そのものであり、保存内容がそのままbodyになる。titleの抽出などの解釈は行わない。

---

## 16. coding agent向けインターフェース

coding agentには、SQLiteを直接操作させず、`jm`コマンドだけを利用させる。

`--json`出力はエージェント向けの正式インターフェースであるため、後方互換性のため出力に**スキーマバージョン**を含める。単一オブジェクト出力ではトップレベルに、一覧出力では包むオブジェクトに`schema_version`を付与する（配列そのものではなく`{ "schema_version": 1, "items": [...] }`の形式）。破壊的変更時にのみ整数を繰り上げる。

### 16.1 読み取り

```bash
jm show JM-42 --json
jm list --ready --json
jm search websocket --json
jm repo show dommy --json
```

### 16.2 更新

```bash
jm start JM-42
jm log JM-42 --kind progress --message "..."
jm done JM-42 --resolution completed
jm ref add JM-42 commit <sha> --repo dommy
```

### 16.3 Agent向け推奨手順

1. `jm show ID --json`でItemを読む
2. 関連Itemとdepends_onを確認する
3. 対象Repositoryを確認する
4. `jm start ID`を実行する
5. 実装・調査を行う
6. 重要な発見を`jm log`へ追加する
7. commitやfileを`jm ref add`で関連付ける
8. 完了条件を確認する
9. `jm done ID`を実行する

エージェントには次を指示する。

* `JM_AUTHOR`を設定して実行する（5.6）
* Entryには**要点のみ**を書く。ビルドログやコマンド出力の転記は禁止する（3章 非目標と整合）。詳細が必要な場合はログファイルへの`jm ref add`で参照する

### 16.4 Agentによる本文更新

AgentがItem本文を更新する場合は、通常の編集経路（14.4）と同じ`jm edit --stdin`を用いる。

```bash
cat body.md | jm edit JM-42 --stdin
```

専用の`jm body`コマンドは設けない。更新経路を一つにすることで、Revision保存のフックも一箇所に集約される。本文更新時は既存本文が自動的にrevisionとして保存される（17章）。

---

## 17. Revision

Itemのtitleまたはbodyが変更された場合、以前の内容をRevisionとして保存する。

### 17.1 Revisionの属性

| 属性         | 内容           |
| ---------- | ------------ |
| id         | Revision ID  |
| item_id    | 対象Item       |
| title      | 変更前のtitle    |
| body       | 変更前のbody     |
| created_at | Revision作成日時 |

### 17.2 Revision操作

```bash
jm history JM-42
jm history JM-42 --show REVISION_ID
```

復元専用コマンドは提供しない。復元が必要な場合は`jm history --show`で旧内容を表示し、`jm edit --stdin`等で書き戻す。

Revisionの目的は、coding agentが`jm edit --stdin`で本文を上書きした際に以前の内容を失わないための保険である。

すべてのメタデータ変更を履歴化するのではなく、titleとbodyのみを対象とする。状態変更などのメタデータ変更は履歴化しない。blocked理由のような文脈はEntryとして残す。

---

## 18. データベース

### 18.1 保存場所

既定の保存場所:

Linux:

```text
$XDG_DATA_HOME/jm/jm.sqlite3
```

`XDG_DATA_HOME`がない場合:

```text
~/.local/share/jm/jm.sqlite3
```

macOSでも初期仕様ではXDG互換の場所を使用してよい。

設定で変更可能とする。

```text
JM_DATABASE=/path/to/jm.sqlite3
```

### 18.2 SQLite設定

推奨設定:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
```

#### マイグレーション適用方針

スキーマを変更する（マイグレーションを適用する）のは`jm init`および将来の`jm migrate`のみとする。通常のコマンドは接続時に`schema_migrations`のバージョンを**検査するだけ**とし、未適用のマイグレーションがあれば書き換えを行わずに終了コード5で失敗し、`jm migrate`の実行を促す。

読み取り操作が暗黙にDBを書き換えないことを保証するためであり、将来の読み取り専用Webビューアが閲覧要求のたびにスキーマを変更してしまう事故も防げる。

#### FTS5とtrigramの可用性検証

`jm init`時に、リンクされたSQLiteでFTS5拡張とtrigram tokenizerが実際に利用可能かを検証する（一時的な仮想テーブル作成を試みる）。利用できない場合は、原因が分かるメッセージとともに終了コード5で明瞭に失敗させる。3文字未満のクエリがFTSにヒットしない挙動は仕様どおりで、LIKEフォールバックで補う（19章）。

### 18.3 スキーマ概要

主要テーブル:

```text
items
entries
item_revisions
repositories
item_repositories
item_relations
item_references
tags
item_tags
schema_migrations
meta
```

`references`はSQLiteの予約語であるため、テーブル名は`item_references`とする。

全文検索:

```text
items_fts
entries_fts
```

`meta`は、スキーマバージョン以外のプロセス状態（最終バックアップ日時など）を保持するkey-valueテーブルである。`schema_migrations`は適用済みマイグレーションの記録に専念させ、可変状態は`meta`に置く。

### 18.4 items

公開ID（`JM-000042`）は`id`から導出するため、専用カラムは持たない（5.2参照）。

```sql
CREATE TABLE items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'inbox',
  priority INTEGER NOT NULL DEFAULT 0,
  resolution TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  archived_at TEXT
);
```

### 18.5 entries

```sql
CREATE TABLE entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'comment',
  body TEXT NOT NULL,
  created_by TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);
```

### 18.6 repositories

```sql
CREATE TABLE repositories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  path TEXT,
  remote_url TEXT,
  default_branch TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### 18.7 item_repositories

```sql
CREATE TABLE item_repositories (
  item_id INTEGER NOT NULL,
  repository_id INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (item_id, repository_id),
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (repository_id) REFERENCES repositories(id) ON DELETE CASCADE
);
```

### 18.8 item_relations

```sql
CREATE TABLE item_relations (
  source_item_id INTEGER NOT NULL,
  target_item_id INTEGER NOT NULL,
  relation TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (source_item_id, target_item_id, relation),
  FOREIGN KEY (source_item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (target_item_id) REFERENCES items(id) ON DELETE CASCADE,
  CHECK (source_item_id != target_item_id)
);
```

### 18.9 item_references

```sql
CREATE TABLE item_references (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  repository_id INTEGER,
  kind TEXT NOT NULL,
  value TEXT NOT NULL,
  label TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (repository_id) REFERENCES repositories(id) ON DELETE SET NULL
);

-- 冪等性の担保（14.1.2）。同一Item・kind・value・repositoryを重複させない。
-- repository_idがNULLでも重複を弾くよう、式インデックスでNULLを固定値へ写像する。
CREATE UNIQUE INDEX idx_item_references_unique
  ON item_references (item_id, kind, value, COALESCE(repository_id, -1));

CREATE INDEX idx_item_references_item ON item_references (item_id);
```

`repository`が異なる同一`kind`・`value`（例: 別リポジトリの同名ファイル、フォーク間の同一SHA）は**別のReference**として扱う。したがって一意キーは`(item_id, kind, value, repository_id)`とする。素朴なUNIQUE制約ではNULLの`repository_id`同士が重複を許すため、`COALESCE(repository_id, -1)`による式インデックスで担保する。`jm ref add`は`INSERT ... ON CONFLICT DO NOTHING`で冪等に挿入する。

### 18.10 tags

```sql
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE COLLATE NOCASE
);
```

### 18.11 item_tags

```sql
CREATE TABLE item_tags (
  item_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (item_id, tag_id),
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
```

### 18.12 meta

スキーマバージョン以外の可変なプロセス状態を保持するkey-valueテーブル。

```sql
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

初期に想定するキー:

```text
json_schema_version  --json出力の現行スキーマバージョン
```

`last_backup_at`（自動バックアップ判定用）は、自動バックアップを実装する将来版で追加する。

### 18.13 item_revisions

Itemのtitleまたはbodyが変更される直前の内容を保存する（17章）。

```sql
CREATE TABLE item_revisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

CREATE INDEX idx_item_revisions_item ON item_revisions (item_id, created_at);
```

`Store::Items#update`がtitle/bodyの変更を検知したときのみ、変更前の`(title, body)`をこのテーブルへ退避する。メタデータのみの変更ではrevisionを作らない。

---

## 19. 全文検索

SQLite FTS5を利用する。

検索対象:

* Item title
* Item body
* Entry body

### 19.1 インデックス構成と同期

FTSテーブルは**external-content方式**（`content=`）で本体テーブルを参照し、本体を二重に保存しない。

tokenizerには**trigram**を使用する。本文・タイトルの多くは日本語であり、unicode61では日本語を分かち書きできず検索がほぼ機能しないためである。trigramはSQLite組み込みであり、日本語を含む部分文字列検索が可能になる。

```sql
CREATE VIRTUAL TABLE items_fts USING fts5(
  title, body,
  content='items', content_rowid='id',
  tokenize='trigram'
);

CREATE VIRTUAL TABLE entries_fts USING fts5(
  body,
  content='entries', content_rowid='id',
  tokenize='trigram'
);
```

trigramの制約として、3文字未満のクエリはFTSで検索できない。この場合は`LIKE`検索へ自動的にフォールバックする。

本体テーブルとの同期は**トリガー**で行う。`items`と`entries`それぞれに`AFTER INSERT` / `AFTER UPDATE` / `AFTER DELETE`トリガーを定義し、external-content FTSの規約に従って`items_fts`へ`delete`／`insert`を発行する。

title・body以外のカラムだけが変わったUPDATEでも問題ないよう、UPDATEトリガーは旧行を`delete`してから新行を`insert`する。

doctorの「FTSインデックスの不整合」チェックは、`items_fts`の`integrity-check`コマンドおよび本体行数との突き合わせで検出し、`jm doctor --rebuild-fts`で`rebuild`により再構築する。

titleはbodyより高い重みを持たせる。重み付けは検索時に`bm25(items_fts, 10.0, 1.0)`のようにカラム重みを指定して行う（FTS5にカラム重みの永続設定はないため、クエリ側で指定する）。

検索結果の既定順位は、概ね次を組み合わせる。

* FTS5 relevance
* priority
* state
* updated_at

全文検索の対象はtitle・body・Entry本文のみとする（14.8）。Tag・Repositoryは`--tag`・`--repo`フィルタで別途絞り込み、FTSクエリには混ぜない。

3文字未満のクエリはtrigramでヒットしないため、`LIKE`検索へ自動的にフォールバックする。

日本語形態素解析による関連度の高い検索は、将来拡張とする。

---

## 20. バックアップ

### 20.1 手動バックアップ

```bash
jm backup
```

既定の保存先:

```text
~/.local/share/jm/backups/
```

ファイル名:

```text
jm-20260715-173012.sqlite3
```

SQLite Backup APIまたは`.backup`相当の処理を利用する。

単純なファイルコピーは使用しない。

v1では手動`jm backup`のみを提供する。次はコアの完成を優先するため後回しとする（30章）。

* 自動バックアップ（書き込み前後の自動実行）と`keep`による世代削除
* JSONLエクスポート（`jm export`）
* JSONLインポート

手動`jm backup`（SQLiteファイルのスナップショット）だけで、v1の消失対策としては足りる。

---

## 21. 設定

設定ファイル:

```text
$XDG_CONFIG_HOME/jm/config.toml
```

例:

```toml
database = "~/.local/share/jm/jm.sqlite3"
editor = "nvim"

[display]
pager = true
date_format = "%Y-%m-%d %H:%M"
default_limit = 50

[defaults]
type = "note"
state = "inbox"
priority = 0
```

環境変数は設定ファイルより優先する。

`[backup]`セクション（`enabled` / `interval` / `keep`）は自動バックアップ用であり、自動バックアップを実装する将来版で追加する。v1では解釈しない。

---

## 22. 出力形式

通常出力は人間向けのテキストとする。

機械処理用に共通オプションを提供する。

```bash
--json
--quiet
--no-color
```

JSON出力には、後方互換のため`schema_version`（整数）を含める（16章参照）。

* 単一オブジェクト出力: トップレベルに`schema_version`を含むオブジェクト。
* 一覧系コマンド: `{ "schema_version": 1, "items": [...] }` の形式でラップする。ペイロード本体は配列とし、コマンドに応じたキー（`items`など）に格納する。

JSONL形式（`--jsonl`や`jm export`）はv1では提供しない（20章）。

エラーは標準エラー出力へ出す。

終了コード:

| コード | 意味              |
| --: | --------------- |
|   0 | 成功              |
|   1 | 一般エラー           |
|   2 | 引数エラー           |
|   3 | 対象が存在しない        |
|   4 | 整合性違反           |
|   5 | データベースエラー       |
|   6 | 外部コマンド・Git関連エラー |

---

## 23. 削除

Itemは通常、物理削除しない。

不要なItemは`archived`へ変更する。

物理削除は明示的なコマンドでのみ行う。

```bash
jm delete JM-42
```

確認を要求する。

```bash
jm delete JM-42 --force
```

削除時には、Entry、Relation、Reference、Tag関連付け、Revisionも削除する。

Repository削除時にはItemを削除しない。

---

## 24. Gitとの関係

`jm` のデータベースはGitで管理しない。

ただし、ItemからGitの情報を参照できる。

### 24.1 Gitから自動取得できる情報

Repository内で実行された場合、次を推測できる。

* Repository
* 現在のbranch
* HEAD commit
* 相対ファイルパス
* remote URL

例:

```bash
cd ~/src/dommy
jm ref add JM-42 commit HEAD
```

`HEAD`を完全なcommit SHAへ解決して保存する。

### 24.2 コミットメッセージとの連携

任意でコミットメッセージへItem IDを含める。

```text
Implement WebSocket message delivery

Refs: JM-42
```

`jm`自身はGit hookを必須にしない。

将来的に次を提供できる。

```bash
jm git scan
```

これにより、コミットメッセージ中の`JM-42`を検出し、自動的にReferenceを追加する。

---

## 25. セキュリティとプライバシー

`jm` はローカル保存を基本とする。

データベースには、非公開の設計情報、セキュリティ上の調査、内部URL、個人的なメモが含まれる可能性がある。

初期仕様ではDB自体の暗号化は行わない。

利用者は次を考慮する。

* OSのディスク暗号化
* バックアップ先のアクセス制御
* クラウド同期の有無
* coding agentへ渡す情報の範囲

将来的にItem単位のsecret属性を追加してもよい。

---

## 26. 初期リリース範囲

最初の実用版では、次の機能に限定する。

### 必須

* SQLiteデータベース初期化
* Item作成（位置引数title、--json出力）
* Item表示
* Item編集（本文のみエディタ、メタデータはフラグ）
* Item一覧
* 状態変更
* type、priority、resolution
* Entry追加
* created_by記録
* 非対話実行の保証と冪等性（14.1.1、14.1.2）
* Repository登録
* ItemとRepositoryの関連付け
* Item間relation（3種）
* Tag
* Reference
* 全文検索（trigram、title/body/Entryのみ）
* ready判定
* JSON出力（schema_version付き）
* 手動backup
* Revision自動保存とjm history
* doctor（DB内部の検査のみ）

### 後回し

* 自動バックアップと世代削除
* JSONLエクスポート／インポート
* doctorの外部状態検査（パス・ファイル・Git remote）
* Gitコミット自動スキャン
* TUI
* Web UI
* coding agentのロック
* テンプレート機能
* 日本語形態素解析による検索

---

## 27. 最小コマンドセット

初期実装をさらに絞る場合、次のコマンドから開始する。

```text
jm add
jm show
jm edit
jm list
jm search
jm start
jm block
jm done
jm archive
jm log
jm link
jm repo
jm ref
jm tag
jm next
jm backup
jm doctor
```

---

## 28. 利用例

### 28.1 設計課題を登録する

```bash
jm add "WebSocketイベントをどのtask sourceへ配送するか" \
  --type design \
  --repo dommy
```

### 28.2 関連リポジトリを追加する

```bash
jm repo link JM-42 dommy-js-quickjs
jm repo link JM-42 quickjs.rb
```

### 28.3 調査項目を作成する

```bash
jm add "WebSocketのイベント順序に関するWPT調査" \
  --type research
```

作成されたIDが`JM-43`だった場合:

```bash
jm link JM-42 depends_on JM-43
```

### 28.4 調査結果を記録する

```bash
jm start JM-43
jm log JM-43 --kind finding --message \
  "messageイベントはPromise jobの後に配送される必要がある"
```

### 28.5 調査を完了する

```bash
jm done JM-43 --resolution completed
```

これにより`JM-42`がreadyになる。

```bash
jm list --ready
```

### 28.6 実装とコミットを関連付ける

```bash
cd ~/src/dommy
jm start JM-42
jm ref add JM-42 file lib/dommy/websocket.rb --repo dommy
jm ref add JM-42 commit HEAD --repo dommy
jm done JM-42 --resolution accepted
```

---

## 29. 設計原則

### 29.1 リポジトリを情報の境界にしない

Itemはリポジトリに所属するのではなく、任意の数のリポジトリと関連する。

### 29.2 構造化データと自由記述を併用する

検索や状態管理に必要な情報はカラムとして持つ。

設計や調査の内容はMarkdown本文として保持する。

### 29.3 現在の理解と履歴を分ける

Item本文は現在の整理された理解を表す。

EntryとRevisionは履歴を表す。

### 29.4 SQLiteを直接操作させない

人間もcoding agentも、原則として`jm` CLIを通して操作する。

### 29.5 Gitへ残す情報は選択する

`jm`を一次的な開発情報の保管場所とする。

ただし、リポジトリ単体の利用・保守に必要な仕様、テスト、公開ドキュメントはGit側へ残す。

### 29.6 入力コストを低く保つ

Item作成時に必須なのはtitleだけとする。

type、body、Repository、Tag、priorityなどは後から追加できる。

### 29.7 過度なワークフローを持ち込まない

状態やtypeは少数に保ち、個別の意味は本文、Tag、Relation、Resolutionで表現する。

---

## 30. 将来拡張

将来的には次の機能を検討できる。

* cursesまたはTUIによる一覧・編集
* ローカルWeb UI
* Markdownファイルへの一時エクスポート
* GitHub Issuesとの選択的同期
* coding agent用のclaim・lease
* Itemごとの作業セッション
* コマンド実行履歴
* LLMによる自動分類
* 類似Item検索
* Item本文の要約
* 重複候補の検出
* リポジトリ横断の変更履歴表示
* GitコミットからのItem候補生成
* テスト失敗からのbug Item生成
* MCPサーバー
* 複数データベース間の読み取り専用統合
* 添付ファイル管理
* 暗号化
* ItemをADRやGitHub Issueへ昇格する機能

初期仕様から意図的に削除・後回しにした次の機能も、必要が実証された場合の将来拡張とする。

* 自動バックアップ（書き込み前後の自動実行）と`keep`による世代削除
* JSONLエクスポート（`jm export`）およびインポート（別DBからの統合を含む）
* doctorの外部状態検査（存在しないローカルパス・ファイル参照・Git remote変更）
* Revision復元コマンド（jm restore）
* Event監査証跡（変更イベントテーブル）
* relation・Repository関連の語彙拡張
* 対話的なinbox処理コマンド
* type別・Repository別などのstats集計軸
* doctorによる自動修復

---

## 31. 初期実装上の判断

初期実装では、次の判断を推奨する。

* Rubyで実装する
* SQLite3を使用する
* CLIパーサーには標準的なライブラリを使う
* Markdown自体の解析には依存しない
* frontmatterは使用しない（エディタ編集は本文のみ）
* FTS5を利用する
* 時刻はUTCのISO 8601形式（`YYYY-MM-DDTHH:MM:SSZ`、末尾`Z`・桁数固定）で保存する。この固定フォーマットにより、TEXTカラムの文字列ソートが時系列ソートと一致する
* 表示時にローカル時刻へ変換する
* schema migrationを最初から用意する
* JSON出力を初期版から実装する
* Git操作は補助機能とし、必須依存にしない
* DBスキーマを外部APIとして公開しない
* coding agent向けにはCLIのJSON出力を正式なインターフェースとする

---

## 32. まとめ

`jm` は、リポジトリ単位のIssue trackerではない。

複数の開発プロジェクトにまたがる情報を、個人の視点で一元管理するためのローカルな開発情報基盤である。

中心となるのは、RepositoryではなくItemである。

Itemは、作業、設計、調査、判断、疑問、知見を同じモデルで扱い、Repository、Gitコミット、ファイル、他のItemなどと関連付けられる。

SQLiteは、状態管理、横断検索、依存関係、履歴、関連付けを担う。

Markdown本文は、構造化しすぎることなく、設計や調査の内容を保持する。

`jm` の基本的な役割は次のように表せる。

```text
Capture → Organize → Relate → Search → Act → Record
```

つまり、

```text
思いついた情報を保存し、
整理し、
他の情報と関連付け、
必要なときに検索し、
作業へ移し、
結果を記録する
```

ためのシステムである。

