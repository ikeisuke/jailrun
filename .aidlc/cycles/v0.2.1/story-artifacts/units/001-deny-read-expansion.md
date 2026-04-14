# Unit: deny-read パス拡充

## 概要
主要クラウドサービス・開発ツールのクレデンシャルパスをサンドボックスのデフォルトdeny-readに追加する。macOS（Seatbelt）とLinux（systemd InaccessiblePaths）の両方に適用。

## 含まれるユーザーストーリー
- ストーリー 1: クラウドクレデンシャルのdeny-read保護
- ストーリー 3: ドキュメント更新（deny-readパス一覧部分）

## 責務
- sandbox.shの_SANDBOX_DENY_READ_PATHSに17パスを追加
- sandbox-linux-systemd.shのInaccessiblePathsに反映
- sandbox_profile.batsに追加パスの存在確認テスト追加
- sandbox_linux_systemd.batsにInaccessiblePaths反映テスト追加
- docs/architecture.mdとdocs/README.mdのdeny-readパス一覧更新

## 境界
- credential isolation（一時ファイル経由の切り出し）は対象外
- Keychain関連の変更は対象外（Unit 002で対応）
- config.tomlスキーマの変更は対象外（SANDBOX_EXTRA_DENY_READ既存機能で個別追加は可能）

## 依存関係

### 依存する Unit
- なし

### 外部依存
- macOS: sandbox-exec（Seatbelt）
- Linux: systemd-run

## 非機能要件（NFR）
- **パフォーマンス**: deny-readパス追加によるサンドボックス起動時間への影響は無視できる範囲
- **セキュリティ**: 追加パスにより17のクレデンシャルディレクトリがカーネルレベルで保護される
- **後方互換性**: 既存のSANDBOX_EXTRA_DENY_READ設定との共存を維持

## 技術的考慮事項
- deny-readパスは存在しないディレクトリでもSeatbelt/systemd双方でエラーにならない
- Linux systemd-runのInaccessiblePathsは存在しないパスをスキップする動作の確認が必要
- パスの追加順序は機能に影響しないが、カテゴリ別にグループ化して可読性を維持

## 関連Issue
- なし

## 実装優先度
High

## 見積もり
中規模（コード変更: パスリスト追加 + Linux InaccessiblePaths反映、テスト: 2ファイル更新、ドキュメント: 2ファイル更新、検証: 存在しないパスの安全性確認）

---
## 実装状態

- **状態**: 完了
- **開始日**: 2026-04-14
- **完了日**: 2026-04-14
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
