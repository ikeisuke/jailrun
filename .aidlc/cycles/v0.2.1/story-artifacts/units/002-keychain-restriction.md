# Unit: Seatbelt Keychain制御可否の調査

## 概要
macOS Seatbeltで実現可能なKeychainアクセス制限の技術的限界を調査・検証し、採用方式を決定する。技術スパイクとして位置付け、実装はUnit 003で行う。

## 含まれるユーザーストーリー
- ストーリー 2a: Seatbelt Keychain制御可否の調査

## 責務
- Seatbeltのkeychain-access-*系オペレーションの調査・実機検証
- Keychainデータベースファイルレベルのfile-read/write制限の検証
- ~/Library/Keychains書き込みのliteral/regex制限の検証
- Claude CodeのOAuthトークンリフレッシュへの影響評価
- 調査結果の文書化と採用方式の決定

## 境界
- 決定した方式の本実装は対象外（Unit 003で実施）
- deny-readパスの追加は対象外（Unit 001で対応）
- Linux側のKeychain/Keyring制御は対象外

## 依存関係

### 依存する Unit
- なし

### 外部依存
- macOS: sandbox-exec（Seatbelt）実機環境
- Claude Code: トークンリフレッシュ動作の検証に必要

## 非機能要件（NFR）
- **セキュリティ**: 調査結果に基づき、最も効果的な制限方式を選定

## 技術的考慮事項
- Seatbeltの`(allow default)`前提のため、deny系ルールの追加で制限を検証
- 調査対象:
  1. `keychain-access-acl-change`, `keychain-access-modify-permissions`等の制御可否
  2. `keychain-access-modify-item`, `keychain-access-read-item`等のフィルタリング可否
  3. Keychainデータベースファイル（`login.keychain-db`）レベルのfile-read/write制御
  4. SecurityServer mach-lookupの部分制限可否
- macOS Seatbeltの非公開API領域が含まれるため、ドキュメントだけでなく実機検証が必須

## 関連Issue
- #21（Add sandbox Keychain access profiles for Claude Code on macOS）

## 実装優先度
High

## 見積もり
小〜中規模（調査・検証・文書化。実装は含まない）

---
## 実装状態

- **状態**: 完了
- **開始日**: 2026-04-14
- **完了日**: 2026-04-14
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
