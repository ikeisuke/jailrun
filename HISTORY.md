# Change History

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
