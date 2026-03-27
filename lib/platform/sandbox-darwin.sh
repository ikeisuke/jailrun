#!/bin/sh
# macOS Seatbelt sandbox backend
# Sourced by sandbox.sh
#
# Requires: $_tmpdir, $_SANDBOX_DENY_READ_PATHS, $_SANDBOX_ALLOW_WRITE_PATHS,
#           $_SANDBOX_ALLOW_WRITE_FILES to be set (newline-separated)
# Provides: _setup_sandbox(), _build_sandbox_exec()

. "$JAILRUN_LIB/platform/git-worktree.sh"

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  # Generate Seatbelt profile
  local _sb="$_tmpdir/sandbox.sb"
  {
    echo '(version 1)'
    echo '(allow default)'
    echo ''
    echo ';; NOTE: Keychain (SecurityServer) access is intentionally allowed.'
    echo ';; Blocking it breaks TLS certificate verification and prevents'
    echo ';; sandboxed apps from refreshing their own auth tokens.'
    echo ';; GitHub PAT is protected by file-read deny rules instead.'
    echo ''
    # When proxy is enabled, restrict network to localhost only
    if [ "${PROXY_ENABLED:-false}" = "true" ] || [ "${PROXY_ENABLED:-0}" = "1" ]; then
      echo ';; Network: localhost only (proxy handles domain filtering)'
      echo '(deny network-outbound (require-not (require-any'
      echo '  (remote ip "localhost:*")'
      echo '  (remote unix-socket))))'
    fi
    echo ''
    echo ';; Deny read access to sensitive directories'
    echo '(deny file-read*'
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      echo "  (subpath \"$_p\")"
    done
    IFS="$_OLD_IFS"
    echo ')'
    echo ''
    if [ "${AGENT_SANDBOX_DEBUG:-}" != "1" ]; then
      echo ';; Restrict writes to whitelisted paths'
      echo '(deny file-write*'
      echo '  (require-not'
      echo '    (require-any'
      echo "      (subpath \"$_cwd\")"
      [ -n "$_git_parent_toplevel" ] && echo "      (subpath \"$_git_parent_toplevel\")"
      [ -z "$_git_parent_toplevel" ] && [ -n "$_git_common_dir" ] && echo "      (subpath \"$_git_common_dir\")"
      echo '      (subpath "/tmp")'
      echo '      (subpath "/private/tmp")'
      echo '      (subpath "/private/var/folders")'
      echo '      (literal "/dev/null")'
      echo '      (literal "/dev/zero")'
      echo '      (literal "/dev/random")'
      echo '      (literal "/dev/urandom")'
      echo "      (subpath \"$_tmpdir\")"
      _OLD_IFS="$IFS"; IFS="
"
      for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
        echo "      (subpath \"$_p\")"
      done
      for _f in $_SANDBOX_ALLOW_WRITE_FILES; do
        echo "      (literal \"$_f\")"
      done
      IFS="$_OLD_IFS"
      echo ')))'
      if [ -n "$_other_worktrees" ]; then
        echo ''
        echo ';; Deny writes to other worktrees'
        echo '(deny file-write*'
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          echo "  (subpath \"$_wt\")"
        done
        IFS="$_OLD_IFS"
        echo ')'
      fi
    else
      echo ';; Debug: write restrictions disabled (read-deny only)'
    fi
  } > "$_sb"
  _sandbox_cmd="sandbox-exec -f $_sb"
}

# Write sandbox exec command to stdout (appended to exec.sh)
_build_sandbox_exec() {
  printf 'exec %s "$@"\n' "$_sandbox_cmd"
}
