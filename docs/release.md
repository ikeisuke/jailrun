# jailrun リリース手順

このドキュメントは jailrun の新規コントリビューターが 1 人でリリース作業を完結できることを目的とする。`bin/bump-version` スクリプトの CLI 契約、バージョン番号の付与ルール、`HISTORY.md` エントリ作成ガイドライン、git tag 運用ポリシー、リリース後の確認項目を順に記す。

## 1. バージョン番号付与ルール（semver）

jailrun は [Semantic Versioning 2.0.0](https://semver.org/lang/ja/) に準拠し、`MAJOR.MINOR.PATCH` 形式でバージョン番号を付与する。昇格基準は以下の通り。

- **MAJOR**: 互換性破壊を伴う変更
  - 例: `bin/jailrun` の CLI 引数・サブコマンドの非互換な変更、`config.toml` スキーマの後方非互換な変更、サンドボックスプロファイルのデフォルト挙動が既存利用を破壊する変更
- **MINOR**: 後方互換な機能追加
  - 例: 新規コマンド・新規設定項目・新規プロファイル・新規 deny-read パスの追加、既存 API の拡張
- **PATCH**: 後方互換なバグ修正・内部改善
  - 例: サンドボックスプロファイルの不具合修正、ドキュメント誤字修正、テスト追加

昇格判断時は、当該サイクルの `.aidlc/cycles/vX.Y.Z/requirements/intent.md` と各 Unit 定義の「変更対象」「境界」セクションを確認し、利用者影響を評価する。

## 2. `bin/bump-version` スクリプトの利用手順

`bin/bump-version` は `bin/jailrun` 内の `VERSION` 行と `HISTORY.md` 先頭のエントリ見出しを一括で更新するスクリプト。オプションで `git tag` 作成にも対応する。

### 2.1 CLI シンタックス

```text
bin/bump-version <new_version> [--message <text>] [--tag] [--dry-run]
```

### 2.2 引数詳細

| 引数 | 必須 | 説明 |
|------|------|------|
| `<new_version>` | 必須 | `vMAJOR.MINOR.PATCH` または `MAJOR.MINOR.PATCH`。内部で `MAJOR.MINOR.PATCH` に正規化される |
| `--message <text>` | 任意 | HISTORY.md 見出しの **タイトル部** のみを指定する（`## vX.Y.Z — <text> (YYYY-MM-DD)` の `<text>`）。省略時は標準入力から 1 行読み取る |
| `--tag` | 任意 | 指定時のみ `git tag vX.Y.Z` を作成する。未指定時は tag 作成せず、`bin/jailrun` と `HISTORY.md` のみ更新 |
| `--dry-run` | 任意 | 変更差分を stdout 表示するのみで、ファイル書き込み・tag 作成を行わない |

### 2.3 タイトル入力の制約

`--message <text>` および標準入力経由で与えるタイトルは以下の制約を満たす必要がある。

- 空文字・空白のみは拒否される
- 改行文字を含む文字列は拒否される
- 標準入力経由の場合は 1 行のみ許容（2 行目以降が検出されるとエラー）
- `--message` を指定した場合、標準入力は読まれない

### 2.4 実行前提

- `bin/jailrun` に `VERSION="..."` 行が 1 つ存在すること
- `HISTORY.md` が `# Change History` で始まり、最初の `## ` 見出しが `^## v[0-9]+\.[0-9]+\.[0-9]+ — .+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$` に厳格一致すること
- **clean worktree 要求は `--tag` 指定時かつ `--dry-run` 未指定の本実行時のみ**。それ以外（`--tag` なし、または `--tag --dry-run` の組み合わせ）では dirty worktree を許容する

### 2.5 挙動

- 日付は UTC 日付で書き込まれる（`date -u +%Y-%m-%d`）
- `bin/bump-version` が自動挿入するのは **見出し行のみ**（`## vX.Y.Z — <タイトル> (YYYY-MM-DD)` + 直後の空行 1 行）。`### Changes` / `### Compatibility` などの本文ブロックは **リリース担当者が手動で追記** する（二段構成）
- 書き込み段階で失敗した場合は、バックアップ（`bin/jailrun` / `HISTORY.md` の一時コピー）から自動復元される

### 2.6 実行例

```sh
# 通常の本実行（リリース直前に実施）
bin/bump-version 0.3.0 --message "現状整理・品質向上・バージョン運用統一"

# 変更内容を確認するだけ（ファイル書き込みなし）
bin/bump-version 0.3.0 --message "test" --dry-run

# tag も同時に作成（clean worktree 必須）
bin/bump-version 0.3.0 --message "release" --tag
```

本サイクル（v0.3.0）のリリースでは `--tag` は指定せず、tag 作成は Operations Phase で PR マージ後に別途行う運用としている（次章参照）。

### 2.7 異常系の挙動

以下の条件で非 0 終了し、ファイル・tag の状態は実行前と同一に保たれる（状態変化ゼロ保証）。

- バージョン形式違反（`abc`、`1.2`、`v1.2.3.4` 等）
- 既存バージョンと同一値
- `HISTORY.md` 不在または期待形式不一致
- 重複見出し（同じ `## vX.Y.Z ...` が既存）
- `--tag` 指定時に既存 tag が存在する／worktree が dirty
- `--message` も stdin もない／空／複数行

## 3. git tag 運用ポリシー

### 3.1 tag 付与タイミング

サイクル PR（`cycle/vX.Y.Z` → `main`）が main にマージされた**直後**に、リリース担当者が手動で tag を付与する。

### 3.2 tag 作成コマンド

```sh
# マージ後、main ブランチに移動してから実行
git checkout main
git pull
git tag v0.3.0
git push origin v0.3.0
```

### 3.3 `bin/bump-version --tag` との使い分け

`bin/bump-version --tag` はローカルで tag を作成するが、v0.3.0 時点の運用では **マージ前の Construction Phase では tag を作成せず**、サイクル PR マージ後の Operations Phase でのみ tag を付与する。このため `bin/bump-version` 本実行時は `--tag` を指定しない。

### 3.4 削除・移動の禁止

一度リモート（`origin`）に push した tag は原則として削除・移動しない。誤タグを付与した場合は、新しいバージョン番号で打ち直す運用とする。

### 3.5 tag 命名規則

tag 名は `v<MAJOR.MINOR.PATCH>` 形式（`v` プレフィックス必須）。`bin/bump-version` がこの形式で作成する。

## 4. `HISTORY.md` エントリ作成ガイドライン

### 4.1 見出しフォーマット

```markdown
## vMAJOR.MINOR.PATCH — <タイトル> (YYYY-MM-DD)
```

正規表現: `^## v[0-9]+\.[0-9]+\.[0-9]+ — .+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$`

### 4.2 挿入位置

`# Change History` 見出し直下、既存の最新バージョンエントリの直前に新エントリを挿入する。`bin/bump-version` がこの位置で自動挿入する。

### 4.3 タイトル決定規則

`.aidlc/cycles/vX.Y.Z/requirements/intent.md` の冒頭「プロジェクト名」行から `jailrun vX.Y.Z — ` プレフィックスを除去した残りを採用する。

例:

- `jailrun v0.3.0 — 現状整理・品質向上・バージョン運用統一` → `現状整理・品質向上・バージョン運用統一`

### 4.4 本文構造

見出し直下に以下の構造で手動追記する。

```markdown
## vMAJOR.MINOR.PATCH — <タイトル> (YYYY-MM-DD)

<概要1段落：当該サイクルの主要成果を 3〜5 文でまとめる>

### Changes

#### <カテゴリ名1>

- **<項目名>**: <詳細>
- **<項目名>**: <詳細>

#### <カテゴリ名2>

- **<項目名>**: <詳細>

### Compatibility

- <互換性情報 1>
- <互換性情報 2>
```

### 4.5 Changes セクションのガイドライン

- **カテゴリ名**: サイクルの主要テーマに応じて命名する。既存 HISTORY.md では `Sandbox Profile` / `Keychain Access` / `Deny-Read Paths` / `Documentation` / `Tests` / `Version Management` などを採用
- **項目数**: 1 カテゴリあたり 1〜6 項目の範囲で許容する。少数項目のカテゴリ（単発のバグ修正など）も許容
- **一次情報トレース**: 各箇条書きは `.aidlc/cycles/vX.Y.Z/history/construction_unit*.md` / `operations.md` / マージコミット差分のいずれかに根拠を持つ事実のみで構成する。intent.md の「やりたいこと」のような未確定情報は含めない

### 4.6 Compatibility セクションのガイドライン

- **採用可**: `construction_unit*.md` の「実行内容」や `operations.md` に明記された互換性情報、merge 差分から読み取れる不変条件（デフォルト値が後方互換、既存 API の維持、OS 固有機能のスコープ明記など）
- **採用不可**: intent.md の「制約事項」そのもの（実装予定の制約であり、出荷された挙動とは限らない）、「実装確認」のような曖昧な根拠表現

### 4.7 未完了 Unit の雛形を書かない

Construction Phase の途中で `bin/bump-version` を本実行する場合（本サイクル v0.3.0 の Unit 004 のような運用）、その時点で未完了の Unit に関する Changes 項目を**先出しで書いてはいけない**。未完了 Unit の成果物は確定していないため、先出しすると利用者向けリリースノートに未確定情報が混在する。

この場合の運用:

1. `bin/bump-version` 実行時点では、確定済み Unit の分のみを `### Changes` / `### Compatibility` に記述する
2. 未完了 Unit 分は、担当 Unit の履歴ファイル（`history/construction_unit{NN}.md`）に「Operations Phase 引き継ぎメモ」として記録する
3. 後続 Unit 完了後、Operations Phase のリリース準備ステップで該当エントリに追記する

### 4.8 記録不足の扱い

一次情報（`construction_unit*.md` / `operations.md` / マージ差分）および補助情報（intent.md / inception.md / `git log`）のいずれにも該当事実が記載されていない場合のみ「（記録不足）」と明示する。単なる「情報が少ない」「調査に時間がかかる」は該当しない。

## 5. リリース後の確認項目

PR マージおよび tag 付与後、以下を順に確認する。

- [ ] `bin/jailrun --version` が期待値（例: `jailrun 0.3.0`）を返す
- [ ] `make test` 全件がパスする
- [ ] `HISTORY.md` の先頭エントリが新バージョンで、`### Changes` / `### Compatibility` が手動補筆済み
- [ ] `git tag -l v<version>` で tag がローカルに存在する
- [ ] `git ls-remote --tags origin v<version>` でリモートに tag が反映されている
- [ ] main ブランチの HEAD が `bin/jailrun` VERSION 更新コミット以降であること

GitHub Releases 機能の利用は本サイクルでは採用していない。将来採用する場合は、tag を元にリリースノートを作成し、`HISTORY.md` エントリ本文を Release description に貼り付ける運用を想定する。

## 関連ドキュメント

- [`docs/architecture.md`](./architecture.md) - jailrun のアーキテクチャ
- [`docs/contributing.md`](./contributing.md) - コントリビューション手順
- [`HISTORY.md`](../HISTORY.md) - 過去リリース履歴
- [`bin/bump-version`](../bin/bump-version) - 本ドキュメントで扱うリリーススクリプト実装
