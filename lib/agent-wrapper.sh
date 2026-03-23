#!/bin/sh
# AI エージェント共通ラッパー
# jailrun エントリポイントから source して使う
# WRAPPER_NAME, JAILRUN_DIR, JAILRUN_LIB は呼び出し元で設定すること
#
# 設定: ~/.config/jailrun/config
# プロファイル指定: AGENT_AWS_PROFILE=dev jailrun <tool>

set -eu

# WRAPPER_NAME は呼び出し元で設定すること
if [ -z "${WRAPPER_NAME:-}" ]; then
  echo "[jailrun] ERROR: WRAPPER_NAME が未設定です" >&2
  exit 1
fi
. "$JAILRUN_LIB/credential-guard.sh"

# PATH から jailrun shims を除外してバイナリ実体を探す
_resolve_real_bin() {
  _clean_path=""
  _OLD_IFS="$IFS"; IFS=":"
  for _d in $PATH; do
    case "$_d" in
      */jailrun/shims) ;;
      *) _clean_path="${_clean_path:+$_clean_path:}$_d" ;;
    esac
  done
  IFS="$_OLD_IFS"
  REAL_BIN=$(PATH="$_clean_path" command -v "$WRAPPER_NAME" 2>/dev/null) || true
  if [ -z "$REAL_BIN" ]; then
    echo "[$WRAPPER_NAME] ERROR: 実体が見つかりません" >&2
    exit 1
  fi
}

# sandbox 検出ヘルパー（env 変数 or ファイルアクセス）
_is_sandboxed() {
  [ "${_CREDENTIAL_GUARD_SANDBOXED:-}" = "1" ] && return 0
  [ -f "$HOME/.aws/config" ] && ! test -r "$HOME/.aws/config" 2>/dev/null && return 0
  return 1
}

# Codex の内蔵 sandbox を無効化してから exec
# jailrun の Seatbelt/systemd-run に統一するため
_exec_codex() {
  _resolve_real_bin
  _sandbox_inserted=false
  _skip_next=false
  # positional parameters を引数リストとして組み立て直す
  set -- "$@" "__SENTINEL__"
  _result=""
  for _arg do
    [ "$_arg" = "__SENTINEL__" ] && break
    if [ "$_skip_next" = true ]; then
      _skip_next=false
      continue
    fi
    case "$_arg" in
      -s|--sandbox)
        echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2
        _skip_next=true; continue ;;
      --sandbox=*)
        echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2
        continue ;;
    esac
    _result="${_result:+$_result
}${_arg}"
    if [ "$_sandbox_inserted" = false ]; then
      case "$_arg" in
        exec|e)
          _result="${_result}
-s
danger-full-access"
          _sandbox_inserted=true ;;
        review)
          _result="${_result}
-c
sandbox_mode=\"danger-full-access\""
          _sandbox_inserted=true ;;
      esac
    fi
  done
  # _result を改行区切りから positional parameters に復元
  set --
  _OLD_IFS="$IFS"; IFS="
"
  for _line in $_result; do
    set -- "$@" "$_line"
  done
  IFS="$_OLD_IFS"
  [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$WRAPPER_NAME] exec: $REAL_BIN $*" >&2
  exec "$REAL_BIN" "$@"
}

# sandbox 済み → 実体を直接 exec（クレデンシャル分離済みのため再処理不要）
if _is_sandboxed; then
  case "$WRAPPER_NAME" in
    codex) _exec_codex "$@" ;;
    *)
      _resolve_real_bin
      [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$WRAPPER_NAME] exec: $REAL_BIN $*" >&2
      exec "$REAL_BIN" "$@"
      ;;
  esac
fi

# 通常起動: バイナリ解決 → credential 分離 + sandbox で exec
_resolve_real_bin

case "$WRAPPER_NAME" in
  codex)
    # 引数を書き換えてから credential_guard_sandbox_exec に渡す
    _sandbox_inserted=false
    _skip_next=false
    _new_args=""
    for _arg in "$@"; do
      if [ "$_skip_next" = true ]; then
        _skip_next=false
        continue
      fi
      case "$_arg" in
        -s|--sandbox)
          echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2
          _skip_next=true; continue ;;
        --sandbox=*)
          echo "[$WRAPPER_NAME] WARN: sandbox 指定を danger-full-access に上書き（二重 sandbox 防止）" >&2
          continue ;;
      esac
      _new_args="${_new_args:+$_new_args
}${_arg}"
      if [ "$_sandbox_inserted" = false ]; then
        case "$_arg" in
          exec|e)
            _new_args="${_new_args}
-s
danger-full-access"
            _sandbox_inserted=true ;;
          review)
            _new_args="${_new_args}
-c
sandbox_mode=\"danger-full-access\""
            _sandbox_inserted=true ;;
        esac
      fi
    done
    set --
    _OLD_IFS="$IFS"; IFS="
"
    for _line in $_new_args; do
      set -- "$@" "$_line"
    done
    IFS="$_OLD_IFS"
    credential_guard_sandbox_exec "$REAL_BIN" "$@"
    ;;
  *)
    credential_guard_sandbox_exec "$REAL_BIN" "$@"
    ;;
esac
