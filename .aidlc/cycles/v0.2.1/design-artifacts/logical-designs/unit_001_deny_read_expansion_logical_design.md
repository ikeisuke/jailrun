# 論理設計: deny-read パス拡充

## 概要
sandbox.shの`_SANDBOX_DENY_READ_PATHS`に17パスを追加し、macOS/Linux両プラットフォームでクラウドクレデンシャルを保護する。

## アーキテクチャパターン
既存のパスリストパターンを踏襲。sandbox.shが改行区切りのパスリストを定義し、プラットフォーム固有バックエンドがそのリストを消費する構造。

## コンポーネント構成

### 変更対象

```text
lib/
├── sandbox.sh                    # _SANDBOX_DENY_READ_PATHS にパス追加（主変更）
└── platform/
    ├── sandbox-darwin.sh          # 変更不要（既存ループでdeny file-read*生成）
    └── sandbox-linux-systemd.sh   # [ -d ] → [ -e ] 変更（ファイルパス対応）
```

### sandbox.sh 変更箇所

`_SANDBOX_DENY_READ_PATHS` 変数（L15-18）にパスを追加。カテゴリ別にコメントでグループ化:

```text
# 既存（4件）
$HOME/.aws
$HOME/.config/gh
$HOME/.gnupg
$HOME/.ssh

# クラウドサービス（3件）
$HOME/.config/gcloud
$HOME/.azure
$HOME/.oci

# コンテナ・オーケストレーション（2件）
$HOME/.docker
$HOME/.kube

# CDN・エッジ・デプロイ（6件）
$HOME/.wrangler
$HOME/.config/wrangler
$HOME/.fly
$HOME/.config/netlify
$HOME/.config/vercel
$HOME/.config/heroku

# IaC・シークレット管理（3件）
$HOME/.terraform.d
$HOME/.vault-token
$HOME/.config/op

# 開発ツール（3件）
$HOME/.config/hub
$HOME/.config/stripe
$HOME/.config/firebase
```

### プラットフォーム別の消費方法

| プラットフォーム | 消費コンポーネント | 消費方法 | 存在しないパスの扱い |
|----------------|------------------|---------|-------------------|
| macOS | sandbox-darwin.sh L42-47 | `(deny file-read* (subpath "..."))` ルール生成 | Seatbeltは存在しないパスでもエラーにならない |
| Linux | sandbox-linux-systemd.sh L133-137 | `InaccessiblePaths=$path`（`[ -e "$_p" ]`で存在確認、ファイル/ディレクトリ両対応） | 存在しないパスはスキップ（`[ -e ]`ガード） |

## 処理フロー概要

### deny-readパス適用フロー

1. sandbox.sh: `_SANDBOX_DENY_READ_PATHS`にデフォルト21パスを定義
2. sandbox.sh: `SANDBOX_EXTRA_DENY_READ`からユーザー追加パスをappend
3. プラットフォームバックエンドがリストを走査してプロファイル/プロパティに反映

## テスト設計

### sandbox_profile.bats
- 既存テスト: デフォルト4パスの存在確認
- 追加テスト: 新規17パスがSeatbeltプロファイルの`deny file-read*`セクションに含まれることを確認

### sandbox_linux_systemd.bats
- 既存テスト: deny-readパスのInaccessiblePaths反映確認（ディレクトリ）
- 追加テスト:
  - ファイルパス（~/.vault-token相当）がInaccessiblePathsに含まれることを確認
  - 存在しないパスがInaccessiblePathsに含まれないことを確認

## 非機能要件（NFR）への対応

### セキュリティ
- 17パスの追加によりクレデンシャル保護範囲が4→21パスに拡大
- SANDBOX_EXTRA_DENY_READ設定との共存を維持（ユーザーカスタマイズ可能）

### パフォーマンス
- パスリスト走査のO(n)増加は無視できる（n: 4→21）

## 技術選定
- **言語**: POSIX sh（既存コードベースに合わせる）
- **テスト**: bats-core

## 実装上の注意事項
- パスの追加順序は機能に影響しないが、カテゴリ別グループ化で可読性を確保
- `$HOME`プレフィックスはシェル変数展開に依存（ダブルクォート不要、改行区切り文字列のため）
- `~/.vault-token`はファイルであり、macOS Seatbeltの`subpath`はファイルにも動作する。Linux側は`[ -d ]`→`[ -e ]`変更でファイルにも対応する
