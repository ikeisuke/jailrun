# 論理設計: config.py 責務分割（v2 — レビュー反映）

## ファイル構成

```
lib/
├── config.py          # TOML解析・設定値API + 後方互換エントリポイント(__main__のみ)
├── config_cli.py      # CLIコマンド処理 + エントリポイント
└── config_migrate.py  # レガシー設定→TOMLマイグレーション
```

## config.py の変更

### 残すもの
- import文: `os`, `sys`, `copy`, `Path`, `tomllib`
- 定数: `DEFAULTS`, `LIST_KEYS`, `KNOWN_KEYS`, `DEFAULT_TOML`
- パス関数: `config_dir()`, `config_file()`, `legacy_config_file()`
- 読み込み: `load_toml()`, `merge_layer()`, `resolve_config()`
- シェル出力: `shell_escape()`, `to_shell()`
- TOML書き込み: `write_toml_value()`, `set_key_in_toml()`

### 削除するもの（config_cli.pyへ移動）
- `cmd_load()`, `cmd_show()`, `cmd_set()`, `cmd_edit()`, `cmd_path()`, `cmd_init()`
- `main()` 関数とコマンドディスパッチ
- docstring のサブコマンド説明（config_cli.pyへ移動）

### 削除するもの（config_migrate.pyへ移動）
- `migrate_shell_to_toml()`
- `cmd_migrate()`

### 不要になるimport
- `subprocess` — 未使用

### `if __name__ == "__main__":` ブロック
後方互換エントリポイントとして残す:
```python
if __name__ == "__main__":
    from config_cli import main
    main()
```
config_cli のimportは実行時のみ発生し、モジュールレベルの循環にはならない。

## config_cli.py の構成

```python
#!/usr/bin/env python3
"""jailrun configuration CLI.

Subcommands:
    load   --app NAME --dir PATH   Merge config and output shell-eval format
    show                            Display current config values
    ...（元のconfig.pyのdocstringを移動）
"""

from __future__ import annotations
import os
import sys
from config import (
    DEFAULTS, LIST_KEYS, KNOWN_KEYS, DEFAULT_TOML,
    config_dir, config_file,
    resolve_config, set_key_in_toml, to_shell,
)
from config_migrate import cmd_migrate

def cmd_load(args): ...
def cmd_show(args): ...
def cmd_set(args): ...
def cmd_edit(args): ...
def cmd_path(args): ...
def cmd_init(args): ...

def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    commands = {
        "load": cmd_load, "show": cmd_show, "set": cmd_set,
        "edit": cmd_edit, "path": cmd_path, "init": cmd_init,
        "migrate": cmd_migrate,
    }
    if cmd in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)
    if cmd not in commands:
        print(f"[config] ERROR: unknown subcommand '{cmd}'", file=sys.stderr)
        sys.exit(1)
    commands[cmd](args)

if __name__ == "__main__":
    main()
```

## config_migrate.py の構成

```python
#!/usr/bin/env python3
"""jailrun legacy config migration."""

from __future__ import annotations
import copy
import sys
from config import (
    DEFAULTS, LIST_KEYS,
    config_file, legacy_config_file,
)

def migrate_shell_to_toml(shell_path): ...
def cmd_migrate(args): ...
```

## 循環importなし

依存方向が一方向（config_cli.py/config_migrate.py → config.py）のため循環なし。

## シェルスクリプト変更

### lib/config-cmd.sh
```diff
-exec python3 "$_LIB_DIR/config.py" "$@"
+exec python3 "$_LIB_DIR/config_cli.py" "$@"
```

### lib/config.sh（3箇所）
```diff
-python3 "$JAILRUN_LIB/config.py" migrate --force
+python3 "$JAILRUN_LIB/config_cli.py" migrate --force

-_config_output="$(python3 "$JAILRUN_LIB/config.py" load --app ...)"
+_config_output="$(python3 "$JAILRUN_LIB/config_cli.py" load --app ...)"

-python3 "$JAILRUN_LIB/config.py" init
+python3 "$JAILRUN_LIB/config_cli.py" init
```

## テスト影響（3系統に分類）

### 1. config.sh 経由（tests/config.bats）
config.shの呼び出し先をconfig_cli.pyに変更。config.shを経由するテストは変更不要。

### 2. config-cmd.sh 経由（tests/config_cmd.bats）
config-cmd.shの呼び出し先をconfig_cli.pyに変更。config-cmd.shを経由するテストは変更不要。

### 3. config.py 直接実行
既存テストにはconfig.pyを直接呼び出すテストが存在しない。`python3 lib/config.py <subcommand>`は__main__ガード経由でconfig_cli.main()にデリゲートされるため、後方互換を維持。二重ロード（__main__とconfigモジュール）が発生するが、config.pyは定数と純粋関数のみのため副作用なし。
