# 運用引き継ぎ情報

Operations Phaseで決定した運用設定・方針をサイクル横断で引き継ぐためのファイルです。

---

## デプロイ方針

### デプロイ方式

- **方式**: GitHub Release + git tag (`vMAJOR.MINOR.PATCH`)
- **リリース方法**: `cycle/<version>` ブランチを main にマージ → `git tag v<version>` を作成・push（GitHub Release 自動生成は将来検討）
- **バージョニング**: SemVer（`bin/jailrun --version` の値、`bin/bump-version` 経由で更新）

### リリース手順

1. Construction Phase で全 Unit 完了
2. Operations Phase で `bin/bump-version <new-version>` を実行（`bin/jailrun` 内 VERSION 行を更新）
3. `HISTORY.md` に新エントリを追記（リンクされた Issue / PR / 修正サマリ）
4. `cycle/<version>` → `main` の PR を作成、AI レビュー、CI green 確認後マージ
5. main へ切替、`git pull`、`git tag v<version>` 作成・push
6. `cycle/<version>` ブランチを削除（local + remote）

### ロールバック方法

- リリース後に問題が発覚した場合: 新たな patch リリース（`v<X.Y.(Z+1)>`）で修正する。tag の削除・force push はしない
- main で revert PR を作成し、cycle/<patch> ブランチで修正を確定させてから次の tag を切る

---

## 既知の問題・注意点

### 運用で発覚した問題

| 問題 | ワークアラウンド | 根本対応予定 |
|------|-----------------|-------------|
| v0.3.3 まで main の branch protection に必須 CI チェック未登録のため `error:checks-status-unknown reason:no-checks-configured` で `--skip-checks` バイパスが必要だった | `gh pr merge --merge --skip-checks` 一時利用 | v0.3.4 で `test (macos-latest)` / `test (ubuntu-latest)` を必須登録（本サイクル内で構造解消） |

### 運用時の注意点

- **`.aidlc/cycles/` は untrack 方針**（`.aidlc/rules.md` 参照）。Operations Phase の中間成果物は履歴として残さず、Issue / PR / `HISTORY.md` / git tag で運用を追跡
- **CI green 必須**: PR マージ前に macOS + Linux 両 OS の `make test` が green であることを確認（v0.3.4 以降は branch protection で強制）
- **トークン関連変更時**: `lib/token.sh` 修正は trap chain（`kill -SIG $$`）が呼び出し元に正しく伝播するか `tests/token.bats` の RT*/AT* で必ず検証
