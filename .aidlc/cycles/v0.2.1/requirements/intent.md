# Intent（開発意図）

## プロジェクト名
jailrun v0.2.1 — Keychainアクセス制限強化とクラウドクレデンシャルdeny-read拡充

## 開発の目的
macOS Seatbeltプロファイルで現在全面許可されているKeychainアクセスを必要最小限に制限する。また、AWS以外の主要クラウドサービス・開発ツールのクレデンシャルパスをdeny-readに追加し、AIエージェントからのクレデンシャル漏洩リスクを低減する。

## 背景
- 現在のSeatbeltプロファイルはSecurityServer（Keychain）への全アクセスを許可しており、AIエージェントがユーザーのKeychain内の任意のアイテムを読み取れる状態にある
- deny-readのデフォルトパスは~/.aws, ~/.config/gh, ~/.gnupg, ~/.sshの4つのみで、GCP, Azure, Docker等の主要クラウド/ツールのクレデンシャルパスが保護されていない
- #21（Add sandbox Keychain access profiles for Claude Code on macOS）で指摘されている通り、Keychainアクセスのプロファイル化が必要

## ターゲットユーザー
jailrunを使ってAIコーディングエージェントを安全に実行する開発者

## ビジネス価値
- Keychainアクセス制限により、AIエージェントが不要なキーチェーンアイテムにアクセスするリスクを排除
- クラウドクレデンシャルのdeny-read拡充により、AWS以外のクラウドサービスの認証情報もカーネルレベルで保護
- セキュリティラッパーとしてのjailrunの保護範囲を大幅に拡大

## 成功基準
- macOS SeatbeltプロファイルでKeychainアクセスが制限され、jailrunが管理するアイテム（jailrun:*）のみアクセス可能、それ以外のKeychainアクセスはブロックされる（Seatbelt技術制約により達成不可の場合は、~/Library/Keychains書き込みの絞り込みで代替）
- 下記「deny-read追加パス確定リスト」のすべてのパスがデフォルトdeny-readに追加されている
- 既存のテスト（sandbox_profile.bats等）がすべてパスする
- sandbox_profile.batsに追加パスの存在確認テストが追加されている
- jailrun経由でClaude Code, Codex, Gemini CLI, Kiro CLIが正常に動作する（既存動作の回帰なし）

## 含まれるもの

### 1. macOS Seatbelt Keychainアクセス制限（macOS固有）
- Seatbeltのkeychain-access-*系オペレーションを調査し、アイテム単位の制限が可能か検証
- 可能な場合: jailrunが管理するKeychainアイテムのみ許可、それ以外を拒否
- 不可能な場合: ~/Library/Keychains書き込みを特定のKeychainデータベースファイルに限定（subpath → literal）
- sandbox-darwin.shのプロファイル生成ロジック修正

### 2. クラウドクレデンシャルdeny-read追加（macOS/Linux共通）
- sandbox.shの_SANDBOX_DENY_READ_PATHSに以下の確定パスを追加
- Linux側はsandbox-linux-systemd.shのInaccessiblePathsにも反映

### 3. テスト追加・更新
- sandbox_profile.batsに追加deny-readパスの存在確認テスト
- Keychain制限のテスト（sandbox_profile.bats）
- sandbox_linux_systemd.batsにInaccessiblePaths反映テスト

### 4. ドキュメント更新
- docs/architecture.mdのdeny-readパス一覧を更新
- docs/README.mdの保護対象一覧を更新

## deny-read追加パス確定リスト

以下のパスを`_SANDBOX_DENY_READ_PATHS`に追加する。

### 選定基準
- **含める**: 認証トークン・APIキー・サービスアカウント鍵等のクレデンシャルを含むパス
- **除外する**: AIコーディングエージェントの正常動作に必要なパス、クレデンシャルを含まない設定のみのパス

### クラウドサービス
| パス | サービス | 含まれるクレデンシャル |
|------|---------|---------------------|
| `~/.config/gcloud` | Google Cloud SDK | サービスアカウント鍵、OAuthトークン |
| `~/.azure` | Azure CLI | サブスクリプション認証情報、トークン |
| `~/.oci` | Oracle Cloud Infrastructure | API署名鍵、テナント情報 |

### コンテナ・オーケストレーション
| パス | サービス | 含まれるクレデンシャル |
|------|---------|---------------------|
| `~/.docker` | Docker | レジストリ認証トークン（config.json） |
| `~/.kube` | Kubernetes | クラスタ認証情報（kubeconfig） |

### CDN・エッジ・デプロイ
| パス | サービス | 含まれるクレデンシャル |
|------|---------|---------------------|
| `~/.wrangler` | Cloudflare Wrangler（v1） | APIトークン |
| `~/.config/wrangler` | Cloudflare Wrangler（v2+） | APIトークン |
| `~/.fly` | Fly.io | APIトークン |
| `~/.config/netlify` | Netlify | アクセストークン |
| `~/.config/vercel` | Vercel | 認証トークン |
| `~/.config/heroku` | Heroku | APIキー |

### IaC・シークレット管理
| パス | サービス | 含まれるクレデンシャル |
|------|---------|---------------------|
| `~/.terraform.d` | Terraform | CLIトークン、プロバイダ認証 |
| `~/.vault-token` | HashiCorp Vault | Vaultトークン |
| `~/.config/op` | 1Password CLI | サービスアカウントトークン |

### 開発ツール
| パス | サービス | 含まれるクレデンシャル |
|------|---------|---------------------|
| `~/.config/hub` | GitHub Hub（レガシー） | OAuthトークン |
| `~/.config/stripe` | Stripe CLI | APIキー |
| `~/.config/firebase` | Firebase CLI | リフレッシュトークン |

## 含まれないもの
- GCP/Azure等のcredential isolation（一時ファイル経由での切り出し）— 将来のサイクルで検討
- proxy.pyやネットワーク制御の変更
- config.tomlのスキーマ変更

## 影響確認対象

| エージェント/ツール | 保証レベル | 確認内容 |
|-------------------|----------|---------|
| Claude Code | 必須保証 | OAuth認証連携、Keychain経由のトークンリフレッシュ |
| Codex | 必須保証 | jailrun shimでの起動・動作 |
| Gemini CLI | ベストエフォート | jailrun経由での起動 |
| Kiro CLI | ベストエフォート | jailrun経由での起動 |
| git (credential helper経由) | 必須保証 | GIT_ASKPASS経由のPATによるHTTPS認証 |

既知の非対応: Docker login、gcloud auth login等のクレデンシャル依存コマンドはサンドボックス内では使用不可（設計上の想定通り）

## 制約事項
- macOS Seatbeltのkeychain制御はmach-lookup / file-read*レベルであり、個別キーチェーンアイテム単位の制御には限界がある可能性あり — Construction Phaseで調査
- deny-readパスの追加はsandbox.shのパスリストへの追記で、macOS（Seatbelt）/ Linux（systemd InaccessiblePaths）の両方に適用
- Keychain制限強化はmacOS Seatbelt固有の変更
- パッチリリース（v0.2.1）のスコープに収まる範囲の変更とする

## 期限とマイルストーン
パッチリリースとして早期完了を目指す

## 不明点と質問（Inception Phase中に記録）

[Question] Seatbeltでkeychain-access-*系のオペレーションを使ってアイテム単位の制限が可能か
[Answer] Construction Phase（Reverse Engineering）で調査予定。不可能な場合は~/Library/Keychains書き込みのliteral制限で代替

[Question] Linux側のdeny-readパス追加も本サイクルに含めるか
[Answer] deny-readパスの追加はsandbox.shのパスリストに追加するため両プラットフォーム共通で適用。加えてLinux側はsandbox-linux-systemd.shのInaccessiblePathsにも反映する。Keychain制限のみmacOS固有
