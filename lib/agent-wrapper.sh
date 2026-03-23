#!/bin/sh
# Common wrapper for AI agents
# Sourced from the jailrun entry point
# WRAPPER_NAME, JAILRUN_DIR, JAILRUN_LIB must be set by the caller
#
# Config: ~/.config/jailrun/config
# Profile override: AGENT_AWS_PROFILE=dev jailrun <tool>

set -eu

# WRAPPER_NAME must be set by the caller
if [ -z "${WRAPPER_NAME:-}" ]; then
  echo "[jailrun] ERROR: WRAPPER_NAME is not set" >&2
  exit 1
fi
. "$JAILRUN_LIB/credential-guard.sh"

# Resolve the real binary by excluding jailrun shims from PATH
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
    echo "[$WRAPPER_NAME] ERROR: real binary not found" >&2
    exit 1
  fi
}

# Sandbox detection helper (env variable or file access)
_is_sandboxed() {
  [ "${_CREDENTIAL_GUARD_SANDBOXED:-}" = "1" ] && return 0
  [ -f "$HOME/.aws/config" ] && ! test -r "$HOME/.aws/config" 2>/dev/null && return 0
  return 1
}

# Disable Codex's built-in sandbox before exec
# Unify under jailrun's Seatbelt/systemd-run sandbox
_exec_codex() {
  _resolve_real_bin
  _sandbox_inserted=false
  _skip_next=false
  # Rebuild positional parameters as argument list
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
        echo "[$WRAPPER_NAME] WARN: overriding sandbox to danger-full-access (prevent double sandbox)" >&2
        _skip_next=true; continue ;;
      --sandbox=*)
        echo "[$WRAPPER_NAME] WARN: overriding sandbox to danger-full-access (prevent double sandbox)" >&2
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
  # Restore _result from newline-separated to positional parameters
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

# Already sandboxed -> exec real binary directly (credentials already isolated)
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

# Normal startup: resolve binary -> credential isolation + sandbox exec
_resolve_real_bin

case "$WRAPPER_NAME" in
  codex)
    # Rewrite arguments before passing to credential_guard_sandbox_exec
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
          echo "[$WRAPPER_NAME] WARN: overriding sandbox to danger-full-access (prevent double sandbox)" >&2
          _skip_next=true; continue ;;
        --sandbox=*)
          echo "[$WRAPPER_NAME] WARN: overriding sandbox to danger-full-access (prevent double sandbox)" >&2
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
