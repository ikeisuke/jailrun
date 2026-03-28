# 論理設計: Unit 003 必須テスト追加

## コンポーネント構成

### 1. tests/test_proxy.py

```
tests/test_proxy.py
├── TestIsPrivateIp          # is_private_ip() のテストクラス
│   ├── test_rfc1918_ranges  # 10.x, 172.16.x, 192.168.x
│   ├── test_loopback        # 127.x
│   ├── test_link_local      # 169.254.x
│   ├── test_ipv6_private    # ::1, fc00::, fe80::
│   ├── test_public_ip       # パブリックIPはFalse
│   └── test_invalid_input   # 不正値はFalse
├── TestMatchDomain          # match_domain() のテストクラス
│   ├── test_exact_match     # 完全一致
│   ├── test_wildcard_match  # *.example.com → sub.example.com
│   ├── test_wildcard_no_match_base  # *.example.com ≠ example.com
│   ├── test_case_insensitive # 大文字小文字
│   └── test_no_match        # 不一致
└── TestHandleClient         # handle_client() のテストクラス
    ├── test_valid_connect    # 正常CONNECT → 200
    ├── test_non_connect_method # GET等 → 405
    ├── test_malformed_request # 不正行 → 400
    ├── test_blocked_domain   # 許可外 → 403
    ├── test_dns_failure      # gaierror → 502
    └── test_private_ip_resolution # プライベートIP解決 → 403
```

#### モック設計

**handle_client テスト用のソケットモック**:
- `client_socket`: `MagicMock(spec=socket.socket)`
  - `recv()` でCONNECTリクエストを返すよう設定
  - `sendall()` で送信データをキャプチャ
- `socket.getaddrinfo`: `patch` でDNS結果を制御
- `socket.socket` (リモート接続用): `patch` で接続をモック

### 2. tests/sandbox_linux_systemd.bats

```
tests/sandbox_linux_systemd.bats
├── setup()                  # 一時ディレクトリ作成、スタブ設定
├── teardown()               # クリーンアップ
├── test: 基本プロパティ      # NoNewPrivileges, CapabilityBoundingSet等
├── test: PROXY_ENABLED=true # IPAddressDeny/Allow出力
├── test: PROXY_ENABLED=false # IPAddress制限なし
├── test: カスタム書込パス    # _SANDBOX_ALLOW_WRITE_PATHS
├── test: カスタム拒否パス    # _SANDBOX_DENY_READ_PATHS
└── test: Git worktree       # _git_parent_toplevel
```

#### スタブ設計

```bash
# _detect_git_worktree のスタブ（何もしない）
_detect_git_worktree() { :; }
```

テストはプロパティファイル（`$_tmpdir/systemd-props`）の内容をgrepで検証する。

## Makefile変更

現在の `make test` は `bats tests/` を実行しており、新規 `.bats` ファイルは自動で拾われる。
pytestは `make test` に追加するか、別ターゲット（`make test-py`）にするか検討。

**方針**: `make test` に pytest を追加し、一括実行可能にする。

```makefile
test:
	bats tests/
	python3 -m pytest tests/ -v
```

## 依存パッケージ

- pytest: `pip install pytest` (テスト実行)
- bats: 既存インストール済み（既存テストで使用中）
