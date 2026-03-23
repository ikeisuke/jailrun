#!/bin/zsh
# AI エージェント共通ラッパー
# jailrun エントリポイントから source して使う
# WRAPPER_NAME, JAILRUN_DIR, JAILRUN_LIB は呼び出し元で設定すること
#
# 設定: ~/.config/security-wrapper/config
# プロファイル指定: AGENT_AWS_PROFILE=dev jailrun <tool>

set -euo pipefail

# WRAPPER_NAME は呼び出し元で設定すること
if [[ -z "${WRAPPER_NAME:-}" ]]; then
  echo "[jailrun] ERROR: WRAPPER_NAME が未設定です" >&2
  exit 1
fi
source "$JAILRUN_LIB/credential-guard.sh"

# sandbox 検出ヘルパー（env 変数 or ファイルアクセス）
_is_sandboxed() {
  [[ "${_CREDENTIAL_GUARD_SANDBOXED:-}" == "1" ]] && return 0
  [[ -f "$HOME/.aws/config" ]] && ! test -r "$HOME/.aws/config" 2>/dev/null && return 0
  return 1
}

# Codex の内蔵 sandbox を無効化（jailrun の Seatbelt/systemd-run に統一するため）
# 結果は _codex_args 配列にセットされる
_rewrite_codex_args() {
  _codex_args=()
  local _sandbox_inserted=false
  local _skip_next=false
  for _arg in "$@"; do
    if [[ "$_skip_next" == true ]]; then
      _skip_next=false
      continue
    fi
    # 既存の -s/--sandbox を除去
    case "$_arg" in
      -s|--sandbox) echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2; _skip_next=true; continue ;;
      --sandbox=*) echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2; continue ;;
    esac
    _codex_args+=("$_arg")
    if [[ "$_sandbox_inserted" == false ]]; then
      case "$_arg" in
        exec|e)
          _codex_args+=(-s danger-full-access)
          _sandbox_inserted=true
          ;;
        review)
          _codex_args+=(-c 'sandbox_mode="danger-full-access"')
          _sandbox_inserted=true
          ;;
      esac
    fi
  done
}

# sandbox 済み → 実体を直接 exec（クレデンシャル分離済みのため再処理不要）
if _is_sandboxed; then
  # JAILRUN_DIR を除外した PATH で実体を探して exec
  _orig_path=("${path[@]}")
  path=("${path[@]:#$JAILRUN_DIR}")
  REAL_BIN="$(command -v "$WRAPPER_NAME" 2>/dev/null)" || true
  path=("${_orig_path[@]}")
  if [[ -z "$REAL_BIN" ]]; then
    echo "[$WRAPPER_NAME] ERROR: 実体が見つかりません" >&2
    exit 1
  fi
  case "$WRAPPER_NAME" in
    codex)
      _rewrite_codex_args "$@"
      [[ "${AGENT_SANDBOX_DEBUG:-}" == "1" ]] && echo "[$WRAPPER_NAME] exec: $REAL_BIN ${_codex_args[*]}" >&2
      exec "$REAL_BIN" "${_codex_args[@]}"
      ;;
  esac
  [[ "${AGENT_SANDBOX_DEBUG:-}" == "1" ]] && echo "[$WRAPPER_NAME] exec: $REAL_BIN $*" >&2
  exec "$REAL_BIN" "$@"
fi

# BIN 変数名を導出: kiro-cli → KIRO_CLI_BIN
_bin_var="${${WRAPPER_NAME:u}//-/_}_BIN"
REAL_BIN="${(P)_bin_var}"
if [[ -z "$REAL_BIN" ]]; then
  echo "[$WRAPPER_NAME] ERROR: ${_bin_var} が設定されていません ($CONFIG_FILE)" >&2
  exit 1
fi

# Codex: 内蔵 sandbox を無効化してから credential_guard_sandbox_exec に渡す
case "$WRAPPER_NAME" in
  codex)
    _rewrite_codex_args "$@"
    credential_guard_sandbox_exec "$REAL_BIN" "${_codex_args[@]}"
    ;;
  *)
    credential_guard_sandbox_exec "$REAL_BIN" "$@"
    ;;
esac
