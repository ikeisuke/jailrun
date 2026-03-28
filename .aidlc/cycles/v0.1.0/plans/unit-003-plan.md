# Unit 003 計画: 必須テスト追加

## 概要

テストカバレッジの主要ギャップを解消する。proxy.py のユニットテストと sandbox-linux-systemd.sh のプロパティ生成テストを新規作成する。

## 変更対象ファイル

### 新規作成
- `tests/test_proxy.py` — proxy.py のユニットテスト（pytest）
- `tests/sandbox_linux_systemd.bats` — sandbox-linux-systemd.sh のプロパティ生成テスト（bats）

### 変更なし（テスト対象のみ）
- `lib/proxy.py` — コード修正なし
- `lib/platform/sandbox-linux-systemd.sh` — コード修正なし

### 変更（必要に応じて）
- `Makefile` — pytest ターゲット追加の検討

## 実装計画

### Phase 1: 設計

1. **ドメインモデル設計**: proxy.py のテスト対象関数とシナリオ定義、sandbox-linux-systemd.sh のテスト対象関数とシナリオ定義
2. **論理設計**: テストファイル構成、モック戦略、テストヘルパーの設計

### Phase 2: 実装

#### tests/test_proxy.py

テスト対象関数:
- `is_private_ip()` — RFC1918/link-local/loopback/メタデータIP判定
- `match_domain()` — 完全一致・ワイルドカードマッチング
- `handle_client()` — CONNECT プロトコル処理（モックベース）

テストシナリオ:
| 関数 | テストケース |
|------|------------|
| `is_private_ip` | 各ブロックレンジ（10.x, 172.16.x, 192.168.x, 169.254.x, 127.x, ::1, fc00::, fe80::）でTrue |
| `is_private_ip` | パブリックIP（8.8.8.8, 2001:4860::）でFalse |
| `is_private_ip` | 不正な値でFalse |
| `match_domain` | 完全一致 |
| `match_domain` | ワイルドカード一致（*.example.com → sub.example.com） |
| `match_domain` | ワイルドカード不一致（*.example.com → example.com） |
| `match_domain` | 大文字小文字正規化 |
| `handle_client` | 正常CONNECT → 200 |
| `handle_client` | 非CONNECTメソッド → 405 |
| `handle_client` | 不正リクエスト行 → 400 |
| `handle_client` | ブロックドメイン → 403 |
| `handle_client` | DNS解決失敗 → 502 |
| `handle_client` | プライベートIPへの解決 → 403 |

モック戦略:
- `socket.getaddrinfo` をモックして DNS 結果を制御
- クライアント/リモートソケットをモックして実ネットワーク接続を回避

#### tests/sandbox_linux_systemd.bats

テスト対象関数:
- `_setup_sandbox()` — systemd プロパティファイル生成

テストシナリオ:
| シナリオ | 検証内容 |
|---------|---------|
| 基本プロパティ生成 | NoNewPrivileges, CapabilityBoundingSet 等の基本項目 |
| PROXY_ENABLED=true | IPAddressDeny/Allow が出力される |
| PROXY_ENABLED=false/未設定 | IPAddress 制限なし |
| カスタム書き込みパス | _SANDBOX_ALLOW_WRITE_PATHS の反映 |
| カスタム拒否パス | _SANDBOX_DENY_READ_PATHS の反映 |
| Git worktree あり | _git_parent_toplevel の ReadWritePaths |

テスト方式:
- bats + grep/パターンマッチ（実 systemd-run 不要）
- プロパティファイルの出力内容をアサート
- macOS 環境でも実行可能（関数出力のテストのみ）

## 完了条件チェックリスト

- [ ] `tests/test_proxy.py` を新規作成。ドメインフィルタリング、DNSリバインディング検出、エラーハンドリングをテスト
- [ ] `tests/sandbox_linux_systemd.bats` を新規作成。プロパティ生成の正常系・異常系をテスト
- [ ] `make test` が全パスすること（新規テストファイル含む）
