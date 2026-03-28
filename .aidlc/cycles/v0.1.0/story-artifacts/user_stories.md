# ユーザーストーリー

## Epic 1: コード品質改善

### ストーリー 1a: config.py — TOML解析の分離
**優先順位**: Must-have

As a コントリビューター
I want to config.py のTOML解析・設定値読み書き機能が独立したモジュールになっている
So that 設定読み込みのバグ修正時にCLIやマイグレーションのコードに触れずに済む

**受け入れ基準**:
- [ ] `lib/config.py` がTOML解析・設定値の読み書きAPIのみを担当する（CLIコマンド処理・マイグレーション処理を含まない）
- [ ] `lib/config.py` を直接 `python3 lib/config.py load` で呼び出した場合、設定値がシェル変数形式で出力される（`config.sh` からの既存呼び出し経路）
- [ ] 既存の `tests/config.bats` のうちTOML読み込み・設定値取得に関するテストがパスする（終了コード0）

**技術的考慮事項**:
- Python 3 の tomllib（読み取り専用）を使用。書き込みは独自実装（既存の `_set_value` 等）
- `config.sh` からの呼び出しインターフェース（`python3 lib/config.py <subcommand>`）を維持
- `show` コマンドはCLIコマンドのためストーリー1bの責務

---

### ストーリー 1b: config.py — CLI処理の分離
**優先順位**: Must-have

As a コントリビューター
I want to config.py のCLIコマンド処理が独立したモジュールになっている
So that CLIサブコマンドの追加・変更時にTOML解析コードに影響しない

**受け入れ基準**:
- [ ] `lib/config_cli.py` が show/set/edit/init/path のCLIコマンド処理を担当する
- [ ] `lib/config-cmd.sh` が `lib/config_cli.py` を呼び出す
- [ ] `jailrun config show`, `jailrun config set <key> <value>`, `jailrun config path` が分割前と同一の出力・終了コードを返す
- [ ] 既存の `tests/config_cmd.bats` が全テストパスする（終了コード0）

---

### ストーリー 1c: config.py — マイグレーションの分離
**優先順位**: Must-have

As a コントリビューター
I want to config.py のマイグレーション処理が独立したモジュールになっている
So that マイグレーションロジックの変更がTOML解析やCLI処理に影響しない

**受け入れ基準**:
- [ ] `lib/config_migrate.py` がレガシーシェル設定からTOMLへのマイグレーション処理を担当する
- [ ] `jailrun config migrate` が分割前と同一の出力・終了コードを返す
- [ ] レガシー設定ファイル（`~/.config/jailrun/config`）からTOML（`~/.config/jailrun/config.toml`）への変換結果が分割前と同一
- [ ] 既存の `tests/config.bats` のマイグレーション関連テストがパスする

---

### ストーリー 2: リポジトリ衛生整備
**優先順位**: Must-have

As a コントリビューター
I want to 不要な生成ファイルがリポジトリの追跡対象に含まれない
So that クリーンなリポジトリ状態を維持し、PRの差分にノイズが入らない

**受け入れ基準**:
- [ ] `.gitignore` に `__pycache__/` と `*.pyc` のエントリが含まれる
- [ ] `git ls-files` の出力に `__pycache__` や `*.pyc` が含まれない
- [ ] Python実行後に新規生成された `.pyc` ファイルが `git status` で追跡対象にならない

---

## Epic 2: テスト追加

### ストーリー 3: proxy.py のユニットテスト追加
**優先順位**: Must-have

As a コントリビューター
I want to proxy.py のセキュリティ機能が自動テストで保護されている
So that ドメインフィルタリングやDNSリバインディング検出のリグレッションを即座に検出できる

**受け入れ基準**:
- [ ] `tests/` 配下に proxy.py 用のテストファイルが存在する
- [ ] 以下のシナリオがテストされている:

| 分類 | シナリオ | 期待結果 |
|------|---------|---------|
| 正常系 | 許可ドメインへのCONNECT要求 | 接続成功（200） |
| 拒否系 | 非許可ドメインへのCONNECT要求 | 接続拒否（403） |
| 拒否系 | プライベートIP（10.0.0.0/8）へのDNSリバインディング | 検出・拒否 |
| 拒否系 | リンクローカルIP（169.254.0.0/16）への解決 | 検出・拒否 |
| 拒否系 | ループバック（127.0.0.0/8, ::1）への解決 | 検出・拒否 |
| 設定不備 | 許可ドメインリストが空 | 全接続拒否 |
| 外部依存不在 | DNS名前解決失敗 | エラーレスポンス返却（プロセスクラッシュしない） |

- [ ] `make test` で新規テストがパスする

**技術的考慮事項**:
- pytest + モックベースで実装（実ネットワーク接続不要）
- `socket.getaddrinfo` をモックしてDNSリバインディングをシミュレート

---

### ストーリー 4: sandbox-linux-systemd.sh のテスト追加
**優先順位**: Must-have

As a コントリビューター
I want to Linux systemd-runプロパティ生成のリグレッションを自動テストで検出できる
So that Linuxサンドボックスの設定変更が意図しない影響を与えないことを保証できる

**受け入れ基準**:
- [ ] `tests/` 配下に sandbox-linux-systemd.sh 用のbatsテストファイルが存在する
- [ ] 以下のシナリオがテストされている:

| 分類 | シナリオ | 期待結果 |
|------|---------|---------|
| 正常系 | デフォルト設定でプロパティ生成 | NoNewPrivileges=yes, ProtectSystem=strict 等の必須項目を含む |
| 正常系 | プロキシ有効時のプロパティ生成 | IPAddressDeny=any, IPAddressAllow=127.0.0.0/8 を含む |
| 正常系 | プロキシ無効時のプロパティ生成 | IPAddressDeny/IPAddressAllow を含まない |
| 正常系 | カスタム書き込みパス指定時 | ReadWritePaths に指定パスが含まれる |
| 外部依存不在 | systemd-run コマンドが不在 | エラーメッセージを出力し非ゼロ終了（サンドボックスなしで実行しない） |
| 設定不備 | 不正な書き込みパス（空文字等）指定時 | 不正パスを無視し、デフォルトのReadWritePathsのみを出力 |

- [ ] `make test` で新規テストがパスする

**技術的考慮事項**:
- batsフレームワークで実装。プロパティ生成関数の出力文字列をgrep/パターンマッチでテスト
- 実際のsystemd-run実行は不要

---

### ストーリー 5: credential-guard 統合テスト追加
**優先順位**: Should-have

As a コントリビューター
I want to 認証情報ガードの主要パスが自動テストで検証されている
So that サンドボックス二重化防止やエラーハンドリングのリグレッションを検出できる

**受け入れ基準**:
- [ ] `tests/` 配下に credential-guard.sh 用のbatsテストファイルが存在する
- [ ] 以下のシナリオがテストされている:

| 分類 | シナリオ | 期待結果 |
|------|---------|---------|
| 正常系 | _CREDENTIAL_GUARD_SANDBOXED 未設定で呼び出し | サンドボックスセットアップ処理に進む |
| 正常系 | _CREDENTIAL_GUARD_SANDBOXED 設定済みで呼び出し | サンドボックスセットアップをスキップ |
| 外部依存不在 | sandbox-exec/systemd-run が不在 | エラーメッセージを出力し非ゼロ終了 |
| 設定不備 | config.toml が不正（構文エラー等） | エラーメッセージを出力し非ゼロ終了（クラッシュしない） |

- [ ] `make test` で新規テストがパスする

---

## Epic 3: ドキュメント整備

### ストーリー 6: README.md 再構成
**優先順位**: Must-have

As a エンドユーザー
I want to README.md の手順に従ってjailrunをインストールし初回実行できる
So that ドキュメントを読む以外の試行錯誤なしにjailrunを利用開始できる

**受け入れ基準**:
- [ ] README.md に「インストール手順」セクションが存在し、macOS/Linuxそれぞれの前提条件・コマンドが記載されている
- [ ] README.md に「クイックスタート」セクションが存在し、`jailrun codex exec "hello"` 等の実行例とその出力例が記載されている
- [ ] README.md に「設定リファレンス」セクションが存在し、`config-defaults.sh` に定義された全設定項目（項目名・デフォルト値・説明）が一覧化されている
- [ ] README.md に「トラブルシューティング」セクションが存在し、最低3つの問題と解決策が記載されている
- [ ] docs/README.md は詳細リファレンスとし、README.md からの相互参照リンクを設置。同一内容の重複記述がない

**技術的考慮事項**:
- 既存の README.md（47行）と docs/README.md（354行）の内容を精査。README.md をユーザー向けクイックリファレンスとし、docs/README.md を詳細リファレンスとする方針

---

### ストーリー 7: 開発者向けドキュメント作成
**優先順位**: Should-have

As a コントリビューター
I want to ドキュメントを読んで開発環境を構築しテストを実行できる
So that プロジェクトの構造を理解し、初回コントリビューションまでの障壁を下げられる

**受け入れ基準**:
- [ ] `docs/architecture.md` が存在し、5層レイヤードアーキテクチャ（エントリポイント→ラッパー→オーケストレーター→抽出→プラットフォーム）の説明が記載されている
- [ ] `docs/architecture.md` に認証情報の流れ（抽出→env-spec→exec.sh→sandbox）のデータフローが記載されている
- [ ] `docs/contributing.md` が存在し、前提条件（bats, Python 3等）のインストール手順が記載されている
- [ ] `docs/contributing.md` に `make test` によるテスト実行手順が記載されている
- [ ] `docs/contributing.md` にコーディング規約（POSIX sh準拠、`[[ ]]` 禁止、関数命名 `_snake_case`）が記載されている

---

## Epic 4: 追加リファクタリング

### ストーリー 8: sandbox.sh の関心分離
**優先順位**: Should-have

As a コントリビューター
I want to sandbox.sh のenv-spec生成・プロキシ管理が独立した関数群に整理されている
So that env-spec生成のバグ修正時にプロキシ管理コードを読む必要がなくなる

**受け入れ基準**:
- [ ] `_build_env_spec()` と `_start_proxy()` が明確な入出力を持つ独立関数として維持される（現状維持も可、ただしファイル内のセクション境界をコメントで明示する）
- [ ] env-spec生成部分を変更しても `_start_proxy()` のテストに影響しないこと（テストが独立に実行可能）
- [ ] 既存の `tests/sandbox_profile.bats` と `tests/passthrough_env.bats` が全テストパスする（終了コード0）
- [ ] `lib/credential-guard.sh` から sandbox.sh をsource後、`_build_sandbox_exec` 関数が呼び出し可能であること

---

### ストーリー 9: token.sh のCLI/ロジック分離
**優先順位**: Should-have

As a コントリビューター
I want to token.sh のCLI引数パースとキーチェーン操作が独立した関数群に整理されている
So that 新しいトークン操作を追加する際にCLIパース部分を変更せずに済む

**受け入れ基準**:
- [ ] CLI引数パース（`token_main`, `_token_usage`等）とキーチェーン操作（`_token_add`, `_token_delete`, `_token_list`, `_token_rotate`）が別セクション/別関数として明確に分離されている
- [ ] `jailrun token --help` が終了コード0でヘルプテキストを出力する
- [ ] `jailrun token add`, `jailrun token rotate`, `jailrun token delete`, `jailrun token list` の引数パース動作が変わらない（不正引数時の終了コードとエラーメッセージが同一）
- [ ] 既存の `tests/jailrun.bats` がパスする（終了コード0）
