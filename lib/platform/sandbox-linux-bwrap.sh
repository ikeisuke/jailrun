#!/bin/sh
# Linux bubblewrap (bwrap) sandbox backend
# Sourced by sandbox-linux.sh
#
# Requires: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#           $_SANDBOX_ALLOW_WRITE_PATHS
# Provides: _setup_sandbox(), _build_sandbox_exec()

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  _sandbox_cmd="bwrap"
  local _args="$_tmpdir/bwrap-args"
  {
    # Base filesystem: read-only bind of /
    echo '--ro-bind'
    echo '/'
    echo '/'

    # Writable: /tmp
    echo '--bind'
    echo '/tmp'
    echo '/tmp'

    # Writable: tmpdir
    echo '--bind'
    echo "$_tmpdir"
    echo "$_tmpdir"

    # Writable: current working directory
    echo '--bind'
    echo "$_cwd"
    echo "$_cwd"

    # Minimal /dev
    echo '--dev'
    echo '/dev'

    # /proc
    echo '--proc'
    echo '/proc'

    # Home directory: read-only by default
    echo '--ro-bind'
    echo "$HOME"
    echo "$HOME"

    # Git worktree
    if [ -n "$_git_parent_toplevel" ]; then
      echo '--bind'
      echo "$_git_parent_toplevel"
      echo "$_git_parent_toplevel"
      if [ -n "$_other_worktrees" ]; then
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          if [ -d "$_wt" ]; then
            # Replace worktree with empty tmpfs to hide it
            echo '--tmpfs'
            echo "$_wt"
          fi
        done
        IFS="$_OLD_IFS"
      fi
    elif [ -n "$_git_common_dir" ]; then
      echo '--bind'
      echo "$_git_common_dir"
      echo "$_git_common_dir"
    fi

    # Make whitelisted directories writable
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      mkdir -p "$_p" 2>/dev/null || true
      echo '--bind'
      echo "$_p"
      echo "$_p"
    done

    # Make sensitive directories inaccessible
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      if [ -d "$_p" ]; then
        echo '--tmpfs'
        echo "$_p"
      fi
    done
    IFS="$_OLD_IFS"

    # Block D-Bus session bus (prevents GNOME Keyring / secret-tool access)
    _xdg_runtime="${XDG_RUNTIME_DIR:-}"
    if [ -n "$_xdg_runtime" ] && [ -S "$_xdg_runtime/bus" ]; then
      # Bind XDG_RUNTIME_DIR but hide the bus socket
      echo '--bind'
      echo "$_xdg_runtime"
      echo "$_xdg_runtime"
      echo '--ro-bind'
      echo '/dev/null'
      echo "$_xdg_runtime/bus"
    fi
    _dbus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    _dbus_sock=""
    case "$_dbus_addr" in
      *path=/*)
        _dbus_tail="${_dbus_addr#*path=}"
        _dbus_sock="${_dbus_tail%%,*}"
        _dbus_sock="${_dbus_sock%%;*}" ;;
    esac
    if [ -n "$_dbus_sock" ] && [ -S "$_dbus_sock" ]; then
      echo '--ro-bind'
      echo '/dev/null'
      echo "$_dbus_sock"
    else
      _DBUS_NEEDS_ENV_CLEAR=1
    fi

    # Config directory: read-only
    echo '--ro-bind'
    echo "${CONFIG_DIR:-$HOME/.config/jailrun}"
    echo "${CONFIG_DIR:-$HOME/.config/jailrun}"

    # Isolation options
    echo '--unshare-ipc'
    echo '--new-session'
    echo '--die-with-parent'
  } > "$_args"
}

# Write sandbox exec command to stdout (appended to exec.sh)
_build_sandbox_exec() {
  printf 'exec bwrap \\\n'
  # Read args two/three at a time from the args file
  while IFS= read -r _line; do
    case "$_line" in
      --ro-bind|--bind)
        IFS= read -r _src
        IFS= read -r _dst
        printf '  %s "%s" "%s" \\\n' "$_line" "$_src" "$_dst"
        ;;
      --tmpfs|--dev|--proc)
        IFS= read -r _path
        printf '  %s "%s" \\\n' "$_line" "$_path"
        ;;
      *)
        printf '  %s \\\n' "$_line"
        ;;
    esac
  done < "$_tmpdir/bwrap-args"
  echo '  -- "$@"'
}
