# Unit 001: deny-read パス拡充 — 実装計画

## 対象Unit
001-deny-read-expansion

## 概要
主要クラウドサービス・開発ツールのクレデンシャルパス17件をdeny-readデフォルトに追加。macOS/Linux両対応。

## 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `lib/sandbox.sh` | `_SANDBOX_DENY_READ_PATHS`に17パス追加 |
| `lib/platform/sandbox-linux-systemd.sh` | InaccessiblePathsに追加パス反映 |
| `tests/sandbox_profile.bats` | 追加パスの存在確認テスト |
| `tests/sandbox_linux_systemd.bats` | InaccessiblePaths反映テスト |
| `docs/architecture.md` | deny-readパス一覧更新 |
| `docs/README.md` | 保護対象一覧更新 |

## 追加パスリスト（17件）

クラウド: `~/.config/gcloud`, `~/.azure`, `~/.oci`
コンテナ: `~/.docker`, `~/.kube`
CDN/デプロイ: `~/.wrangler`, `~/.config/wrangler`, `~/.fly`, `~/.config/netlify`, `~/.config/vercel`, `~/.config/heroku`
IaC/シークレット: `~/.terraform.d`, `~/.vault-token`, `~/.config/op`
開発ツール: `~/.config/hub`, `~/.config/stripe`, `~/.config/firebase`

## 完了条件チェックリスト

- [ ] sandbox.shの_SANDBOX_DENY_READ_PATHSに17パス追加
- [ ] sandbox-linux-systemd.shのInaccessiblePathsに反映
- [ ] sandbox_profile.batsに追加パスのテスト追加
- [ ] sandbox_linux_systemd.batsにInaccessiblePathsテスト追加
- [ ] docs/architecture.mdのdeny-readパス一覧更新
- [ ] docs/README.mdの保護対象一覧更新
- [ ] 既存テストがすべてパス
- [ ] jailrun経由でClaude Code, Codexが正常動作（手動確認）

## リスク

- Linux systemd-runのInaccessiblePathsに存在しないパスを指定した場合の挙動確認が必要
- 実装リスクは低（パスリスト追加が主な変更）
