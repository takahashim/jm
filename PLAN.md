# jm 実装計画

`SPEC.md` を実装するための計画。各フェーズは**それ自体で動作する**ように区切り、早い段階から実運用を始められる順序にしている。

## 1. 技術スタックと依存

| 項目 | 選択 | 備考 |
|---|---|---|
| 言語 | Ruby | 外部配布しないため単一バイナリの利点が不要。開発速度と保守性を優先 |
| DB | `sqlite3` gem | モダンな SQLite を同梱。FTS5 + trigram tokenizer が利用可能 |
| CLI | `optparse`(標準ライブラリ) | 依存を増やさない |
| JSON | `json`(標準ライブラリ) | |
| TOML | `tomlrb` | 設定は読み取りのみのため read-only パーサで十分 |
| Git | `git` コマンドを shell out | libgit2 依存を避ける。非 git ディレクトリを許容 |
| テスト | `minitest` | 一時 DB に対して実行 |
| Lint | `rubocop` | 既存の自動整形フローに乗せる |

- Markdown のターミナル整形は v1 では持たず、本文は生表示(必要なら pager 経由)。
- エディタ・Git 以外に外部プロセス依存を作らない。
- 起動レイテンシがエージェント連携で問題化した場合は、常駐モード(将来の MCP サーバー)で対処し、言語は変えない。

## 2. プロジェクト構成

```
jm/
├── SPEC.md
├── PLAN.md
├── Gemfile
├── Rakefile                  # test / rubocop タスク
├── bin/jm                    # エントリポイント → JM::CLI.run(ARGV)
├── lib/
│   ├── jm.rb                 # require まとめ + VERSION / JSON_SCHEMA_VERSION
│   └── jm/
│       ├── cli.rb            # グローバルオプション解析 + コマンドディスパッチ
│       ├── config.rb         # env > config.toml の解決
│       ├── database.rb       # 接続・PRAGMA・トランザクション・マイグレーション実行
│       ├── migrations/       # 001_initial.sql など連番
│       ├── public_id.rb      # JM-000042 ⇄ 整数 の正規化
│       ├── clock.rb          # UTC ISO8601(Z) 生成
│       ├── author.rb         # --by / JM_AUTHOR / nil
│       ├── editor.rb         # エディタ起動 + TTY ガード
│       ├── output.rb         # 人間/JSON 整形、色、終了コード、エラー型
│       ├── store/            # データアクセス層(SQL を閉じ込める)
│       │   ├── items.rb  entries.rb  repositories.rb
│       │   ├── relations.rb  references.rb  tags.rb  revisions.rb
│       ├── search.rb  ready.rb  backup.rb  doctor.rb  git.rb
│       └── commands/         # 1コマンド1ファイル、run(args) を持つ
│           ├── add.rb show.rb list.rb edit.rb ...
└── test/
```

ORM は使わず、SQL を `store/*` に閉じ込める薄い層にする。コマンド層は store とビュー(`output`)を呼ぶだけに保つ。

**コマンドを薄く保つ規律**: ビジネスロジック(検証・正規化・状態遷移・Revision フックなど)は `store/*` とドメイン操作側に置き、コマンドは「引数パース → ドメイン呼び出し → 描画」に徹する。これにより、将来 Web 閲覧ビューアが必要になったとき、共有ユースケース層(`queries`/`services`)を抽出するのが書き直しではなく機械的リファクタで済む。Web 用の層自体は必要になるまで作らない(SPEC 30.7)。

## 3. 横断的な基盤(全フェーズで効く設計判断)

- **終了コード** — `Output` に例外型を定義(`ArgError=2`, `NotFound=3`, `Integrity=4`, `DBError=5`, `GitError=6`)。`CLI.run` が rescue して stderr + コード変換。全コマンドはこの型を投げるだけ。
- **非対話ガード** — エディタ/確認が必要で `$stdin.tty?` が偽なら `ArgError` で即死(ハングさせない)。`Editor` と `jm delete` が参照。(SPEC 14.1.1)
- **冪等性** — 書き込みは `INSERT ... ON CONFLICT DO NOTHING` / check-then-noop。tag/ref/link/repo-link/start/done が対象。(SPEC 14.1.2)
- **トランザクション** — 書き込みは `BEGIN IMMEDIATE` で包む。WAL + `busy_timeout=5000` で複数エージェント並走に耐える。
- **時刻** — 生成は `Clock.now`(UTC, `...Z`)一箇所。表示時のみ config の `date_format` でローカル変換。(SPEC 31)
- **Revision フック** — `Store::Items#update` が title/body 変更を検知したら旧値を `item_revisions` に退避してから更新。(SPEC 17)

## 4. フェーズ計画

### Phase 0 — 骨組みとインフラ

- Gemfile / Rakefile / bin/jm / lib レイアウト
- `Config`(env 優先)、`Database`(PRAGMA 一式)
- **マイグレーション方針**: `jm init` / 将来の `jm migrate` のみがスキーマを変更。通常コマンドはバージョン検査のみ(未適用なら書き換えず終了コード5)。読み取りが暗黙に DB を書き換えない(SPEC 18.2)
- **マイグレーション 001**: 全テーブル(items, entries, item_revisions, repositories, item_repositories, item_relations, item_references, tags, item_tags, meta) + FTS 仮想テーブル(trigram, external-content) + 同期トリガー + インデックス(state, priority, updated_at, item_references 一意/item_id, item_revisions item_id など)
- `PublicId` / `Clock` / `Author` / `Output` / `CLI` ディスパッチ雛形
- `jm init`(明示初期化 + FTS5/trigram の可用性検証。使えなければ終了コード5で明瞭に失敗)
- `jm doctor` の integrity check だけ先行
- テストハーネス(一時 DB 生成ヘルパ)

**動く成果物**: `jm init` で DB 作成、`jm doctor` が通る。

### Phase 1 — Item のライフサイクル(道具の背骨)

- `jm add`(位置引数 title、`--type/--state/--repo/--stdin/--by/--json`、TTY ありならエディタ)
- `jm show`(人間 + `--json` に `schema_version`)
- `jm list`(フィルタ群、state ランク順、`--by/--since`、`--json`)
- `jm edit`(本文のみエディタ、`--title/--type/--stdin`、変更で Revision 自動保存)
- 状態遷移 `jm open/start/block/done/archive`(timestamps、`--resolution`、`--reason`→Entry)
- `jm priority`
- created_by 配線、冪等性・非対話ガードをここで通しで検証

**動く成果物**: 1 Item を作って読んで編集して完了まで、人間が実運用できる。

### Phase 2 — 関係・リポジトリ・参照・タグ・Entry

- `jm log`(`--kind/--message/--stdin/--by`)
- `jm link/unlink/links`(3種、blocks/child_of 正規化、depends_on 循環検出を再帰 CTE で)
- `jm repo add/list/show/edit/remove/link/unlink`(`git.rb` で絶対パス・remote・既定ブランチ自動取得、非 git 許容)
- `jm ref add/list/remove`(commit を完全 SHA へ解決、`HEAD` 対応、リポジトリ相対パス化)
- `jm tag add/remove/list`(NOCASE 一意、先勝ち表記)

**動く成果物**: 関係モデル全体が使える。エージェント連携の書き込み経路が揃う。

### Phase 3 — 検索・ready・next・stats

- `jm search`(FTS trigram で title/body/Entry のみ、3文字未満は LIKE フォールバック、`--type/--state/--tag/--repo` フィルタ、`--json`、bm25 で title 重み付け。生 FTS クエリ `--fts` は初期版では出さない)
- `ready.rb` + `jm list --ready`
- `jm next`(`--start`、`--repo`)
- `jm stats`(state 別カウント + ready 数)

**動く成果物**: 探す・拾う・着手するの一連。

### Phase 4 — バックアップ・doctor・削除・履歴

- `jm backup`(SQLite Backup API、タイムスタンプ命名)。手動のみ
- `jm doctor` の DB 内部検査 + `jm doctor --rebuild-fts`(整合性・外部キー・FTS・depends_on 循環・timestamp 整合)
- `jm delete`(`--force`、カスケード)
- `jm history [--show]`

**動く成果物**: SPEC 26章「初期リリース範囲」を満たす v1。

v1 から外した運用機能(後回し): 自動バックアップ + 世代削除、JSONL export/import、doctor の外部状態検査(パス・ファイル・Git remote)。

### Phase 5 — 仕上げ

- RuboCop 適用、README、エージェント向け利用手順の短いドキュメント

## 5. テスト方針

- 各コマンドを一時 DB に対して**ディスパッチャ経由**で実行(サブプロセスを立てず高速)。
- 終了コード・TTY 挙動・エディタ起動だけは数本のサブプロセス煙テスト。
- 循環検出、ID 正規化、state 順、冪等性、Revision 発火、FTS フォールバックは単体で重点的に。

## 6. 実装中に確定させる小さな判断

1. **メタ変更コマンドの粒度** — `jm edit --type` 等に集約するか、`jm type`/`jm state` を個別に生やすか(SPEC は edit 集約寄り)。
2. **search の既定並び** — bm25 と priority/state/updated の合成比率(まず bm25 → priority → updated の順で単純化を推奨)。

マイグレーション適用方針は確定済み(`init`/`migrate` のみ変更、通常コマンドは検査のみ)。上記は実装を止めないため、Phase 0 は即着手できる。
