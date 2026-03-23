#!/bin/zsh
# AI エージェント共通クレデンシャル分離ライブラリ
# jailrun エントリポイントから source して使う
#
# 設定ファイル: ~/.config/security-wrapper/config
# deny パス一覧は apps/claude/settings.json の sandbox.filesystem.denyRead と同期すること
#
# 提供する関数:
#   credential_guard_exec <command> [args...] - クレデンシャル分離して exec
#   credential_guard_sandbox_exec <command> [args...] - クレデンシャル分離 + OS sandbox して exec

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/security-wrapper"
CONFIG_FILE="$CONFIG_DIR/config"
_WRAPPER_NAME="${WRAPPER_NAME:-jailrun}"

# 既に sandbox 済みの場合はスキップ（親エージェントから呼ばれた場合）
# env 変数チェック（正常に継承される環境向け）
# + ファイルアクセスチェック（Claude のように env を継承しないツール向け）
if [[ "${_CREDENTIAL_GUARD_SANDBOXED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
if [[ -f "$HOME/.aws/config" ]] && ! test -r "$HOME/.aws/config" 2>/dev/null; then
  echo "[$_WRAPPER_NAME] sandbox 検出（~/.aws/config 読み取り不可）: クレデンシャル分離をスキップ" >&2
  return 0 2>/dev/null || true
fi

# ─── デフォルト値 ───────────────────────────────────────
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_KEYCHAIN_SERVICE="github:classic"
_DEFAULT_REGION="ap-northeast-1"

# バイナリパス（マシンごとに異なる可能性がある）
CLAUDE_BIN=""
CODEX_BIN=""
KIRO_CLI_BIN=""
KIRO_CLI_CHAT_BIN=""
GEMINI_BIN=""

# ─── 設定ファイル読み込み ───────────────────────────────
# 未定義の *_BIN を自動検出して config に追記するヘルパー
_auto_detect_bin() {
  local _var="$1" _cmd="$2"
  if [[ -z "${(P)_var}" ]]; then
    local _orig_path=("${path[@]}")
    path=("${path[@]:#$JAILRUN_DIR}")
    local _found
    _found=$(command -v "$_cmd" 2>/dev/null) || true
    path=("${_orig_path[@]}")
    if [[ -n "$_found" ]]; then
      echo "$_var=\"$_found\"" >> "$CONFIG_FILE"
      eval "$_var=\"$_found\""
      echo "[$_WRAPPER_NAME] 自動検出: $_var=$_found (config に追記)" >&2
    fi
  fi
}

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  # 新しいツールが追加された場合、未定義のパスを自動補完
  _auto_detect_bin CLAUDE_BIN claude
  _auto_detect_bin CODEX_BIN codex
  _auto_detect_bin KIRO_CLI_BIN kiro-cli
  _auto_detect_bin KIRO_CLI_CHAT_BIN kiro-cli-chat
  _auto_detect_bin GEMINI_BIN gemini
else
  echo "[$_WRAPPER_NAME] 設定ファイルがありません: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] 初期設定ファイルを作成します..." >&2
  mkdir -p "$CONFIG_DIR"

  # バイナリパスを自動検出（ラッパー自身を除外するため PATH から JAILRUN_DIR を外して検索）
  # zsh の path 配列からフィルタして検索
  _detect_bin() {
    local _orig_path=("${path[@]}")
    path=("${path[@]:#$JAILRUN_DIR}")
    local _found
    _found=$(command -v "$1" 2>/dev/null) || true
    path=("${_orig_path[@]}")
    echo "${_found:-# not found: $1}"
  }

  cat > "$CONFIG_FILE" <<CONF
# AI エージェント セキュリティラッパー共通設定
# このファイルは git 管理外（マシン固有の設定）
# claude, codex, kiro-cli, gemini で共有される

# 許可する AWS プロファイル（スペース区切り）
# エージェントはここに列挙されたプロファイルのみ使用可能
# AGENT_AWS_PROFILES 環境変数でロードするプロファイルを選択可能（許可リスト内に限る）
ALLOWED_AWS_PROFILES="default"

# デフォルトで使う AWS プロファイル（環境変数 AGENT_AWS_PROFILE で上書き可）
# プロファイルが存在しなければ AWS なしで起動する
DEFAULT_AWS_PROFILE="default"

# Keychain に保存した GitHub PAT のサービス名
# github:fine-grained / github:classic
GH_KEYCHAIN_SERVICE="github:classic"

# 各ツールの実体パス（自動検出済み、必要に応じて修正）
CLAUDE_BIN="$(_detect_bin claude)"
CODEX_BIN="$(_detect_bin codex)"
KIRO_CLI_BIN="$(_detect_bin kiro-cli)"
KIRO_CLI_CHAT_BIN="$(_detect_bin kiro-cli-chat)"
GEMINI_BIN="$(_detect_bin gemini)"
CONF
  unfunction _detect_bin
  echo "[$_WRAPPER_NAME] 作成しました: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] AWS プロファイル設定を確認してください: $CONFIG_FILE" >&2
  exit 1
fi

# 環境変数でのオーバーライド（AGENT_AWS_PROFILE > AWS_PROFILE > config の DEFAULT_AWS_PROFILE）
DEFAULT_AWS_PROFILE="${AGENT_AWS_PROFILE:-${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}}"

# ロードするプロファイル（AGENT_AWS_PROFILES > デフォルトのみ）
# AGENT_AWS_PROFILES が指定されていればそれを、未指定なら DEFAULT_AWS_PROFILE のみロード
# 許可リスト外のプロファイルは拒否する
_LOAD_PROFILES="${AGENT_AWS_PROFILES:-$DEFAULT_AWS_PROFILE}"
if [[ -n "$_LOAD_PROFILES" && -n "$ALLOWED_AWS_PROFILES" ]]; then
  _filtered_profiles=()
  for _p in ${=_LOAD_PROFILES}; do
    if [[ " ${ALLOWED_AWS_PROFILES} " != *" $_p "* ]]; then
      echo "[$_WRAPPER_NAME] WARN: AWS '$_p' は許可リストにありません (ALLOWED_AWS_PROFILES)" >&2
    else
      _filtered_profiles+=("$_p")
    fi
  done
  _LOAD_PROFILES="${_filtered_profiles[*]}"
fi

# ─── 一時ディレクトリ ───────────────────────────────────
_tmpdir=$(mktemp -d)
trap '\rm -rf "$_tmpdir"' EXIT

# ─── AWS クレデンシャル ─────────────────────────────────
# 許可プロファイルの一時 config/credentials を生成
# エージェントは --profile で許可されたプロファイル間を切り替えられる
_aws_config="$_tmpdir/aws-config"
_aws_creds="$_tmpdir/aws-credentials"
touch "$_aws_config" "$_aws_creds"

# プロファイルセクションを一時ファイルに書き出すヘルパー
_write_aws_profile() {
  local _section_config="$1" _section_creds="$2" _ak="$3" _sk="$4" _st="$5" _region="$6"
  echo "[$_section_config]" >> "$_aws_config"
  echo "region = $_region" >> "$_aws_config"
  echo "" >> "$_aws_config"
  echo "[$_section_creds]" >> "$_aws_creds"
  echo "aws_access_key_id = $_ak" >> "$_aws_creds"
  echo "aws_secret_access_key = $_sk" >> "$_aws_creds"
  [[ -n "$_st" ]] && echo "aws_session_token = $_st" >> "$_aws_creds"
  echo "" >> "$_aws_creds"
}

_default_written=false
_default_ak="" _default_sk="" _default_st="" _default_region=""

if command -v aws >/dev/null 2>&1 && [[ -n "$_LOAD_PROFILES" ]]; then
  for _profile in ${=_LOAD_PROFILES}; do
    # 一時クレデンシャルを取得（jq がなければ grep/cut にフォールバック）
    if _exported=$(aws configure export-credentials --profile "$_profile" --format process 2>/dev/null); then
      if command -v jq >/dev/null 2>&1; then
        _ak=$(echo "$_exported" | jq -r .AccessKeyId)
        _sk=$(echo "$_exported" | jq -r .SecretAccessKey)
        _st=$(echo "$_exported" | jq -r '.SessionToken // empty')
      else
        _ak=$(echo "$_exported" | grep -o '"AccessKeyId"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        _sk=$(echo "$_exported" | grep -o '"SecretAccessKey"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        _st=$(echo "$_exported" | grep -o '"SessionToken"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
      fi

      _region=$(aws configure get region --profile "$_profile" 2>/dev/null || echo "$_DEFAULT_REGION")

      # default セクション（DEFAULT_AWS_PROFILE と一致するプロファイルで生成）
      if [[ "$_default_written" == "false" && "$_profile" == "$DEFAULT_AWS_PROFILE" ]]; then
        _write_aws_profile "default" "default" "$_ak" "$_sk" "$_st" "$_region"
        _default_written=true
      fi

      # デフォルトプロファイルのクレデンシャルをキャッシュ（後方の fallback 用）
      if [[ "$_profile" == "$DEFAULT_AWS_PROFILE" ]]; then
        _default_ak="$_ak" _default_sk="$_sk" _default_st="$_st" _default_region="$_region"
      fi

      _write_aws_profile "profile $_profile" "$_profile" "$_ak" "$_sk" "$_st" "$_region"

      echo "[$_WRAPPER_NAME] AWS: $_profile (一時クレデンシャル)" >&2
    else
      echo "[$_WRAPPER_NAME] WARN: AWS '$_profile' のクレデンシャル取得失敗（aws sso login が必要？）" >&2
    fi
  done

  # DEFAULT_AWS_PROFILE がループ内で default セクション未生成の場合、キャッシュから生成
  if [[ "$_default_written" == "false" && -n "$_default_ak" ]]; then
    _write_aws_profile "default" "default" "$_default_ak" "$_default_sk" "${_default_st:-}" "${_default_region:-$_DEFAULT_REGION}"
  fi
fi

# ─── GitHub トークン ────────────────────────────────────
# OS に応じたセキュアストアからトークンを取得
# macOS: Keychain (security コマンド)
# Linux: secret-tool (GNOME Keyring) → 既存の GH_TOKEN/GITHUB_TOKEN にフォールバック
_gh_token=""
_gh_token_source=""
case "$(uname)" in
  Darwin)
    _gh_token=$(security find-generic-password -s "jailrun:$GH_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null) || true
    [[ -n "$_gh_token" ]] && _gh_token_source="Keychain"
    ;;
  Linux)
    if command -v secret-tool >/dev/null 2>&1; then
      _gh_token=$(secret-tool lookup service "jailrun:$GH_KEYCHAIN_SERVICE" account "$USER" 2>/dev/null) || true
      [[ -n "$_gh_token" ]] && _gh_token_source="GNOME Keyring"
    fi
    if [[ -z "$_gh_token" ]] && ! command -v secret-tool >/dev/null 2>&1; then
      echo "[$_WRAPPER_NAME] WARN: secret-tool 未インストール (sudo apt install libsecret-tools gnome-keyring)" >&2
    fi
    ;;
esac

if [[ -n "$_gh_token" ]]; then
  echo "[$_WRAPPER_NAME] GitHub: PAT ($_gh_token_source)" >&2
else
  echo "[$_WRAPPER_NAME] WARN: GitHub PAT 未設定（docs/github-pat-setup.md を参照）" >&2
fi

# ─── OS サンドボックス ───────────────────────────────────
# sandbox 非内蔵ツール用に OS レベルの制限を適用
# macOS: Seatbelt (sandbox-exec)、Linux/WSL2: systemd-run
#
# 読み取り拒否: 機密ディレクトリ
# 書き込み許可: カレントディレクトリ + /tmp + ツール・シェルが使うディレクトリ（ホワイトリスト方式）

_SANDBOX_DENY_READ_PATHS=(
  "$HOME/.aws"
  "$HOME/.config/gh"
  "$HOME/.gnupg"
  "$HOME/.ssh"
)

_SANDBOX_ALLOW_WRITE_PATHS=(
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.kiro"
  "$HOME/.gemini"
  "$HOME/.local/share"
  "$HOME/.local/state"
  "$HOME/.cache"
  "$HOME/.npm"
  "$HOME/.config/claude"
  "$HOME/.config/codex"
  "$HOME/.config/kiro"
)

_SANDBOX_ALLOW_WRITE_FILES=(
  "$HOME/.claude.json"
)

_sandbox_cmd=()

_setup_sandbox() {
  local _cwd="$PWD"

  # git worktree の場合:
  #   - 親リポジトリの toplevel を書き込み許可（git pull 等のため）
  #   - 他のワークツリーは書き込み拒否（分離を維持）
  local _git_common_dir=""
  local _git_parent_toplevel=""
  local _other_worktrees=()
  if command -v git >/dev/null 2>&1; then
    _git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || true
    # 相対パスの場合は絶対パスに変換
    if [[ -n "$_git_common_dir" && "$_git_common_dir" != /* ]]; then
      _git_common_dir="$_cwd/$_git_common_dir"
    fi
    # 通常リポジトリ（$_cwd 配下）なら追加不要
    if [[ -n "$_git_common_dir" && "$_git_common_dir" == "$_cwd"/* ]]; then
      _git_common_dir=""
    elif [[ -n "$_git_common_dir" ]]; then
      # worktree: 親リポジトリの toplevel を取得（.git の親ディレクトリ）
      _git_parent_toplevel="${_git_common_dir%/.git}"
      # 他のワークツリーを列挙（自分自身は除外）
      local _wt_path=""
      while IFS= read -r _line; do
        case "$_line" in
          worktree\ *)
            _wt_path="${_line#worktree }"
            ;;
          "")
            if [[ -n "$_wt_path" && "$_wt_path" != "$_cwd" && "$_wt_path" != "$_git_parent_toplevel" ]]; then
              _other_worktrees+=("$_wt_path")
            fi
            _wt_path=""
            ;;
        esac
      done < <(git worktree list --porcelain 2>/dev/null; echo)
    fi
  fi

  case "$(uname)" in
    Darwin)
      local _sb="$_tmpdir/sandbox.sb"
      {
        echo '(version 1)'
        echo '(allow default)'
        echo ''
        echo ';; 機密ディレクトリの読み取りを拒否'
        echo '(deny file-read*'
        for _p in "${_SANDBOX_DENY_READ_PATHS[@]}"; do
          echo "  (subpath \"$_p\")"
        done
        echo ')'
        echo ''
        # AGENT_SANDBOX_DEBUG=1: 書き込み制限を無効化（find -newer で書き込み先を特定）
        if [[ "${AGENT_SANDBOX_DEBUG:-}" != "1" ]]; then
          echo ';; 書き込みをホワイトリストに制限'
          echo '(deny file-write*'
          echo '  (require-not'
          echo '    (require-any'
          echo "      (subpath \"$_cwd\")"
          # git worktree: 親リポジトリ全体を書き込み許可
          [[ -n "$_git_parent_toplevel" ]] && echo "      (subpath \"$_git_parent_toplevel\")"
          # 通常リポジトリで .git が外にある場合のフォールバック
          [[ -z "$_git_parent_toplevel" && -n "$_git_common_dir" ]] && echo "      (subpath \"$_git_common_dir\")"
          echo '      (subpath "/tmp")'
          echo '      (subpath "/private/tmp")'
          echo '      (subpath "/private/var/folders")'
          echo '      (literal "/dev/null")'
          echo '      (literal "/dev/zero")'
          echo '      (literal "/dev/random")'
          echo '      (literal "/dev/urandom")'
          echo "      (subpath \"$_tmpdir\")"
          for _p in "${_SANDBOX_ALLOW_WRITE_PATHS[@]}"; do
            echo "      (subpath \"$_p\")"
          done
          for _f in "${_SANDBOX_ALLOW_WRITE_FILES[@]}"; do
            echo "      (literal \"$_f\")"
          done
          echo ')))'
          # git worktree: 他のワークツリーへの書き込みを拒否
          # （親リポジトリを許可した上で、他ワークツリーだけピンポイントで deny）
          if [[ ${#_other_worktrees[@]} -gt 0 ]]; then
            echo ''
            echo ';; 他のワークツリーへの書き込みを拒否'
            echo '(deny file-write*'
            for _wt in "${_other_worktrees[@]}"; do
              echo "  (subpath \"$_wt\")"
            done
            echo ')'
          fi
        else
          echo ';; デバッグ: 書き込み制限を無効化（読み取り拒否のみ有効）'
        fi
      } > "$_sb"
      _sandbox_cmd=(sandbox-exec -f "$_sb")
      ;;
    Linux)
      if ! command -v systemd-run >/dev/null 2>&1; then
        echo "[$_WRAPPER_NAME] WARN: systemd-run が利用できません、サンドボックスなしで起動" >&2
        return
      fi
      _sandbox_cmd=(
        systemd-run
        --user --pty --wait --collect --same-dir
        # 環境変数は _env_args の env 経由で渡すため PATH のみ明示
        -E PATH="$PATH"
        # 権限昇格防止
        -p NoNewPrivileges=yes
        -p CapabilityBoundingSet=
        -p AmbientCapabilities=
        -p RestrictSUIDSGID=yes
        -p LockPersonality=yes
        # デバイス制限
        -p PrivateDevices=no
        -p DevicePolicy=closed
        -p "DeviceAllow=/dev/null rw"
        -p "DeviceAllow=/dev/random r"
        -p "DeviceAllow=/dev/urandom r"
        # プロセス・IPC 分離
        -p PrivateUsers=yes
        -p PrivateMounts=yes
        -p PrivateIPC=yes
        -p PrivateTmp=no
        -p "ReadWritePaths=/tmp"
        # ネットワーク（API 通信に必要なため許可、ソケット種別のみ制限）
        -p PrivateNetwork=no
        -p "RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6"
        # ファイルシステム: read-only + ホワイトリスト書き込み
        -p ProtectSystem=strict
        -p ProtectHome=read-only
        -p "ReadWritePaths=$_cwd"
        -p "ReadWritePaths=$_tmpdir"
        # カーネル保護
        -p ProtectProc=invisible
        -p ProtectClock=yes
        -p ProtectHostname=yes
        -p ProtectKernelLogs=yes
        -p ProtectKernelModules=yes
        -p ProtectKernelTunables=yes
        -p ProtectControlGroups=yes
        # syscall フィルタ
        -p SystemCallArchitectures=native
        -p "SystemCallFilter=@system-service"
        -p "SystemCallFilter=~@privileged @debug"
        -p SystemCallErrorNumber=EPERM
        # namespace・リアルタイム制限
        -p RestrictNamespaces=yes
        -p RestrictRealtime=yes
        # その他
        -p UMask=0077
        -p CoredumpFilter=0
        -p KeyringMode=private
      )
      # git worktree: 親リポジトリ全体を書き込み許可、他ワークツリーはアクセス不可
      if [[ -n "$_git_parent_toplevel" ]]; then
        _sandbox_cmd+=(-p "ReadWritePaths=$_git_parent_toplevel")
        for _wt in "${_other_worktrees[@]}"; do
          [[ -d "$_wt" ]] && _sandbox_cmd+=(-p "InaccessiblePaths=$_wt")
        done
      elif [[ -n "$_git_common_dir" ]]; then
        _sandbox_cmd+=(-p "ReadWritePaths=$_git_common_dir")
      fi
      # ホワイトリストのディレクトリを書き込み可能に
      for _p in "${_SANDBOX_ALLOW_WRITE_PATHS[@]}"; do
        mkdir -p "$_p" 2>/dev/null || true
        _sandbox_cmd+=(-p "ReadWritePaths=$_p")
      done
      # 機密ディレクトリをアクセス不可に
      for _p in "${_SANDBOX_DENY_READ_PATHS[@]}"; do
        [[ -d "$_p" ]] && _sandbox_cmd+=(-p "InaccessiblePaths=$_p")
      done
      ;;
  esac
}

# ─── exec ヘルパー ──────────────────────────────────────
# 共通の env 引数を構築（継承された危険な環境変数を明示的にクリア）
_build_env_args() {
  # env コマンドは -u オプションを VAR=val より前に置く必要がある
  # まず -u を全て集め、その後に VAR=val を追加する
  _env_args=(
    env
    # 継承された AWS クレデンシャルをクリア（config/credentials file より優先されるため）
    -u AWS_ACCESS_KEY_ID
    -u AWS_SECRET_ACCESS_KEY
    -u AWS_SESSION_TOKEN
    -u AWS_PROFILE
    -u AWS_DEFAULT_PROFILE
    -u AWS_ROLE_ARN
    -u AWS_ROLE_SESSION_NAME
  )
  # GitHub トークン: セキュアストアのみ（環境変数フォールバックなし）
  # 既存の GH_TOKEN / GITHUB_TOKEN は常にクリア
  _env_args+=(-u GH_TOKEN -u GITHUB_TOKEN)
  # 制限済みクレデンシャルを注入（-u の後に VAR=val）
  _env_args+=(
    AWS_CONFIG_FILE="$_aws_config"
    AWS_SHARED_CREDENTIALS_FILE="$_aws_creds"
    GH_CONFIG_DIR="$_tmpdir/gh"
    SSH_AUTH_SOCK=
  )
  if [[ -n "$_gh_token" ]]; then
    _env_args+=(GH_TOKEN="$_gh_token")
    # SSH は秘密鍵・エージェントともにブロック済みのため HTTPS に統一
    # git の SSH URL を自動で HTTPS に変換し、GH_TOKEN で認証する
    printf '#!/bin/sh\necho "$GH_TOKEN"\n' > "$_tmpdir/git-askpass"
    chmod +x "$_tmpdir/git-askpass"
    _env_args+=(
      GIT_ASKPASS="$_tmpdir/git-askpass"
      GIT_TERMINAL_PROMPT=0
      GIT_CONFIG_COUNT=2
      GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf"
      GIT_CONFIG_VALUE_0="git@github.com:"
      GIT_CONFIG_KEY_1="url.https://github.com/.insteadOf"
      GIT_CONFIG_VALUE_1="ssh://git@github.com/"
    )
  fi
}

# exec 前に一時ファイルの cleanup をスケジュール
# exec はプロセスを置き換えるため trap EXIT は実行されない
# → バックグラウンドプロセスでエージェント終了を待ち、終了後に削除する
_schedule_cleanup() {
  (
    # 親プロセス（exec 後のエージェント）の終了を待つ
    while kill -0 $$ 2>/dev/null; do
      sleep 5
    done
    \rm -rf "$_tmpdir"
  ) &
  disown
}

# クレデンシャル分離のみ（sandbox 内蔵ツール向け: claude）
credential_guard_exec() {
  _build_env_args
  _schedule_cleanup
  exec "${_env_args[@]}" "$@"
}

# クレデンシャル分離 + OS サンドボックス
# 既に sandbox 内（親エージェントから呼ばれた場合）ならネストしない
credential_guard_sandbox_exec() {
  _build_env_args
  if [[ -z "${_CREDENTIAL_GUARD_SANDBOXED:-}" ]]; then
    _setup_sandbox
    # sandbox が実際に適用された場合のみフラグを設定（Linux で systemd-run 未インストール時はスキップ）
    if [[ ${#_sandbox_cmd[@]} -gt 0 ]]; then
      _env_args+=(_CREDENTIAL_GUARD_SANDBOXED=1)
    fi
  fi
  # Linux (systemd-run): env VAR=val は子プロセスに継承されないため -E フラグで渡す
  if [[ ${#_sandbox_cmd[@]} -gt 0 && "${_sandbox_cmd[1]}" == "systemd-run" ]]; then
    local _new_env_args=(env)
    local _arg
    for _arg in "${_env_args[@]}"; do
      case "$_arg" in
        env) ;;  # skip
        -u) _new_env_args+=(-u) ;;
        -u*) _new_env_args+=("$_arg") ;;
        *=*) _sandbox_cmd+=(-E "$_arg") ;;
        *) _new_env_args+=("$_arg") ;;
      esac
    done
    _env_args=("${_new_env_args[@]}")
  fi
  _schedule_cleanup
  [[ "${AGENT_SANDBOX_DEBUG:-}" == "1" ]] && echo "[$_WRAPPER_NAME] exec: ${_sandbox_cmd[*]} $*" >&2
  exec "${_env_args[@]}" "${_sandbox_cmd[@]}" "$@"
}
