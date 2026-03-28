# ドメインモデル: Unit 003 必須テスト追加

## テスト対象ドメイン

### 1. proxy.py ドメイン

#### エンティティ

**IPフィルタリング** (`is_private_ip`)
- 責務: IPアドレスがブロック対象レンジに含まれるか判定
- 入力: 文字列形式のIPアドレス
- 出力: bool（プライベートならTrue）
- ブロック対象: RFC1918, link-local, loopback, ULA(IPv6), metadata

**ドメインマッチング** (`match_domain`)
- 責務: ホスト名が許可リストに合致するか判定
- 入力: host文字列, 許可ドメインset
- 出力: bool
- パターン: 完全一致, ワイルドカード(`*.example.com`)

**クライアントハンドリング** (`handle_client`)
- 責務: 個別クライアント接続のCONNECTプロトコル処理
- 入力: clientソケット, addr, 許可ドメインset
- 出力: HTTP応答コード
- 分岐:
  - 不正リクエスト → 400
  - 非CONNECT → 405
  - ブロックドメイン → 403
  - DNS失敗 → 502
  - プライベートIP解決 → 403
  - 接続成功 → 200 + relay

### 2. sandbox-linux-systemd.sh ドメイン

#### エンティティ

**プロパティ生成** (`_setup_sandbox`)
- 責務: systemd-runプロパティファイルを生成
- 入力: 環境変数（PWD, PROXY_ENABLED, XDG_RUNTIME_DIR, etc.）
- 出力: プロパティファイル（`$_tmpdir/systemd-props`）
- 生成カテゴリ:
  - 特権昇格防止（NoNewPrivileges, CapabilityBoundingSet）
  - デバイス制限（DevicePolicy, DeviceAllow）
  - プロセス/IPC隔離（PrivateUsers, PrivateIPC）
  - ネットワーク制御（RestrictAddressFamilies, IPAddress*）
  - ファイルシステム保護（ProtectSystem, ProtectHome）
  - カーネル保護（ProtectProc, ProtectClock等）
  - Syscallフィルタ（SystemCallFilter）
  - D-Busブロック
  - Git worktree対応
  - カスタムパス（allow-write / deny-read）

## テスト戦略

### proxy.py テスト
- フレームワーク: pytest
- モック: `unittest.mock.patch` で `socket.getaddrinfo` 等をモック
- ソケット: `MagicMock` でクライアント/リモートソケットをシミュレート
- ネットワーク接続: 一切不要

### sandbox-linux-systemd.sh テスト
- フレームワーク: bats
- アプローチ: `_setup_sandbox` 関数を呼び出し、生成されたプロパティファイルの内容をgrep/パターンマッチで検証
- 依存関数のスタブ: `_detect_git_worktree` をスタブ化
- 実systemd-run: 不要（プロパティファイル生成のテストのみ）
- macOS互換: シェル関数の出力テストのため、Linux固有機能に依存しない
