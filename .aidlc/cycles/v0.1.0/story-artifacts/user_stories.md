# ユーザーストーリー

## Epic 1: コード品質改善

### ストーリー 1: config.py の責務分割
**優先順位**: Must-have

As a コントリビューター
I want to config.py が TOML解析・CLI・マイグレーションの3つの責務に分割されている
So that 各ファイルの責務が明確になり、変更時の影響範囲を限定できる

**受け入れ基準**:
- [ ] `lib/config.py` が TOML解析・設定値の読み書きのみを担当する
- [ ] `lib/config_cli.py` が show/set/edit/init/path 等のCLIコマンド処理を担当する
- [ ] `lib/config_migrate.py` がレガシーシェル設定からTOMLへのマイグレーションを担当する
- [ ] `lib/config.sh` が分割後のファイルを正しく呼び出し、既存の設定読み込み動作が変わらない
- [ ] `lib/config-cmd.sh` が分割後のファイルを正しく呼び出す
- [ ] 既存の `tests/config.bats` と `tests/config_cmd.bats` が全テストパスする
- [ ] `~/.config/jailrun/config.toml` の読み書きが分割前と同一の結果を返す

**技術的考慮事項**:
- Python 3 の tomllib（読み取り専用）を使用しているため、書き込み側の実装を確認する必要がある
- `config.sh` からの呼び出しインターフェースを維持すること

---

### ストーリー 2: リポジトリ衛生整備
**優先順位**: Must-have

As a コントリビューター
I want to .gitignore が整備され、不要ファイルがリポジトリに含まれない
So that クリーンなリポジトリ状態を維持できる

**受け入れ基準**:
- [ ] `.gitignore` に `__pycache__/` と `*.pyc` のエントリが含まれる
- [ ] `lib/__pycache__/` がリポジトリから削除されている（git rm --cached）
- [ ] `git status` で `.pyc` ファイルが追跡対象に含まれない

---

## Epic 2: テスト追加

### ストーリー 3: proxy.py のユニットテスト追加
**優先順位**: Must-have

As a コントリビューター
I want to proxy.py のドメインフィルタリングとDNSリバインディング検出のテストが存在する
So that プロキシのセキュリティ機能がリグレッションなく維持されることを検証できる

**受け入れ基準**:
- [ ] `tests/` 配下に proxy.py 用のテストファイルが存在する
- [ ] 許可ドメインへの接続が成功するケースがテストされている
- [ ] 非許可ドメインへの接続が拒否されるケースがテストされている
- [ ] プライベートIPアドレス（10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16等）へのDNSリバインディングが検出・拒否されるケースがテストされている
- [ ] `make test` で新規テストがパスする

**技術的考慮事項**:
- proxy.py はPython 3で記述されているため、pytest または unittest でテストを実装する
- 実際のネットワーク接続を伴わないモックベースのテストが望ましい

---

### ストーリー 4: sandbox-linux-systemd.sh のテスト追加
**優先順位**: Must-have

As a コントリビューター
I want to sandbox-linux-systemd.sh のプロパティ生成ロジックのテストが存在する
So that Linuxサンドボックスの設定変更時にリグレッションを検出できる

**受け入れ基準**:
- [ ] `tests/` 配下に sandbox-linux-systemd.sh 用のテストファイルが存在する
- [ ] 生成されるsystemd-runプロパティに必須項目（NoNewPrivileges, ProtectSystem等）が含まれることがテストされている
- [ ] プロキシ有効時のネットワーク制限プロパティ（IPAddressDeny等）が含まれることがテストされている
- [ ] `make test` で新規テストがパスする

**技術的考慮事項**:
- bats フレームワークで実装し、既存テストとの一貫性を保つ
- 実際の systemd-run 実行は不要。プロパティ生成関数の出力をテストする

---

### ストーリー 5: credential-guard 統合テスト追加
**優先順位**: Should-have

As a コントリビューター
I want to credential-guard.sh の統合テストが存在する
So that 認証情報ガードの動作をテストで確認できる

**受け入れ基準**:
- [ ] `tests/` 配下に credential-guard.sh 用のテストファイルが存在する
- [ ] 二重サンドボックス防止（_CREDENTIAL_GUARD_SANDBOXED チェック）がテストされている
- [ ] エラー条件（設定ファイル不正、バイナリ不在等）のテストが含まれる
- [ ] `make test` で新規テストがパスする

---

## Epic 3: ドキュメント整備

### ストーリー 6: README.md 再構成
**優先順位**: Must-have

As a エンドユーザー
I want to README.md を読んでインストールから基本利用まで迷わず辿れる
So that jailrun を短時間で導入・利用開始できる

**受け入れ基準**:
- [ ] README.md に「インストール手順」セクションが存在し、macOS/Linuxそれぞれの手順が記載されている
- [ ] README.md に「クイックスタート」セクションが存在し、最初の実行例が記載されている
- [ ] README.md に「設定リファレンス」セクションが存在し、config.toml の全設定項目が一覧化されている
- [ ] README.md に「トラブルシューティング」セクションが存在し、よくある問題と解決策が記載されている
- [ ] docs/README.md との内容重複が解消されている（一方に集約または相互参照）

**技術的考慮事項**:
- 既存の README.md（47行）と docs/README.md（354行）の内容を精査し、統合方針を決定する

---

### ストーリー 7: 開発者向けドキュメント作成
**優先順位**: Should-have

As a コントリビューター
I want to アーキテクチャ概要とコントリビューションガイドが存在する
So that プロジェクトの構造を理解し、効率的に開発に参加できる

**受け入れ基準**:
- [ ] `docs/architecture.md` が存在し、5層レイヤードアーキテクチャの説明が記載されている
- [ ] `docs/architecture.md` にデータフロー（認証情報の流れ、サンドボックス構築の流れ）が記載されている
- [ ] `docs/contributing.md` が存在し、開発環境セットアップ手順が記載されている
- [ ] `docs/contributing.md` にテスト実行方法（`make test`）が記載されている
- [ ] `docs/contributing.md` にコーディング規約（POSIX sh準拠、命名規則等）が記載されている

---

## Epic 4: 追加リファクタリング

### ストーリー 8: sandbox.sh の関心分離
**優先順位**: Should-have

As a コントリビューター
I want to sandbox.sh の責務が明確に分離されている
So that サンドボックス関連の変更時に影響範囲を限定できる

**受け入れ基準**:
- [ ] プラットフォーム共通ロジック、env-spec生成、プロキシ管理が論理的に分離されている
- [ ] 既存の `tests/sandbox_profile.bats` と `tests/passthrough_env.bats` が全テストパスする
- [ ] sandbox.sh を source している他のファイル（credential-guard.sh等）の動作が変わらない

---

### ストーリー 9: token.sh のCLI/ロジック分離
**優先順位**: Should-have

As a コントリビューター
I want to token.sh のCLI解析部分とキーチェーン操作ロジックが分離されている
So that トークン管理ロジックの変更がCLI部分に影響しない

**受け入れ基準**:
- [ ] CLI解析（引数パース、ヘルプ表示）とキーチェーン操作ロジックが論理的に分離されている
- [ ] 既存の `tests/jailrun.bats`（token --help テスト）がパスする
- [ ] `jailrun token add/rotate/delete/list` の動作が変わらない
