#!/bin/zsh
# AI エージェント共通クレデンシャル分離ライブラリ
# jailrun エントリポイントから source して使う
#
# 設定ファイル: ~/.config/jailrun/config
#
# 提供する関数:
#   credential_guard_sandbox_exec <command> [args...] - クレデンシャル分離 + OS sandbox して exec

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/jailrun"
CONFIG_FILE="$CONFIG_DIR/config"
_WRAPPER_NAME="${WRAPPER_NAME:-jailrun}"

# 旧ディレクトリからのマイグレーション
_OLD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/security-wrapper"
if [[ ! -f "$CONFIG_FILE" && -f "$_OLD_CONFIG_DIR/config" ]]; then
  mkdir -p "$CONFIG_DIR"
  cp "$_OLD_CONFIG_DIR/config" "$CONFIG_FILE"
  echo "[$_WRAPPER_NAME] config を移行しました: $_OLD_CONFIG_DIR → $CONFIG_DIR" >&2
fi

# ─── sandbox 検出・早期リターン ──────────────────────────
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

CLAUDE_BIN=""
CODEX_BIN=""
KIRO_CLI_BIN=""
KIRO_CLI_CHAT_BIN=""
GEMINI_BIN=""

# sandbox パス（config で追加可能）
SANDBOX_EXTRA_DENY_READ=""
SANDBOX_EXTRA_ALLOW_WRITE=""
SANDBOX_EXTRA_ALLOW_WRITE_FILES=""

# ─── 設定ファイル読み込み ───────────────────────────────
_auto_detect_bin() {
  local _var="$1" _cmd="$2"
  if [[ -z "${(P)_var}" ]]; then
    local _found
    _found=$(command -v "$_cmd" 2>/dev/null) || true
    if [[ -n "$_found" ]]; then
      echo "$_var=\"$_found\"" >> "$CONFIG_FILE"
      eval "$_var=\"$_found\""
      echo "[$_WRAPPER_NAME] 自動検出: $_var=$_found (config に追記)" >&2
    fi
  fi
}

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  _auto_detect_bin CLAUDE_BIN claude
  _auto_detect_bin CODEX_BIN codex
  _auto_detect_bin KIRO_CLI_BIN kiro-cli
  _auto_detect_bin KIRO_CLI_CHAT_BIN kiro-cli-chat
  _auto_detect_bin GEMINI_BIN gemini
else
  echo "[$_WRAPPER_NAME] 設定ファイルがありません: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] 初期設定ファイルを作成します..." >&2
  mkdir -p "$CONFIG_DIR"

  _detect_bin() {
    local _found
    _found=$(command -v "$1" 2>/dev/null) || true
    echo "${_found:-# not found: $1}"
  }

  cat > "$CONFIG_FILE" <<CONF
# jailrun 設定ファイル（マシン固有、git 管理外）

# ─── AWS ───────────────────────────────────────────────
# 許可する AWS プロファイル（スペース区切り）
ALLOWED_AWS_PROFILES="default"

# デフォルトで使う AWS プロファイル
DEFAULT_AWS_PROFILE="default"

# ─── GitHub ────────────────────────────────────────────
# jailrun token で登録したトークン名
# github:fine-grained-myorg / github:classic
GH_KEYCHAIN_SERVICE="github:classic"

# ─── バイナリパス ──────────────────────────────────────
# 自動検出済み。必要に応じて修正
CLAUDE_BIN="$(_detect_bin claude)"
CODEX_BIN="$(_detect_bin codex)"
KIRO_CLI_BIN="$(_detect_bin kiro-cli)"
KIRO_CLI_CHAT_BIN="$(_detect_bin kiro-cli-chat)"
GEMINI_BIN="$(_detect_bin gemini)"

# ─── sandbox カスタマイズ ──────────────────────────────
# 読み取り拒否パスを追加（スペース区切り）
# デフォルト: ~/.aws ~/.ssh ~/.gnupg ~/.config/gh
#SANDBOX_EXTRA_DENY_READ=""

# 書き込み許可パスを追加（スペース区切り）
# デフォルト: ~/.claude ~/.codex ~/.kiro ~/.gemini ~/.cache 等
#SANDBOX_EXTRA_ALLOW_WRITE=""

# 書き込み許可ファイルを追加（スペース区切り）
#SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
CONF
  unfunction _detect_bin
  echo "[$_WRAPPER_NAME] 作成しました: $CONFIG_FILE" >&2
  echo "[$_WRAPPER_NAME] 設定を確認してください: $CONFIG_FILE" >&2
  exit 1
fi

DEFAULT_AWS_PROFILE="${AGENT_AWS_PROFILE:-${AWS_PROFILE:-$DEFAULT_AWS_PROFILE}}"

# ─── 一時ディレクトリ ───────────────────────────────────
_tmpdir=$(mktemp -d)
trap '\rm -rf "$_tmpdir"' EXIT

# ─── AWS クレデンシャル ─────────────────────────────────
source "$JAILRUN_LIB/aws.sh"
_setup_aws_credentials || true

# ─── GitHub トークン ────────────────────────────────────
case "$(uname)" in
  Darwin) source "$JAILRUN_LIB/platform/keychain-darwin.sh" ;;
  Linux)  source "$JAILRUN_LIB/platform/keychain-linux.sh" ;;
esac
_get_gh_token

if [[ -n "$_gh_token" ]]; then
  echo "[$_WRAPPER_NAME] GitHub: PAT ($_gh_token_source)" >&2
else
  echo "[$_WRAPPER_NAME] WARN: GitHub PAT 未設定（docs/github-pat-setup.md を参照）" >&2
fi

# ─── サンドボックス設定 ─────────────────────────────────
_SANDBOX_DENY_READ_PATHS=(
  "$HOME/.aws"
  "$HOME/.config/gh"
  "$HOME/.gnupg"
  "$HOME/.ssh"
)
# config から追加
for _p in ${=SANDBOX_EXTRA_DENY_READ}; do
  _SANDBOX_DENY_READ_PATHS+=("${_p/#\~/$HOME}")
done

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
for _p in ${=SANDBOX_EXTRA_ALLOW_WRITE}; do
  _SANDBOX_ALLOW_WRITE_PATHS+=("${_p/#\~/$HOME}")
done

_SANDBOX_ALLOW_WRITE_FILES=(
  "$HOME/.claude.json"
)
for _p in ${=SANDBOX_EXTRA_ALLOW_WRITE_FILES}; do
  _SANDBOX_ALLOW_WRITE_FILES+=("${_p/#\~/$HOME}")
done

_sandbox_cmd=()

case "$(uname)" in
  Darwin) source "$JAILRUN_LIB/platform/sandbox-darwin.sh" ;;
  Linux)  source "$JAILRUN_LIB/platform/sandbox-linux.sh" ;;
esac

# ─── exec ヘルパー ──────────────────────────────────────
_build_env_args() {
  _env_args=(
    env
    -u AWS_ACCESS_KEY_ID
    -u AWS_SECRET_ACCESS_KEY
    -u AWS_SESSION_TOKEN
    -u AWS_PROFILE
    -u AWS_DEFAULT_PROFILE
    -u AWS_ROLE_ARN
    -u AWS_ROLE_SESSION_NAME
    -u GH_TOKEN
    -u GITHUB_TOKEN
    AWS_CONFIG_FILE="$_aws_config"
    AWS_SHARED_CREDENTIALS_FILE="$_aws_creds"
    GH_CONFIG_DIR="$_tmpdir/gh"
    SSH_AUTH_SOCK=
    PATH="$JAILRUN_LIB/shims:$PATH"
  )
  if [[ -n "$_gh_token" ]]; then
    _env_args+=(GH_TOKEN="$_gh_token")
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

_schedule_cleanup() {
  (
    while kill -0 $$ 2>/dev/null; do
      sleep 5
    done
    \rm -rf "$_tmpdir"
  ) &
  disown
}

credential_guard_sandbox_exec() {
  _build_env_args
  if [[ -z "${_CREDENTIAL_GUARD_SANDBOXED:-}" ]]; then
    _setup_sandbox
    if [[ ${#_sandbox_cmd[@]} -gt 0 ]]; then
      _env_args+=(_CREDENTIAL_GUARD_SANDBOXED=1)
    fi
  fi
  # Linux (systemd-run): env VAR=val を -E フラグで渡す
  if [[ ${#_sandbox_cmd[@]} -gt 0 && "${_sandbox_cmd[1]}" == "systemd-run" ]]; then
    local _new_env_args=(env)
    local _arg
    for _arg in "${_env_args[@]}"; do
      case "$_arg" in
        env) ;;
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
