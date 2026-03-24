#!/bin/sh
# Common wrapper for AI agents
# Sourced from the jailrun entry point
# WRAPPER_NAME, JAILRUN_DIR, JAILRUN_LIB must be set by the caller
#
# Config: ~/.config/jailrun/config
# Profile override: AGENT_AWS_PROFILES="dev staging" jailrun <tool>

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
      */jailrun/shims|*/lib/shims) ;;
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
  [ "${_CREDENTIAL_GUARD_SANDBOXED:-}" = "1" ]
}

# Rewrite Codex args and exec.
# $1 = "direct" (exec binary) or "sandbox" (credential_guard_sandbox_exec)
# $2 = binary path
# $3.. = original arguments
# Uses shift+set to preserve arguments containing newlines.
_rewrite_and_exec_codex() {
  _exec_mode="$1"; shift
  _bin="$1"; shift
  _sandbox_inserted=false
  _skip_next=false
  _argc=$#
  _i=0
  while [ $_i -lt $_argc ]; do
    _arg="$1"; shift; _i=$((_i + 1))
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
    set -- "$@" "$_arg"
    if [ "$_sandbox_inserted" = false ]; then
      case "$_arg" in
        exec|e)
          set -- "$@" -s danger-full-access
          _sandbox_inserted=true ;;
        review)
          set -- "$@" -c 'sandbox_mode="danger-full-access"'
          _sandbox_inserted=true ;;
      esac
    fi
  done
  [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$WRAPPER_NAME] exec: $_bin $*" >&2
  if [ "$_exec_mode" = "direct" ]; then
    exec "$_bin" "$@"
  else
    credential_guard_sandbox_exec "$_bin" "$@"
  fi
}

# Already sandboxed -> exec real binary directly (credentials already isolated)
if _is_sandboxed; then
  _resolve_real_bin
  case "$WRAPPER_NAME" in
    codex) _rewrite_and_exec_codex direct "$REAL_BIN" "$@" ;;
    *)
      [ "${AGENT_SANDBOX_DEBUG:-}" = "1" ] && echo "[$WRAPPER_NAME] exec: $REAL_BIN $*" >&2
      exec "$REAL_BIN" "$@"
      ;;
  esac
fi

# Normal startup: resolve binary -> credential isolation + sandbox exec
_resolve_real_bin

case "$WRAPPER_NAME" in
  codex)
    _rewrite_and_exec_codex sandbox "$REAL_BIN" "$@"
    ;;
  *)
    credential_guard_sandbox_exec "$REAL_BIN" "$@"
    ;;
esac
