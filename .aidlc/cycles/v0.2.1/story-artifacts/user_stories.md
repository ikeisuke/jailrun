# ユーザーストーリー

## Epic: クレデンシャル保護範囲の拡充

### ストーリー 1: クラウドクレデンシャルのdeny-read保護
**優先順位**: Must-have

As a jailrun利用者
I want to 主要クラウドサービス（GCP, Azure, Docker, Kubernetes等）のクレデンシャルパスがサンドボックスのdeny-readで保護されている
So that AIエージェントが意図せずクラウドサービスの認証情報を読み取るリスクを排除できる

**受け入れ基準**:

コード変更:
- [ ] `~/.config/gcloud`, `~/.azure`, `~/.oci` がdeny-readに追加されている
- [ ] `~/.docker`, `~/.kube` がdeny-readに追加されている
- [ ] `~/.wrangler`, `~/.config/wrangler`, `~/.fly`, `~/.config/netlify`, `~/.config/vercel`, `~/.config/heroku` がdeny-readに追加されている
- [ ] `~/.terraform.d`, `~/.vault-token`, `~/.config/op` がdeny-readに追加されている
- [ ] `~/.config/hub`, `~/.config/stripe`, `~/.config/firebase` がdeny-readに追加されている
- [ ] macOSでSeatbeltプロファイルに上記パスのdeny file-read*ルールが含まれている
- [ ] Linux（systemd-run）でInaccessiblePathsに上記パスが反映されている

テスト:
- [ ] sandbox_profile.batsに追加パスの存在確認テストがある
- [ ] sandbox_linux_systemd.batsにInaccessiblePaths反映テストがある

動作確認:
- [ ] jailrun経由でClaude Code, Codexが正常に起動・動作する

**技術的考慮事項**:
- deny-readパスは`sandbox.sh`の`_SANDBOX_DENY_READ_PATHS`に追加（macOS/Linux共通）
- Linux側は`sandbox-linux-systemd.sh`のInaccessiblePathsにも反映が必要
- 存在しないパスのdeny-readはエラーにならないことを確認

---

### ストーリー 2a: Seatbelt Keychain制御可否の調査
**優先順位**: Must-have

As a macOSでjailrunを利用する開発者
I want to Seatbeltで実現可能なKeychainアクセス制限の技術的限界が明らかになっている
So that 最も効果的なアクセス制限方式を選定して実装できる

**受け入れ基準**:
- [ ] Seatbeltのkeychain-access-*系オペレーション（keychain-access-acl-change, keychain-access-modify-permissions, keychain-access-read-item等）の制御可否が検証されている
- [ ] Keychainデータベースファイル（login.keychain-db）レベルのfile-read/write制限の可否が検証されている
- [ ] 検証結果に基づき、採用方式（アイテム単位制限 or ファイル単位制限 or その他）が決定されている
- [ ] 調査結果がdesign-artifacts/architecture配下に文書化されている
- [ ] Claude CodeのOAuthトークンリフレッシュへの影響が評価されている

**技術的考慮事項**:
- macOS Seatbeltの非公開API領域が含まれるため、実機検証が必須
- `(allow default)`前提のため、deny系ルールの追加可否を確認

---

### ストーリー 2b: Keychainアクセス制限の実装
**優先順位**: Must-have

As a macOSでjailrunを利用する開発者
I want to サンドボックス内のKeychainアクセスが調査結果に基づく最も細かい粒度で制限されている
So that AIエージェントがKeychain内の不要なアイテムにアクセスするリスクが排除される

**受け入れ基準**:
- [ ] ストーリー2aで決定された方式に基づくKeychain制限が実装されている
- [ ] Claude CodeのOAuthトークンリフレッシュが制限後も正常に動作する
- [ ] git credential helper経由のHTTPS認証が制限後も正常に動作する
- [ ] sandbox_profile.batsにKeychain制限のテストが追加されている
- [ ] 制限の技術的背景と選択理由がコード内コメントに記録されている

**技術的考慮事項**:
- ストーリー2aの調査結果に依存するため、実装アプローチは調査完了後に確定

---

### ストーリー 3: ドキュメント更新
**優先順位**: Should-have

As a jailrunの利用者・コントリビューター
I want to deny-readパス一覧とKeychain制限の仕様がドキュメントに反映されている
So that 保護範囲を正確に把握し、必要に応じてカスタマイズできる

**受け入れ基準**:
- [ ] docs/architecture.mdのdeny-readパス一覧が更新されている
- [ ] docs/README.mdの保護対象一覧が更新されている
- [ ] Keychain制限の技術的背景と制約がドキュメントに記載されている
