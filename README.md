# jailrun

AI コーディングエージェントをクレデンシャル分離 + OS サンドボックスで安全に起動するセキュリティラッパー。

## 対応ツール

Claude Code, Codex, Gemini CLI, Kiro CLI

## インストール

```bash
make install                        # ~/.local/bin にインストール
make install PREFIX=/usr/local      # /usr/local/bin にインストール
```

初回起動時に `~/.config/jailrun/config` が自動生成される。

## 使い方

```bash
jailrun claude
jailrun codex exec "fix the bug"
jailrun gemini
jailrun kiro-cli

# AWS プロファイル指定
AGENT_AWS_PROFILE=staging jailrun claude

# トークン管理
jailrun token add --name github:fine-grained-myorg
jailrun token rotate --name github:fine-grained-myorg
jailrun token list
```

## 保護の仕組み

| 層 | 仕組み | 回避可能性 |
|----|--------|-----------|
| OS サンドボックス | Seatbelt (macOS) / systemd-run (Linux) | 不可（カーネル強制） |
| クレデンシャル分離 | 環境変数で一時認証を注入 | 不可（起動前に確定） |
| サービス側制限 | IAM Role / Fine-grained PAT | 不可（サーバ側で拒否） |

詳細は [docs/README.md](docs/README.md) を参照。

## ライセンス

MIT
