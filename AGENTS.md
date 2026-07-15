# coding agent 向けガイド

`jm` は人間と coding agent の両方が書き込む前提で設計されている。agent は SQLite を
直接触らず、`jm` コマンドと `--json` 出力だけを使うこと。

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
