#!/bin/sh
# macOS Seatbelt sandbox construction
# Sourced by credential-guard.sh
#
# Requires: $_tmpdir, $_SANDBOX_DENY_READ_PATHS, $_SANDBOX_ALLOW_WRITE_PATHS,
#           $_SANDBOX_ALLOW_WRITE_FILES to be set (newline-separated)
# Outputs: _setup_sandbox() function (sets _sandbox_cmd)

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
