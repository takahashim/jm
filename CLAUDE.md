# CLAUDE.md

`jm` は開発情報を単一 SQLite DB で管理する Ruby 製 CLI。設計は [SPEC.md](SPEC.md)、
実装計画とアーキテクチャ方針は [PLAN.md](PLAN.md) を参照(章番号は SPEC を指す)。

## コマンド

```bash
bundle exec rake test     # テスト(minitest、一時 DB に対しディスパッチャ経由で実行)
bundle exec rubocop       # Lint(オフェンス 0 を維持)
ruby -Ilib bin/jm <cmd>   # CLI を直接実行
```

## アーキテクチャ

- `lib/jm/cli.rb` — グローバルオプション解析 → コマンド dispatch → 例外を終了コードへ。
- `lib/jm/command.rb` — コマンド基底。DB ライフサイクルと store/editor/入力ヘルパを提供。
  コマンドは「引数パース → store 呼び出し → 描画」に徹する(ビジネスロジックを持たない)。
- `lib/jm/store/*.rb` — 各 aggregate の SQL を閉じ込めるデータアクセス層。
- `lib/jm/commands/*.rb` — 1 コマンド 1 ファイル。
- `lib/jm/migrations/*.sql` — スキーマ。変更は `jm init` / 将来の `jm migrate` のみ。

## 規約

- 時刻は `Clock.now`(UTC ISO8601、末尾 Z)で生成し一箇所に集約。
- 公開 ID `JM-000042` は整数 id から `PublicId` で導出(保存しない)。
- 書き込みは冪等(`ON CONFLICT DO NOTHING` / check-then-noop)。
- 非対話で完結。TTY が無くエディタ/確認が必要なら終了コード 2 で失敗しハングしない。
- `--json` 出力は `schema_version` 付き。coding agent 向けの正式インターフェース。
- 新コマンドは `cli.rb` の `COMMANDS` と require、`lib/jm.rb` の require に登録する。
- RuboCop 設定は `.rubocop.yml`(double_quotes、行長 100)。
