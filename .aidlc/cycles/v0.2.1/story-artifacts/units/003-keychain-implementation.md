# Unit: Keychainアクセス制限の実装

## 概要
Unit 002の調査結果に基づき、macOS Seatbeltプロファイルで最も効果的な粒度でKeychainアクセスを制限する。

## 含まれるユーザーストーリー
- ストーリー 2b: Keychainアクセス制限の実装
- ストーリー 3: ドキュメント更新（Keychain制限部分）

## 責務
- sandbox-darwin.shのプロファイル生成ロジック修正（調査結果に基づく方式）
- ~/Library/Keychains書き込み権限の絞り込み
- sandbox_profile.batsにKeychain制限テスト追加
- Keychain制限の技術的背景のドキュメント記録（docs/architecture.md）
- コード内コメントで制限の選択理由を記録

## 境界
- 技術調査は対象外（Unit 002で完了済みが前提）
- deny-readパスの追加は対象外（Unit 001で対応）
- Linux側のKeychain/Keyring制御は対象外
- SecurityServer mach-lookupの完全ブロックは対象外（TLS証明書検証に必要）

## 依存関係

### 依存する Unit
- Unit 002: Seatbelt Keychain制御可否の調査（依存理由: 調査結果に基づき実装方式が決定されるため）

### 統合検証
- Unit 001との併用確認を推奨（deny-readとKeychain制限の併存動作確認）

### 外部依存
- macOS: sandbox-exec（Seatbelt）
- Claude Code: OAuthトークンリフレッシュ動作の確認に必要

## 非機能要件（NFR）
- **パフォーマンス**: Seatbeltプロファイルの複雑化による起動時間への影響は無視できる範囲
- **セキュリティ**: Keychainアクセスが制限され、AIエージェントが不要なキーチェーンアイテムにアクセスするリスクが低減
- **後方互換性**: Claude CodeのOAuthトークンリフレッシュとgit credential helper動作を維持

## 技術的考慮事項
- 実装アプローチはUnit 002の調査結果に依存（設計フェーズで確定）
- テストはSeatbeltプロファイルの生成内容の検証（sandbox_profile.bats）

## 関連Issue
- #21（Add sandbox Keychain access profiles for Claude Code on macOS）

## 実装優先度
High

## 見積もり
中規模（実装 + テスト + ドキュメント更新）

---
## 実装状態

- **状態**: 未着手
- **開始日**: -
- **完了日**: -
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
