# Unit: config.py 責務分割

## 概要
`lib/config.py`（546行）を3つのファイルに分割し、TOML解析・CLI処理・マイグレーションの責務を明確に分離する。Must-have中核のリファクタリング。

## 含まれるユーザーストーリー
- ストーリー 1a: config.py — TOML解析の分離
- ストーリー 1b: config.py — CLI処理の分離
- ストーリー 1c: config.py — マイグレーションの分離

## 責務
- `lib/config.py` をTOML解析・設定値読み書きAPIに限定
- `lib/config_cli.py` を新規作成し、show/set/edit/init/path等のCLIコマンド処理を移動
- `lib/config_migrate.py` を新規作成し、レガシー設定→TOMLマイグレーション処理を移動
- `lib/config.sh` と `lib/config-cmd.sh` の呼び出し先を更新
- 既存テスト（config.bats, config_cmd.bats）の全パスを確認

## 境界
- config.py内部のロジック改善（アルゴリズム変更等）は行わない
- 新しい設定項目の追加は行わない
- config.tomlのフォーマット変更は行わない

## 依存関係

### 依存する Unit
- なし

### 外部依存
- Python 3（tomllib）

## 非機能要件（NFR）
- **パフォーマンス**: 分割前と同等の設定読み込み速度を維持
- **セキュリティ**: 設定ファイルのパーミッション処理を変更しない
- **スケーラビリティ**: 該当なし
- **可用性**: 該当なし

## 完了条件
- `make test` が全パスすること（`posix_compliance.bats`, `config.bats`, `config_cmd.bats` 含む）

## 技術的考慮事項
- `python3 lib/config.py <subcommand>` の呼び出しインターフェースを維持
- config_cli.py と config_migrate.py は config.py をimportして使用
- 分割は責務の移動のみ。ロジック変更は最小限に抑える

## 実装優先度
High

## 見積もり
中（3ストーリー分、既存テストによる回帰確認込み）

---
## 実装状態

- **状態**: 未着手
- **開始日**: -
- **完了日**: -
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
