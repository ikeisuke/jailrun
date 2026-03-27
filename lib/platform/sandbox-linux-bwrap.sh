#!/bin/sh
# Linux bubblewrap (bwrap) sandbox backend
# Sourced by sandbox-linux.sh
#
# Requires: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#           $_SANDBOX_ALLOW_WRITE_PATHS, $_PROXY_ENABLED (optional)
# Provides: _setup_sandbox(), _build_sandbox_exec()

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  _sandbox_cmd="bwrap"
  local _args="$_tmpdir/bwrap-args"
  {
    # === Layer 1: base filesystem (read-only) ===
    echo '--ro-bind'
    echo '/'
    echo '/'

    # Minimal /dev
    echo '--dev'
    echo '/dev'

    # /proc
    echo '--proc'
    echo '/proc'

    # === Layer 2: home directory (read-only) ===
    echo '--ro-bind'
    echo "$HOME"
    echo "$HOME"

    # === Layer 3: writable mounts (override ro-bind above) ===
    # Order matters: these must come AFTER --ro-bind $HOME

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

    # Whitelisted directories: writable
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      mkdir -p "$_p" 2>/dev/null || true
      echo '--bind'
      echo "$_p"
      echo "$_p"
    done

    # === Layer 4: deny overrides (on top of everything) ===

    # Sensitive directories: replace with empty tmpfs
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

    # === Isolation options ===
    echo '--unshare-ipc'
    echo '--unshare-uts'
    # NOTE: --new-session omitted to preserve job control (Ctrl+Z)
    echo '--die-with-parent'

    # Prevent privilege escalation
    echo '--cap-drop'
    echo 'ALL'

    # NOTE: Network isolation (--unshare-net) would block access to the
    # host-side proxy on 127.0.0.1. bwrap alone cannot restrict to
    # "localhost only" while keeping host loopback reachable.
    # Network restriction is enforced by the proxy layer instead:
    # HTTPS_PROXY forces traffic through the domain-filtering proxy.
  } > "$_args"
}

# Write sandbox exec command to stdout (appended to exec.sh)
_build_sandbox_exec() {
  printf 'exec bwrap \\\n'
  while IFS= read -r _line; do
    case "$_line" in
      --ro-bind|--bind)
        IFS= read -r _src
        IFS= read -r _dst
        printf '  %s "%s" "%s" \\\n' "$_line" "$_src" "$_dst"
        ;;
      --tmpfs|--dev|--proc|--cap-drop)
        IFS= read -r _path
        printf '  %s %s \\\n' "$_line" "$_path"
        ;;
      *)
        printf '  %s \\\n' "$_line"
        ;;
    esac
  done < "$_tmpdir/bwrap-args"
  echo '  -- "$@"'
}
