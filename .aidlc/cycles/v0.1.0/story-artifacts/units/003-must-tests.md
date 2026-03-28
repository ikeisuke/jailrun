# Unit: 必須テスト追加

## 概要
テストカバレッジの主要ギャップを解消する。proxy.pyのユニットテストとsandbox-linux-systemd.shのプロパティ生成テストを追加する。

## 含まれるユーザーストーリー
- ストーリー 3: proxy.py のユニットテスト追加
- ストーリー 4: sandbox-linux-systemd.sh のテスト追加

## 責務
- `tests/test_proxy.py`（または同等）を新規作成。ドメインフィルタリング、DNSリバインディング検出、エラーハンドリングをテスト
- `tests/sandbox_linux_systemd.bats` を新規作成。プロパティ生成の正常系・異常系をテスト
- Makefileにテストターゲットを追加（必要に応じて）

## 境界
- proxy.py / sandbox-linux-systemd.sh のコード修正は行わない（テスト追加のみ）
- credential-guard のテストはUnit 007で実施

## 依存関係

### 依存する Unit
- なし

### 外部依存
- pytest（proxy.pyテスト用）
- bats（sandbox-linux-systemd.shテスト用）

## 非機能要件（NFR）
- **パフォーマンス**: テスト実行時間が既存テストスイートの2倍以内
- **セキュリティ**: テストで実際のネットワーク接続やサンドボックス実行を行わない
- **スケーラビリティ**: 該当なし
- **可用性**: 該当なし

## 完了条件
- `make test` が全パスすること（新規テストファイル含む）

## 技術的考慮事項
- proxy.pyテストはpytest + モックベース（socket.getaddrinfoをモック）
- sandbox-linux-systemd.shテストはbats + grep/パターンマッチ（実systemd-run不要）
- macOS環境でもLinuxテストが実行可能なこと（関数出力のテストのみ）

## 実装優先度
High

## 見積もり
中（2テストファイル新規作成、シナリオ表に基づくテストケース実装）

---
## 実装状態

- **状態**: 完了
- **開始日**: 2026-03-28
- **完了日**: 2026-03-28
- **担当**: -
- **エクスプレス適格性**: -
- **適格性理由**: -
