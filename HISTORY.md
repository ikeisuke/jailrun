# Change History

## v0.3.1 — テスト基盤補強・5 領域の回帰保護を確立 (2026-04-23)

v0.3.0 のコードベース調査で特定されたテストカバレッジ不足 5 領域を全て解消。bats（token/ruleset/aws）と Python unittest（config_cli/config_migrate）を組み合わせ、本体コード無変更で品質補強リリースを届けた。

### Changes

#### Tests

- **`tests/token.bats` 新設**: `lib/token.sh` の `_cmd_add` / `_cmd_rotate` / `_cmd_delete` / `_cmd_list` に対する 19 ケースの bats テストを追加。macOS `security` / Linux `secret-tool` の PATH shim による Keychain 呼び出し検証、正常系 / Keychain 未設定 / 不正引数を網羅（Unit 001, Issue #41）
- **`tests/ruleset.bats` 新設**: `lib/ruleset.sh` の GitHub API 呼び出し（`gh api` 経由のブランチ / タグ保護 apply 系）に対する 19 ケースの bats テストを追加。sysbin ホワイトリスト方式（6 コマンド）で PATH 隔離し、TSV 6 列（category / last 切替）で branch / tag POST を区別。idempotent skip、`gh api` 失敗系、delete 代替の idempotent skip、タグ保護 POST 失敗（RSF1 代表）を網羅（Unit 002, Issue #42）
- **`tests/aws.bats` 新設**: `lib/aws.sh` の `_setup_aws_credentials` / `_write_aws_profile` に対する 9 ケース（AW1-AW9）の bats テストを追加。`aws configure export-credentials` と `jq` の PATH shim、INI 書き込みの section 重複・順序・行位置検証 helper（14 種）、AWS 失敗時 fail-open、jq 不在 fallback、プロファイル名正規化（`tr 'a-z' 'A-Z' | sed 's/[^A-Z0-9_]/_/g'` で `[A-Z0-9_]` へ閉じた正規化）を網羅（Unit 003, Issue #43）
- **`tests/test_config_cli.py` 新設**: `lib/config_cli.py` の 6 関数（`cmd_load` / `cmd_show` / `cmd_set` / `cmd_edit` / `cmd_path` / `cmd_init`）に対する 21 ケース（CL1-CL3 / CS1-CS2 / CSET1-CSET9 / CE1-CE3 / CP1 / CI1-CI3）の Python unittest を追加。`config_cli.config_file` + `config.config_file` 両 patch、`os.execvp` スタブ化、`--append` 重複値の no-op 分岐を `set_key_in_toml` spy で直接観測、`--dir` longest-prefix + list append の識別 fixture を網羅（Unit 004, Issue #44）
- **`tests/test_config_migrate.py` 新設**: `lib/config_migrate.py` の `migrate_shell_to_toml` / `cmd_migrate` 2 関数に対する 12 ケース（MST1-MST8 / CM1-CM4）の Python unittest を追加。`assertEqual` による TOML 全文厳密比較でラウンドトリップを検証、`GH_TOKEN_NAME` の precedence 分岐（`lib/config_migrate.py:54-56`）固定、`FileNotFoundError` / `SystemExit(1)` / `--force` 上書きを網羅（Unit 005, Issue #45）

#### Test Helpers

- **`tests/helpers.bash` 拡充**: token / ruleset / aws テスト向けの共通 helper を追加。PATH shim セットアップ（sysbin ホワイトリスト 12 コマンド: `readlink` / `dirname` / `cat` / `grep` / `cut` / `rm` / `chmod` / `mkdir` / `touch` / `awk` / `tr` / `sed`）、TSV 6 列 shim 呼び出しログ、INI section / key assertion（14 種、section_count / section_order / line_in_nth 系統）、AWS shim 専用のプロファイル名正規化を整備（Unit 001-003）

#### Documentation

- **`docs/contributing.md` Test Structure 更新**: v0.3.1 で追加された 5 テストファイル（`token.bats` / `ruleset.bats` / `aws.bats` / `test_config_cli.py` / `test_config_migrate.py`）を反映。あわせて既存の誤記（実在しない `lint.bats` の削除）と既存欠落ファイル（`bump_version.bats` / `path_resolution.bats` / `posix_compliance.bats` / `sandbox_deny_log.bats` / `sandbox_linux_apparmor.bats` / `shim.bats`）を追記して `tests/` 実在ファイル一覧と全面再同期（Unit 006）

#### Version Management

- **`bin/jailrun` VERSION 更新**: `0.3.0` → `0.3.1`（`bin/bump-version 0.3.1 --message "テスト基盤補強・5 領域の回帰保護を確立"` 経由で `bin/jailrun` VERSION 行と `HISTORY.md` 先頭見出しを同時更新、Unit 006）

### Compatibility

- 本サイクルの変更は **テスト追加 + リリースメタデータ / 文書更新のみ**で、本体コード（`lib/token.sh` / `lib/ruleset.sh` / `lib/aws.sh` / `lib/config_cli.py` / `lib/config_migrate.py` / `lib/config.py` / `bin/jailrun` のロジック部）に変更はない
- 既存 bats 120 ケース + Python unittest 26 ケース（`tests/test_proxy.py`）は全て引き続きパス
- 新規 bats 47 ケース（`token.bats` 19 / `ruleset.bats` 19 / `aws.bats` 9）+ Python unittest 33 ケース（`test_config_cli.py` 21 + `test_config_migrate.py` 12）を追加、合計 **bats 167 ケース + Python unittest 59 ケース**
- `jailrun --version` 出力が `jailrun 0.3.1` に更新される

## v0.3.0 — 現状整理・品質向上・バージョン運用統一 (2026-04-20)

VERSION SoT の確立と bump-version スクリプト導入、HISTORY.md の過去サイクル分補完、v0.3.0 リリース手順ドキュメント新設により、リリース可視性とバージョン運用の統一を達成した。併せて Issue #23（Linux lockdir/proper-lockfile 競合）の論理検証を実施した。

### Changes

#### Investigation

- **Issue #23 の論理検証**: Linux 環境の lockdir 事前作成と `proper-lockfile` の競合について、`mkdir -p` 除去後の挙動を再評価。回帰なしを確認してクローズ判断に至った（Unit 001）

#### Version Management

- **`bin/bump-version` 新設**: POSIX sh 実装で `<version> [--message <text>] [--tag] [--dry-run]` CLI を提供。`bin/jailrun` 内 VERSION 行と `HISTORY.md` 先頭見出しを原子的に更新し、`--tag` 指定時は `git tag vX.Y.Z` を作成。失敗時はバックアップからの自動復元で状態変化ゼロを保証（Unit 002）
- **VERSION SoT の確立**: `bin/jailrun` 内の `VERSION="x.y.z"` 行を `jailrun --version` の単一 source of truth として確立し、`tests/jailrun.bats` もこの値を期待値として参照するよう整備（Unit 002）
- **`tests/bump_version.bats` 追加**: 正常系・異常系（バージョン形式違反、重複バージョン、HISTORY.md 形式不正、`--tag` での既存 tag／dirty worktree、`--dry-run` 副作用ゼロなど）および `--message` / stdin 入力制約の網羅テストを追加（Unit 002）

#### Release Documentation

- **HISTORY.md 過去サイクル分の補完**: v0.2.0（サンドボックスプロファイル修正の正式化と deny ログ機能追加）と v0.2.1（Keychain アクセス制限強化とクラウドクレデンシャル deny-read 拡充）のエントリを補完し、新しい順（v0.2.1 → v0.2.0 → v0.1.0）に並び替え。一次情報（`construction_unit*.md` / `operations.md` / merge 差分）にトレース可能な fact のみで構成（Unit 003）
- **v0.3.0 エントリ先頭挿入**: `bin/bump-version` 本実行（初の実運用）により `bin/jailrun` VERSION を `0.3.0` に更新し、HISTORY.md 先頭に v0.3.0 見出しを自動挿入（Unit 004）
- **`docs/release.md` 新設**: 新規コントリビューターが 1 人でリリース作業を完結できる 5 章構成（semver 規則、bump-version 利用手順、git tag 運用ポリシー、HISTORY.md エントリガイドライン、リリース後確認項目）のリリース手順書を新設（Unit 004）

#### Tests

- **`tests/jailrun.bats` version 期待値更新**: `"jailrun 0.1.0"` → `"jailrun 0.3.0"` に更新し、VERSION SoT の実運用と整合（Unit 004）

### Compatibility

- `jailrun --version` の参照元を `bin/jailrun` 内の `VERSION` 定数に統一した（Unit 002 `construction_unit02.md` / `bin/jailrun` 差分）
- `docs/release.md` の新設は既存 `docs/*.md` の構造・内容を変更しない独立ファイル追加のみ（既存 `docs/architecture.md` / `docs/contributing.md` / `docs/github-pat-setup.md` / `docs/README.md` は不変）

## v0.2.1 — Keychainアクセス制限強化とクラウドクレデンシャルdeny-read拡充 (2026-04-14)

macOS Seatbeltプロファイルで従来全面許可されていたKeychain書き込みを設定駆動で絞り込める仕組み（`keychain_profile`）を追加し、主要クラウド／開発ツールのクレデンシャルパス19件をdeny-readデフォルトへ取り込むことでjailrunの保護範囲を大幅に拡大した。

### Changes

#### Keychain Access

- **制御可否の技術調査**: Seatbelt `keychain-access-*` オペレーションは macOS 26.3 で `unbound variable`（制御不可）と判明。代替として Keychain DB への `file-write*` deny が有効であることを検証
- **採用戦略の決定**: `keychain-db-regex-write-scope`（`~/Library/Keychains` 書き込みをプロファイル設定で絞り込む）を Unit 003 実装方針として確定
- **`keychain_profile` 設定の追加**: `config.toml` に `keychain_profile`（`deny` / `read-cache-only` / `allow`、デフォルト `allow`）を新設
- **バリデーション追加**: `lib/config.py` に `keychain_profile` の許容値バリデーションを追加（不正値は即時エラー）。`lib/config.sh` でも不正値検出時に即座に中断するよう修正
- **Seatbeltプロファイル分岐**: `lib/sandbox.sh` で `KEYCHAIN_PROFILE` 値に応じ macOS Seatbelt プロファイルの `~/Library/Keychains` 書き込み許可を条件分岐

#### Deny-Read Paths

- **デフォルトdeny-readパスを4→23件に拡充**: `lib/sandbox.sh` の `_SANDBOX_DENY_READ_PATHS` に19パス追加
- **追加対象**: `~/.config/gcloud`, `~/.azure`, `~/.oci`, `~/.docker`, `~/.kube`, `~/.wrangler`, `~/.config/wrangler`, `~/.fly`, `~/.config/netlify`, `~/.config/vercel`, `~/.config/heroku`, `~/.terraform.d`, `~/.vault-token`, `~/.config/op`, `~/.config/hub`, `~/.config/stripe`, `~/.config/firebase` ほか
- **Linux反映**: `lib/platform/sandbox-linux-systemd.sh` の `InaccessiblePaths` に同追加パスを反映
- **存在チェック改善**: Linux側の存在チェックを `[ -d ]` → `[ -e ]` に変更し、ファイル単体パスにも対応

#### Tests

- **deny-readパス検証テスト**: `tests/sandbox_profile.bats` に追加パスの存在確認テストを3件追加
- **`keychain_profile`モード別テスト**: `tests/sandbox_profile.bats` に `allow` / `deny` / `read-cache-only` の各モードテストを追加（Unit 003 完了時に全8件合格、回帰なし）
- **Linux InaccessiblePathsテスト**: `tests/sandbox_linux_systemd.bats` に反映テストを追加

#### Documentation

- **architecture.md 更新（Unit 001）**: `docs/architecture.md` の deny-read パス一覧を23パスに拡充
- **architecture.md 更新（Unit 003）**: `docs/architecture.md` の Keychain セクションを `keychain_profile` 3 モード仕様に更新
- **README 更新（Operations）**: `README.md` / `docs/README.md` の保護対象一覧を deny-read 23 パスと `keychain_profile` 説明込みに更新

### Compatibility

- `keychain_profile` のデフォルトは `allow` のため、設定未指定時は従来挙動を維持（後方互換）
- deny-read 追加は macOS（Seatbelt）／Linux（systemd `InaccessiblePaths`）共通で適用。既存の4パス（`~/.aws`, `~/.config/gh`, `~/.gnupg`, `~/.ssh`）は維持
- `keychain_profile=deny` / `read-cache-only` 時は `~/Library/Keychains` 書き込みが Seatbelt プロファイルから除外される。利用者向け挙動説明は `docs/architecture.md` / `docs/README.md` に記載

## v0.2.0 — サンドボックスプロファイル修正の正式化とdenyログ機能追加 (2026-04-14)

v0.1.0サイクル中にWIPで導入されたサンドボックスプロファイル修正（Keychain書き込み・lockfile・atomic write）を正式化し、Seatbeltによるdenyイベントを自動記録する仕組みを追加した。ドキュメントにプロファイル挙動の説明を加え、Linux側のReadWritePathsもあわせて整備した。

### Changes

#### Sandbox Profile

- **lockfile / atomic write サポート**: `lib/sandbox.sh` に lockfile パス（`.claude.lock`, `.claude.json.lock`）と atomic write regex（`.claude.json.tmp.*`）を追加
- **macOS Seatbelt 反映**: `lib/platform/sandbox-darwin.sh` の Seatbelt プロファイルに lockfile subpath と atomic write regex を反映
- **Linux systemd 反映**: `lib/platform/sandbox-linux-systemd.sh` の ReadWritePaths に lockfile ディレクトリを追加
- **Keychain書き込み許可の正式化**: `~/Library/Keychains` への書き込みを Seatbelt プロファイルで許可（Keychain 経由のトークン保存用途）
- **Seatbeltエスケープヘルパ追加**: `_seatbelt_escape` をユーティリティとして追加
- **Linux非対称性コメント追加**: `lib/platform/sandbox-linux-systemd.sh` に Linux 固有の挙動差を示すコメントを追加

#### Deny Log

- **macOS deny ログの自動記録**: `log stream --predicate` ベースで Seatbelt deny イベントを自動記録する仕組みを追加
- **hook 実装**: `_start_deny_log` / `_stop_deny_log` を `lib/platform/sandbox-darwin.sh` に実装、Linux 側は no-op hook で統一
- **ログ保存先の固定**: `$TMPDIR/jailrun-seatbelt-<PID>.log` に保存し、EXIT trap でクリーンアップ
- **デバッグモード連携**: `AGENT_SANDBOX_DEBUG=1` 設定時に deny ログを stderr にも出力
- **起動失敗時の挙動**: `log stream` 起動失敗時は stderr に警告を出し、jailrun 本体は継続起動

#### Fixes

- **Linux lockdir事前作成の除去**: `lib/platform/sandbox-linux-systemd.sh` から lockdir の事前作成処理を除去（#23）
- **EXIT trap での tmpdir クリーンアップ**: `lib/sandbox.sh` の EXIT trap が tmpdir クリーンアップを確実に行うよう修正

#### Tests

- **sandbox_deny_log.bats 新規追加**: deny ログの起動・停止・失敗時挙動を検証する bats テストを新設
- **既存テストの継続通過確認**: Unit 001 完了時に `sandbox_profile.bats` 既存 5 件が通過、Unit 002 完了時に deny ログ含む全 9 件テストが通過することを確認

#### Documentation

- **README.md 更新**: `docs/README.md` に Write Allowances（lockfile / atomic write）と Seatbelt Deny Log セクションを追加
- **architecture.md 更新**: `docs/architecture.md` に Deny Log データフローと Sandbox Architecture の更新を反映

### Compatibility

- 既存の deny/allow 挙動は変更なし。deny ログは観測のみで、サンドボックス判断には影響しない
- `log stream` 起動失敗時は jailrun 本体の起動を妨げず、stderr 警告のみで継続
- Linux 環境の deny ログ機能は no-op（macOS Seatbelt 固有。Linux 向けは将来サイクルで検討）

## v0.1.0 — コードベース整理・品質向上・ドキュメント整備 (2026-03-28)

既存コードベースを全体的にチェック・整理し、初回リリースに向けてコード品質・テストカバレッジ・ドキュメントの3つの軸で品質を引き上げた。

### Changes

#### Code Quality

- **config.py 責務分割**: `lib/config.py`(546行) を3ファイルに分割
  - `lib/config.py` — TOML解析・設定値API
  - `lib/config_cli.py` — CLIコマンド処理 (load/show/set/edit/path/init/migrate)
  - `lib/config_migrate.py` — レガシーshell設定→TOMLマイグレーション
- **sandbox.sh 関心分離**: env-spec生成・プロキシ管理の関数群をセクション境界で整理
- **token.sh CLI/ロジック分離**: CLI引数パースとキーチェーン操作の関数を分離
- **リポジトリ衛生整備**: `.gitignore` に `__pycache__/`, `*.pyc` 追加、追跡済み `__pycache__/` を除外

#### Tests

- **proxy.py ユニットテスト**: ドメインフィルタリング、プライベートIP検出、不正リクエスト処理 (26テストケース)
- **sandbox-linux-systemd.sh テスト**: systemd-run プロパティ生成の検証
- **credential-guard 統合テスト**: 二重サンドボックス防止 (`_CREDENTIAL_GUARD_SANDBOXED`) のガード条件テスト

#### Documentation

- **README.md 再構成**: Install / Quick Start / Configuration Reference / Troubleshooting の4セクション構成に整理
- **環境変数オーバーライド**: `AGENT_AWS_PROFILES`, `AWS_PROFILE`, `GH_TOKEN_NAME`, `SANDBOX_PASSTHROUGH_ENV` のランタイムオーバーライドを文書化
- **docs/architecture.md**: データフロー、ファイル構成、保護レイヤーの解説を新規作成
- **docs/contributing.md**: 開発環境セットアップ、テスト実行方法、コーディング規約を新規作成

### Compatibility

- CLI引数互換: `jailrun <agent> [args]` の引数体系は変更なし
- 設定ファイル互換: `~/.config/jailrun/config.toml` のキー名・構造は変更なし
- トークン互換: キーチェーン保存済みトークンはそのまま利用可能
