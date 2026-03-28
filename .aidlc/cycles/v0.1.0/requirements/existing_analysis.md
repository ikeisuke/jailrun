# 既存コードベース分析

## ディレクトリ構造・ファイル構成

```
.
├── bin/
│   └── jailrun                    # エントリポイント（シェルスクリプト）
├── lib/
│   ├── agent-wrapper.sh           # エージェントラッパー（引数書き換え、二重サンドボックス防止）
│   ├── aws.sh                     # AWS認証情報抽出
│   ├── config.sh                  # 設定読み込み（config.pyを呼び出し）
│   ├── config.py                  # TOML設定パーサー（Python）
│   ├── config-cmd.sh              # config CLIディスパッチ
│   ├── config-defaults.sh         # デフォルト設定値
│   ├── credential-guard.sh        # サンドボックスオーケストレーター
│   ├── credentials.sh             # 認証情報抽出（AWS/GitHub）
│   ├── proxy.py                   # HTTPSプロキシ（ドメイン許可リスト）
│   ├── ruleset.sh                 # GitHub APIルールセット
│   ├── sandbox.sh                 # サンドボックス構築
│   ├── token.sh                   # トークン管理CLI
│   ├── platform/
│   │   ├── git-worktree.sh        # git worktree検出
│   │   ├── keychain-darwin.sh     # macOSキーチェーン
│   │   ├── keychain-linux.sh      # Linuxキーリング
│   │   ├── sandbox-darwin.sh      # macOS Seatbeltプロファイル生成
│   │   ├── sandbox-linux.sh       # Linuxサンドボックスディスパッチ
│   │   └── sandbox-linux-systemd.sh # systemd-runプロパティ生成
│   └── shims/
│       └── codex                  # Codexシム（jailrun経由で再実行）
├── tests/
│   ├── helpers.bash               # テストヘルパー
│   ├── jailrun.bats               # CLI基本テスト
│   ├── codex_args.bats            # Codex引数書き換えテスト
│   ├── config.bats                # 設定読み込みテスト
│   ├── config_cmd.bats            # configコマンドテスト
│   ├── passthrough_env.bats       # 環境変数パススルーテスト
│   ├── path_resolution.bats       # パス解決テスト
│   ├── posix_compliance.bats      # POSIX準拠テスト
│   ├── sandbox_profile.bats       # サンドボックスプロファイルテスト
│   └── shim.bats                  # シムテスト
├── docs/
│   ├── README.md                  # 詳細ドキュメント
│   └── github-pat-setup.md        # GitHub PAT設定ガイド
├── Makefile                       # ビルド・テスト
├── README.md                      # プロジェクトREADME
└── LICENSE                        # ライセンス
```

- 総コード行数: 約2,854行（テスト除く）
- テスト: 9ファイル、約696行

## アーキテクチャ・パターン

### アーキテクチャ: レイヤードアーキテクチャ（5層）

1. **エントリポイント層**: `bin/jailrun` — CLI解析、PATH解決
2. **ラッパー層**: `lib/agent-wrapper.sh` — エージェント引数書き換え、二重サンドボックス防止
3. **オーケストレーター層**: `lib/credential-guard.sh`, `lib/sandbox.sh` — サンドボックス構築制御
4. **抽出層**: `lib/credentials.sh`, `lib/config.sh` — 認証情報・設定の抽出
5. **プラットフォーム層**: `lib/platform/*.sh` — OS固有実装（macOS/Linux）

根拠: `bin/jailrun` → `agent-wrapper.sh` → `credential-guard.sh` → `sandbox.sh` → `platform/*.sh` の一方向依存

### デザインパターン

- **Strategy パターン**: プラットフォーム別サンドボックス実装（darwin/linux）の切り替え（根拠: `sandbox.sh` が `$_PLATFORM` で `sandbox-darwin.sh` / `sandbox-linux.sh` を動的にsource）
- **Shim パターン**: `lib/shims/codex` がCodexコマンドをjailrun経由に透過的にリダイレクト（根拠: `exec jailrun codex "$@"`）
- **環境変数注入パターン**: env-specファイルでUNSET/SETディレクティブを生成し、exec.shが読み取り・適用（根拠: `_build_env_spec()` in `sandbox.sh`）

### コーディング規約

- POSIX sh準拠（`#!/bin/sh`）— `[[ ]]` 禁止、`test` / `[ ]` のみ使用
- 関数名: `_snake_case`（プライベート関数にアンダースコアプレフィックス）
- 変数名: `UPPER_SNAKE_CASE`（環境変数）、`_lower_snake_case`（ローカル変数）
- 日本語文字列なし（POSIX準拠テストで検証済み）

## 技術スタック

| 項目 | 値 | 根拠ファイル |
|------|-----|-------------|
| 言語 | POSIX Shell, Python 3 | bin/jailrun (#!/bin/sh), lib/config.py, lib/proxy.py |
| フレームワーク | なし | - |
| テストフレームワーク | bats (Bash Automated Testing System) | tests/*.bats |
| 設定形式 | TOML | lib/config.py (tomllib使用) |
| ビルドツール | Make | Makefile |
| サンドボックス(macOS) | Seatbelt (sandbox-exec) | lib/platform/sandbox-darwin.sh |
| サンドボックス(Linux) | systemd-run | lib/platform/sandbox-linux-systemd.sh |
| キーチェーン(macOS) | security コマンド | lib/platform/keychain-darwin.sh |
| キーチェーン(Linux) | secret-tool (GNOME Keyring) | lib/platform/keychain-linux.sh |

## 依存関係

### 内部モジュール間依存（境界単位: ファイル）

```
bin/jailrun
  → lib/agent-wrapper.sh
    → lib/config.sh → lib/config.py
    → lib/credentials.sh → lib/aws.sh, lib/platform/keychain-*.sh
    → lib/credential-guard.sh
      → lib/sandbox.sh
        → lib/platform/git-worktree.sh
        → lib/platform/sandbox-darwin.sh / sandbox-linux.sh
        → lib/proxy.py（プロキシ有効時）
```

- **循環依存**: なし
- **依存方向**: 一貫して上位→下位の一方向

### 外部依存

| 依存先 | 用途 | 必須/オプション |
|--------|------|----------------|
| Python 3 (tomllib) | TOML設定解析 | 必須 |
| aws CLI | AWS認証情報抽出 | オプション |
| gh CLI | GitHub API操作 | オプション |
| security (macOS) | キーチェーンアクセス | macOSで必須 |
| secret-tool (Linux) | キーリングアクセス | Linuxで必須 |
| sandbox-exec (macOS) | Seatbeltサンドボックス | macOSで必須 |
| systemd-run (Linux) | systemdサンドボックス | Linuxで必須 |
| bats | テスト実行 | 開発時のみ |

### エントリポイントとデータフロー

```
ユーザー: jailrun <agent> [args]
  → PATH解決（実際のエージェントバイナリ発見）
  → 引数書き換え（Codex: --sandbox → -s danger-full-access）
  → 認証情報抽出（AWS/GitHub、キーチェーンから取得）
  → env-spec生成（UNSET/SETディレクティブ）
  → プロキシ起動（有効時、ドメイン許可リスト付き）
  → exec.sh生成（環境変数設定 + サンドボックスコマンド）
  → サンドボックス内でエージェント実行
  → 終了時: 一時ファイル・認証情報クリーンアップ（trap）
```

## 特記事項

### テストカバレッジのギャップ

- `credential-guard.sh`: 直接テストなし（統合テスト経由のみ）
- `credentials.sh`: 直接テストなし（AWS/キーチェーン要）
- `proxy.py`: テストなし（DNSリバインディング保護、ドメインフィルタリング未テスト）
- `sandbox-linux-systemd.sh`: テストなし
- `keychain-*.sh`: テストなし（プラットフォーム固有）
- `ruleset.sh`: テストなし（GitHub API認証要）
- エラー条件・エッジケースのテストが不足

### コード品質の課題

- `config.py` (546行): 複数責務（TOML解析、CLI、マイグレーション）が1ファイルに集約
- `sandbox.sh` (266行): プラットフォーム共通ロジック + env-spec生成 + プロキシ管理が混在
- `token.sh` (277行): CLI解析とキーチェーン操作が混在
- `__pycache__/` がリポジトリに含まれている可能性（.gitignore要確認）
- ドキュメント（docs/README.md）とREADME.mdの内容の重複・不整合の可能性
