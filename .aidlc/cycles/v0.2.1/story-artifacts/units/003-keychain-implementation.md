# Unit: Keychainアクセスプロファイル設定の実装

## 概要
Unit 002の調査結果に基づき、macOS SeatbeltプロファイルでのKeychainアクセスを `config.toml` の設定値で切り替え可能にする。deny（全拒否）/ read-cache-only（読み取りのみ）/ allow（全許可、デフォルト）の3プロファイルを提供。

## 含まれるユーザーストーリー
- ストーリー 2b: Keychainアクセス制限の実装
- ストーリー 3: ドキュメント更新（Keychain制限部分）

## 責務
- `config.toml` に `keychain_profile` 設定を追加（`deny` | `read-cache-only` | `allow`、デフォルト: `allow`）
- `sandbox.sh` で設定値に応じて `~/Library/Keychains` の書き込み許可を切り替え
  - `allow`: 現状維持（`subpath` で全許可）
  - `deny` / `read-cache-only`: `_SANDBOX_ALLOW_WRITE_PATHS` から `~/Library/Keychains` を除外
- `sandbox_profile.bats` に各プロファイルのテスト追加
- `docs/architecture.md` にKeychain制限の技術的背景と設定方法を記録
- コード内コメントでUnit 002調査レポートへのリンクを記載

## 境界
- 技術調査は対象外（Unit 002で完了済み）
- deny-readパスの追加は対象外（Unit 001で対応済み）
- Linux側のKeychain/Keyring制御は対象外
- SecurityServer mach-lookupの完全ブロックは対象外（TLS証明書検証に必要）
- regexによる書き込みスコープ絞り込み（Unit 002で検証済み）は本Unitでは実装しない（コスト対効果が低いため）

## 依存関係

### 依存する Unit
- Unit 002: Seatbelt Keychain制御可否の調査（調査結果: `.aidlc/cycles/v0.2.1/design-artifacts/keychain-investigation-report.md`）

### 統合検証
- Unit 001との併用確認を推奨（deny-readとKeychain制限の併存動作確認）

### 外部依存
- macOS: sandbox-exec（Seatbelt）

## 非機能要件（NFR）
- **パフォーマンス**: 設定値の読み取りのみ。サンドボックス起動時間への影響なし
- **セキュリティ**: ユーザーが明示的に `deny` を選択すればKeychain書き込みを完全ブロック可能
- **後方互換性**: デフォルト `allow` で既存動作を維持

## 技術的考慮事項
- `deny` と `read-cache-only` は実装上同じ（file-write除外のみ）。file-readはSecurityServer経由のため影響なし（Unit 002 KC-02-S1/S3で確認済み）
- `deny` 設定時、サンドボックス外で先に認証（`claude auth login` 等）しておけばキャッシュ済みトークンで動作する可能性あり（ユーザー責任）
- 調査レポート: `.aidlc/cycles/v0.2.1/design-artifacts/keychain-investigation-report.md`

## 関連Issue
- #21（Add sandbox Keychain access profiles for Claude Code on macOS）

## 実装優先度
High

## 見積もり
小規模（config読み取り + 条件分岐 + テスト + ドキュメント）

---
## 実装状態

- **状態**: 未着手
- **開始日**: -
- **完了日**: -
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
