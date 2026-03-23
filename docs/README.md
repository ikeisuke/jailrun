# AI エージェント セキュリティラッパー

AI コーディングエージェント（Claude Code, Codex, Kiro CLI, Gemini CLI）が
ローカルのクレデンシャルを悪用することを防ぐ多層防御の仕組み。

## 問題

エージェントはユーザーの端末で動くため、`~/.aws`, `~/.ssh`, `~/.config/gh` 等の
クレデンシャルにフルアクセスできる。管理者権限のトークンが漏洩・悪用されるリスクがある。

## アーキテクチャ

```
保護層                          仕組み                     回避可能性
────────────────────────────────────────────────────────────────────
Layer 1: OS サンドボックス       Seatbelt / systemd-run     不可（カーネル強制）
Layer 2: クレデンシャル分離      環境変数で一時認証を注入    不可（起動前に確定）
Layer 3: サービス側制限          IAM Role / Fine-grained PAT 不可（サーバ側で拒否）
Layer 4: ツール固有の設定        permissions.deny / hook 等  低〜中（AI の判断に依存）
```

## ファイル構成

```
bin/
└── jailrun                  # エントリポイント（サブコマンドディスパッチ）

lib/
├── credential-guard.sh      # 共通ライブラリ（クレデンシャル分離 + サンドボックス）
├── agent-wrapper.sh         # 共通ラッパーテンプレート（各ツール向け）
└── token-rotate.sh          # GitHub PAT ローテーション

~/.config/security-wrapper/
└── config                   # マシン固有の設定（git 管理外、初回自動生成）
```

## 各ツールの保護レベル

| 保護 | Claude Code | Codex | Kiro CLI | Gemini CLI |
|------|------------|-------|----------|------------|
| クレデンシャル分離 | `credential_guard_sandbox_exec` | `credential_guard_sandbox_exec` | `credential_guard_sandbox_exec` | `credential_guard_sandbox_exec` |
| OS サンドボックス | Seatbelt（※注） | Seatbelt / systemd-run | Seatbelt / systemd-run | Seatbelt / systemd-run |
| 書き込み制限 | Seatbelt ホワイトリスト | Seatbelt / systemd-run | Seatbelt / systemd-run | Seatbelt / systemd-run |
| permissions.deny | あり | なし | なし | なし |
| PreToolUse hook | あり（sandbox 未適用時ブロック） | なし | なし | なし |
| ネットワーク制限 | なし | 内蔵（デフォルト遮断） | なし | なし |

> **※注**: Claude Code は sandbox-exec 内で起動されるが、子プロセス（Bash ツール）に
> sandbox が継承されない問題あり。`permissions.deny` と PreToolUse hook で補完している。

## セットアップ

### 1. インストール

```bash
make install           # /usr/local にインストール
make install PREFIX=~  # ~/bin, ~/lib にインストール
```

### 2. 初回起動

```bash
jailrun claude  # または codex, gemini, kiro-cli, kiro-cli-chat
```

初回は `~/.config/security-wrapper/config` が自動生成され、設定を促して終了する。

### 3. 設定ファイルを編集

```bash
vi ~/.config/security-wrapper/config
```

```bash
# 許可する AWS プロファイル（スペース区切り）
ALLOWED_AWS_PROFILES="dev staging"

# デフォルトプロファイル
DEFAULT_AWS_PROFILE="dev"

# jailrun token で登録した名前（github:classic / github:fine-grained-myorg 等）
GH_KEYCHAIN_SERVICE="github:classic"

# バイナリパスは自動検出済み（通常編集不要）
CLAUDE_BIN="/opt/homebrew/bin/claude"
CODEX_BIN="/opt/homebrew/bin/codex"
KIRO_CLI_BIN="/Users/you/.local/bin/kiro-cli"
KIRO_CLI_CHAT_BIN="/Users/you/.local/bin/kiro-cli-chat"
GEMINI_BIN="/opt/homebrew/bin/gemini"
```

### 4. GitHub PAT を設定

[github-pat-setup.md](./github-pat-setup.md) を参照。
Fine-grained と Classic の2種類を別々の Keychain サービス名で保持できる。

### 5. Linux/WSL2 の場合

systemd-run を利用（systemd 環境なら追加インストール不要）:

```bash
# WSL2 で systemd が有効か確認
systemctl --user status
```

GitHub トークンは `secret-tool`（GNOME Keyring）で管理:

```bash
sudo apt install libsecret-tools gnome-keyring    # Ubuntu/Debian

# トークンを保存（echo -n でパイプし、制御文字混入を防止）
echo -n "ghp_xxxx" | secret-tool store --label="GitHub PAT Classic" service ai-agent-gh-token-classic account "$USER"

# 確認（xxd で制御文字が混入していないか確認）
secret-tool lookup service ai-agent-gh-token-classic account "$USER" | xxd | head -1
```

`secret-tool` 未インストールの場合は GitHub PAT なしで動作する（WARN 表示）。
環境変数フォールバックは廃止済み — セキュアストアのみをサポート。

## 使い方

```bash
# 通常起動（設定済みプロファイルで保護される）
jailrun claude
jailrun codex
jailrun kiro-cli
jailrun gemini

# 一時的に別の AWS プロファイルを使う（許可リスト内に限る）
AGENT_AWS_PROFILE=staging jailrun claude

# 複数プロファイルをロード（許可リスト内に限る）
AGENT_AWS_PROFILES="dev staging" jailrun claude

# シェルの AWS_PROFILE を引き継ぐ
AWS_PROFILE=dev jailrun claude
```

### AWS プロファイルの優先順位

```
AGENT_AWS_PROFILE  →  AWS_PROFILE  →  config の DEFAULT_AWS_PROFILE
（最優先）            （シェルの設定）   （フォールバック）
```

## サンドボックスの保護

### 読み取り拒否パス

以下のディレクトリはカーネルレベルで読み取りが拒否される:

| パス | 内容 | 備考 |
|------|------|------|
| `~/.aws` | AWS クレデンシャル、SSO キャッシュ、設定 | |
| `~/.config/gh` | GitHub CLI トークン | |
| `~/.gnupg` | GPG 秘密鍵 | |
| `~/.ssh` | SSH 秘密鍵、known_hosts | |

> **SSH→HTTPS 変換**: git の SSH URL（`git@github.com:` / `ssh://git@github.com/`）は
> `GIT_CONFIG` env 変数で HTTPS に自動変換され、`GIT_ASKPASS` 経由で `GH_TOKEN` を使って認証する。
> これにより SSH 鍵なしで git 操作が可能。
> Linux (systemd-run) では環境変数が自動継承されないため、`-E` フラグで明示的に渡す。

### sandbox 検出（ネスト防止）

エージェントが別のエージェントを呼ぶ場合（Claude → Codex 等）、二重 sandbox を防止する。
検出は2段構え:

1. `_CREDENTIAL_GUARD_SANDBOXED=1` 環境変数（env を継承するツール向け）
2. `~/.aws/config` の読み取り可否（Claude のように env を継承しないツール向け）

### Codex の内蔵 sandbox 対策

Codex は自身で sandbox-exec を適用するため、ラッパーの Seatbelt と競合する。
サブコマンドに応じて内蔵 sandbox を無効化:

| サブコマンド | 方式 |
|-------------|------|
| `exec` / `e` | `-s danger-full-access` をサブコマンド後に挿入 |
| `review` | `-c 'sandbox_mode="danger-full-access"'` をサブコマンド後に挿入 |

ユーザーが `-s` / `--sandbox` を指定した場合は `danger-full-access` に強制上書きされ、
警告が表示される（二重 sandbox 防止のため）。

## Claude Code 固有の保護

### permissions.deny / permissions.ask

Claude Code の `settings.json` で設定:

- **deny**: `~/.aws`, `~/.ssh` の Read/Bash、`aws sso get-role-credentials` 等の直接実行
- **ask**: `~/.aws`, `~/.config/gh` を含む Bash コマンド（確認ダイアログ）

### PreToolUse hook

sandbox 未適用で起動した場合、全ツール実行をブロック:

```json
"PreToolUse": [{
  "hooks": [{
    "type": "command",
    "command": "if [ -r ~/.aws/config ]; then echo 'sandbox未適用です。jailrun claude から起動し直してください' >&2; exit 2; fi"
  }]
}]
```

- `~/.aws/config` が読める → sandbox 未適用 → exit 2 でブロック
- `~/.aws/config` が読めない → sandbox 適用済み → exit 0 で許可

## 動作確認

エージェント内で以下を試して `Operation not permitted` が返れば成功:

```
cat ~/.aws/config
```

Claude Code の場合は Read ツールでも確認:
- `File is in a directory that is denied` → permissions.deny（ツールレベル）
- `Operation not permitted` → sandbox（カーネルレベル）

## トラブルシューティング

### "AWS プロファイルのクレデンシャル取得失敗"

SSO セッションが切れている。再ログインする:

```bash
aws sso login --profile <プロファイル名>
```

### サンドボックスのデバッグ

`AGENT_SANDBOX_DEBUG=1` で起動すると:
- 書き込み制限を無効化する（読み取り拒否は有効のまま）
- exec コマンドを stderr に表示

`find -newer` と組み合わせてホワイトリスト外への書き込み先を特定する:

```bash
# ターミナル1: マーカーを作成
touch /tmp/before-agent

# ターミナル2: デバッグモードで起動して操作を再現
AGENT_SANDBOX_DEBUG=1 jailrun claude

# ターミナル1: 操作後に書き込み先を確認
find ~ -maxdepth 4 -newer /tmp/before-agent \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/Library/Logs/*' \
  -not -path '*/.claude/projects/*' \
  2>/dev/null | sort
```

追加すべきパスを特定したら `lib/credential-guard.sh` の `_SANDBOX_ALLOW_WRITE_PATHS` / `_SANDBOX_ALLOW_WRITE_FILES` に追加する。

### エージェントが起動しない・動作がおかしい

サンドボックスの書き込み制限が原因の可能性がある。以下の手順で切り分ける:

```bash
# 1. 実体を直接起動して sandbox が原因か確認
/opt/homebrew/bin/claude

# 2. 起動できたら sandbox が原因。書き込み先を特定する:
touch /tmp/before-agent

# 3. AGENT_SANDBOX_DEBUG=1 で起動して操作を再現
AGENT_SANDBOX_DEBUG=1 jailrun claude

# 4. 変更されたファイルを確認
find ~ -maxdepth 4 -newer /tmp/before-agent \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/Library/Logs/*' \
  -not -path '*/.claude/projects/*' \
  2>/dev/null | sort
```

特定できたパスを `lib/credential-guard.sh` の `_SANDBOX_ALLOW_WRITE_PATHS` または
`_SANDBOX_ALLOW_WRITE_FILES` に追加する。

### ラッパーをバイパスしたい

jailrun を使わず、実体を直接呼ぶ:

```bash
/opt/homebrew/bin/claude
```
