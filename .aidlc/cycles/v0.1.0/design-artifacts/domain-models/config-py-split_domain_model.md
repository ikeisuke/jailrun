# ドメインモデル: config.py 責務分割（v2 — レビュー反映）

## エンティティ・値オブジェクト

### config.py（TOML解析・設定値の読み書きAPI）
- `DEFAULTS`, `LIST_KEYS`, `KNOWN_KEYS`, `DEFAULT_TOML` — 定数定義
- `config_dir()`, `config_file()`, `legacy_config_file()` — パス解決
- `load_toml()`, `merge_layer()`, `resolve_config()` — 設定の読み込み・マージ
- `shell_escape()`, `to_shell()` — シェル出力変換
- `write_toml_value()`, `set_key_in_toml()` — TOML書き込みヘルパー
- `main()` は削除（エントリポイントはconfig_cli.pyに移動）

### config_cli.py（CLIコマンド処理 + エントリポイント）
- `cmd_load()` — load サブコマンド
- `cmd_show()` — show サブコマンド
- `cmd_set()` — set サブコマンド（--append, --remove含む）
- `cmd_edit()` — edit サブコマンド
- `cmd_path()` — path サブコマンド
- `cmd_init()` — init サブコマンド
- `main()` — コマンドディスパッチ（新エントリポイント）

### config_migrate.py（マイグレーション）
- `migrate_shell_to_toml()` — レガシ��シェル設定→TOML変換
- `cmd_migrate()` — migrate サブコマンド

## 依存関係（循環なし）

```
config_cli.py ──import──> config.py（定数、パス関数、resolve_config, set_key_in_toml等）
config_cli.py ──import──> config_migrate.py（cmd_migrate ���コマンドテーブルに登録）
config_migrate.py ──import──> config.py（DEFAULTS, LIST_KEYS, config_file, legacy_config_file）
```

依存方向: config_cli.py / config_migrate.py → config.py（一方向��み）

## 呼び出しインターフェース
- `lib/config-cmd.sh`: `exec python3 "$_LIB_DIR/config_cli.py" "$@"` に変更
- `lib/config.sh`: `python3 "$JAILRUN_LIB/config_cli.py" ...` に変更
- `python3 lib/config.py <subcommand>` — 直接呼び出しは非推奨（mainなし）
  - ���存テストは全てshellスクリプト経由なので影響なし
