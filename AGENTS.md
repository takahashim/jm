# coding agent 向けガイド

`jm` は人間と coding agent の両方が書き込む前提で設計されている。agent は SQLite を
直接触らず、`jm` コマンドと `--json` 出力だけを使うこと。

このガイドはツールに同梱されており、どのエージェント・どのプロジェクトからでも
`jm guide` で最新版を表示できる。作業を始める前にまず `jm guide` を読むこと。
まだ DB が無ければ `jm init` で初期化する(初回のみ)。

## 原則

- **SQLite を直接操作しない。** すべて `jm` CLI 経由。DB スキーマは非公開の内部実装。
- **`--json` を正式インターフェースとする。** 人間向けテキストをパースしない。出力には
  `schema_version` が含まれる。
- **作成者を名乗る。** `JM_AUTHOR` を設定して実行する(例 `JM_AUTHOR=claude`)。人間が
  後から「誰が書いたか」で信頼度を判断できるようにするため。
- **非対話で完結する。** 本文は `--message` か `--stdin` で渡す。エディタは開かない
  (TTY がなければ即エラーになる)。本文入力は `--message` / `--stdin` のいずれか一つ。
- **冪等。** `tag add` / `ref add` / `link` / `repo link` / `start` / `done` の再実行は
  エラーではなく no-op になる。リトライして安全。
- **Entry は要点のみ。** ビルドログやコマンド出力を丸ごと貼らない。長い出力はファイルに
  残し `jm ref add ... log` で参照する。

## 読み取り

```bash
jm show JM-42 --json          # Item 全体 + tag/repo/relation/reference/entry
jm list --ready --json        # 着手可能な Item
jm search websocket --json    # 全文検索
jm links JM-42 --json         # 依存関係
jm repo show dommy --json     # リポジトリ情報
```

## 更新

```bash
jm start JM-42
jm log JM-42 --kind progress --message "..."
jm log JM-42 --kind finding --stdin < findings.md
jm ref add JM-42 commit HEAD --repo dommy   # 完全 SHA へ解決される
jm ref add JM-42 file lib/foo.rb --repo dommy
jm done JM-42 --resolution completed
jm done JM-42 --resolution completed --at 2026-01   # 済んだ作業を後から記録(粗い日付可)
```

## 推奨手順

1. `JM_AUTHOR` を設定して実行する。
2. `jm show ID --json` で Item を読む。
3. `depends_on`(`jm links ID --json`)と対象 Repository を確認する。
4. `jm start ID` で着手する。
5. 実装・調査を行う。
6. 重要な発見だけを `jm log` に残す。
7. commit・file を `jm ref add` で関連付ける。
8. 完了条件を確認する。
9. `jm done ID --resolution ...` で完了する。

## Item 本文の更新

本文の上書きは通常の編集経路を使う。上書き前の本文は自動的に revision として保存される。

```bash
jm edit JM-42 --stdin < new_body.md
```

## 終了コード

`0` 成功 / `1` 一般 / `2` 引数 / `3` 対象なし / `4` 整合性違反 / `5` DB / `6` Git。
`jm next` は着手可能な Item が無いとき `3` を返す。

## jm 自体が不調なとき(改善につなげる)

`jm` のコマンドがエラーになる・仕様と挙動がずれる・使いにくいと感じたら、黙って回避
せずに記録する。`jm` の source は `jm` 自身に repo として登録されている。

```bash
jm repo show jm --json        # source のローカルパスを得る(path フィールド)
```

1. **記録する** — 再現コマンドと期待/実際を要点だけ Item に残す。
   ```bash
   jm add "jm doctor が WAL で誤検知する" --type bug --repo jm \
     --message "再現: jm doctor / 期待: OK / 実際: FTS mismatch を誤報"
   ```
   長いログは貼らず、ファイルに保存して `jm ref add ... log` で参照する(Entry は要点のみ)。
2. **直す(可能なら)** — repo の path へ移動し、通常の開発フローで修正する。
   ```bash
   cd "$(jm repo show jm --json | ruby -rjson -e 'puts JSON.parse(STDIN.read)["path"]')"
   # 修正 → 検証(必ず緑を確認してからコミット)
   bundle exec rake test && bundle exec rubocop
   # 修正を手元の jm に反映(入れ直すまで古い挙動のまま)
   bundle exec rake install
   ```
   関連コミットを Item に紐付ける: `jm ref add <ID> commit HEAD --repo jm`。
3. 挙動と仕様が食い違う場合は、実装だけでなく `SPEC.md` / `PLAN.md` / このガイドの
   どれを正とすべきかも Item の本文で述べる。
