# 既存コードベース分析

## ディレクトリ構造・ファイル構成

```
jailrun/
├── bin/jailrun                      # CLIエントリポイント
├── lib/
│   ├── credential-guard.sh          # オーケストレーター
│   ├── config.sh / config.py        # 設定読み込み（TOML）
│   ├── credentials.sh               # AWS + GitHub認証情報抽出
│   ├── sandbox.sh                   # サンドボックスパスリスト・exec生成
│   ├── aws.sh                       # AWSクレデンシャル分離
│   ├── proxy.py                     # HTTPSプロキシ
│   ├── token.sh                     # トークン管理
│   └── platform/
│       ├── sandbox-darwin.sh        # macOS Seatbeltプロファイル生成
│       ├── sandbox-linux-systemd.sh # Linux systemd-runプロパティ
│       ├── keychain-darwin.sh       # macOS Keychain取得
│       └── keychain-linux.sh        # Linux GNOME Keyring取得
├── tests/                           # bats + pytest
└── docs/                            # アーキテクチャ・セットアップガイド
```

## アーキテクチャ・パターン

- **レイヤード構成**: bin/ → lib/ → lib/platform/ の3層（根拠: ファイル構成とsource関係）
- **プラットフォーム抽象化**: sandbox.sh がプラットフォーム固有バックエンドをsourceする（根拠: `sandbox-darwin.sh` / `sandbox-linux.sh`）
- **パスリストパターン**: deny-read / allow-write パスを改行区切り変数で管理（根拠: `sandbox.sh` L15-92）
- **プロファイル動的生成**: Seatbelt .sb ファイルを実行時に tmpdir に生成（根拠: `sandbox-darwin.sh` L22-100）

### 本サイクルに関連する重要ポイント

1. **deny-readパス定義** (`sandbox.sh` L15-25):
   - ハードコードされた4パス: `~/.aws`, `~/.config/gh`, `~/.gnupg`, `~/.ssh`
   - `SANDBOX_EXTRA_DENY_READ` 設定で追加可能

2. **Keychain/SecurityServerアクセス** (`sandbox-darwin.sh` L27-30):
   - `(allow default)` により全アクセス許可
   - SecurityServerを個別にdeny/allowする制御なし
   - コメントで「TLS証明書検証とトークンリフレッシュのため意図的に許可」と明記

3. **~/Library/Keychains書き込み許可** (`sandbox.sh` L47-52):
   - subpath write access（ディレクトリ全体）
   - コメントに「特定ファイルへの絞り込みは将来の改善」と記載

## 技術スタック

| 項目 | 値 | 根拠ファイル |
|------|-----|-------------|
| 言語 | Shell (POSIX sh), Python 3 | `lib/*.sh`, `lib/proxy.py`, `lib/config.py` |
| フレームワーク | なし（CLIツール） | - |
| 主要ライブラリ | bats-core（テスト）, jq（オプション） | `tests/*.bats`, `lib/aws.sh` |
| ビルドツール | Make | `Makefile` |
| テスト | bats-core, pytest | `tests/*.bats`, `tests/test_proxy.py` |

## 依存関係

### 内部モジュール（source関係）
```
bin/jailrun → lib/agent-wrapper.sh → lib/credential-guard.sh
  ├── lib/config.sh
  ├── lib/credentials.sh → lib/aws.sh, lib/platform/keychain-*.sh
  └── lib/sandbox.sh → lib/platform/sandbox-darwin.sh or sandbox-linux.sh
```

### 外部依存
- macOS: `sandbox-exec`（Seatbelt）, `security`（Keychain）, `log`（deny log）
- Linux: `systemd-run`, `secret-tool`（GNOME Keyring）
- 共通: `python3`, `git`, `curl`, `jq`（オプション）

循環依存: なし

## 特記事項

- Seatbeltプロファイルの `(allow default)` はすべてのアクションを許可し、その後に deny ルールで制限を追加する「ホワイトリスト反転」モデル。Keychainアクセス制御はこの構造の中で対応する必要がある
- `SANDBOX_EXTRA_DENY_READ` は既存の拡張ポイントであり、新しいデフォルトdeny-readパスの追加はハードコード部分（`sandbox.sh` L15-18）への追記が自然
- Linux systemd-run側にはdeny-readパスの概念がない（`ProtectHome=read-only` で全ホームが読み取り専用になるため、個別パスのdeny-readは`InaccessiblePaths`で実装可能）
