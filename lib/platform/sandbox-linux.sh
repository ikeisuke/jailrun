#!/bin/sh
# Linux systemd-run sandbox construction
# Sourced by credential-guard.sh
#
# Requires: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#           $_SANDBOX_ALLOW_WRITE_PATHS to be set (newline-separated)
# Outputs: _setup_sandbox() function
#   _sandbox_cmd="systemd-run" (marker)
#   Writes properties to $_tmpdir/systemd-props

. "$JAILRUN_LIB/platform/git-worktree.sh"

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  if ! command -v systemd-run >/dev/null 2>&1; then
    echo "[$_WRAPPER_NAME] WARN: systemd-run not available, launching without sandbox" >&2
    return
  fi

  _sandbox_cmd="systemd-run"
  local _props="$_tmpdir/systemd-props"
  {
    # Prevent privilege escalation
    echo '-p NoNewPrivileges=yes'
    echo '-p CapabilityBoundingSet='
    echo '-p AmbientCapabilities='
    echo '-p RestrictSUIDSGID=yes'
    echo '-p LockPersonality=yes'
    # Device restrictions
    echo '-p PrivateDevices=no'
    echo '-p DevicePolicy=closed'
    echo '-p DeviceAllow=/dev/null rw'
    echo '-p DeviceAllow=/dev/random r'
    echo '-p DeviceAllow=/dev/urandom r'
    # Process and IPC isolation
    echo '-p PrivateUsers=yes'
    echo '-p PrivateMounts=yes'
    echo '-p PrivateIPC=yes'
    echo '-p PrivateTmp=no'
    echo '-p ReadWritePaths=/tmp'
    # Network
    echo '-p PrivateNetwork=no'
    echo '-p RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6'
    # Filesystem
    echo '-p ProtectSystem=strict'
    echo '-p ProtectHome=read-only'
    echo "-p ReadWritePaths=$_cwd"
    echo "-p ReadWritePaths=$_tmpdir"
    # Kernel protection
    echo '-p ProtectProc=invisible'
    echo '-p ProtectClock=yes'
    echo '-p ProtectHostname=yes'
    echo '-p ProtectKernelLogs=yes'
    echo '-p ProtectKernelModules=yes'
    echo '-p ProtectKernelTunables=yes'
    echo '-p ProtectControlGroups=yes'
    # Syscall filter
    echo '-p SystemCallArchitectures=native'
    echo '-p SystemCallFilter=@system-service'
    echo '-p SystemCallFilter=~@privileged @debug'
    echo '-p SystemCallErrorNumber=EPERM'
    # Namespace and realtime restrictions
    echo '-p RestrictNamespaces=yes'
    echo '-p RestrictRealtime=yes'
    # Miscellaneous
    echo '-p UMask=0077'
    echo '-p CoredumpFilter=0'
    echo '-p KeyringMode=private'
    # Block D-Bus session bus (prevents GNOME Keyring / secret-tool access)
    # 1. Block default XDG user bus socket
    _xdg_runtime="${XDG_RUNTIME_DIR:-}"
    if [ -n "$_xdg_runtime" ] && [ -S "$_xdg_runtime/bus" ]; then
      echo "-p InaccessiblePaths=$_xdg_runtime/bus"
    fi
    # 2. Block socket from DBUS_SESSION_BUS_ADDRESS if it contains a file path
    #    Handles formats: unix:path=/x, unix:guid=...,path=/x, etc.
    _dbus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    _dbus_sock=""
    case "$_dbus_addr" in
      *path=/*)
        # Extract path= value from anywhere in the address string
        _dbus_tail="${_dbus_addr#*path=}"
        _dbus_sock="${_dbus_tail%%,*}"
        _dbus_sock="${_dbus_sock%%;*}" ;;
    esac
    if [ -n "$_dbus_sock" ] && [ -S "$_dbus_sock" ]; then
      echo "-p InaccessiblePaths=$_dbus_sock"
    else
      # Abstract sockets or unresolvable: clear the address as fallback
      _DBUS_NEEDS_ENV_CLEAR=1
    fi
    # Explicit write protection for config directory
    echo "-p ReadOnlyPaths=${CONFIG_DIR:-$HOME/.config/jailrun}"

    # Git worktree
    if [ -n "$_git_parent_toplevel" ]; then
      echo "-p ReadWritePaths=$_git_parent_toplevel"
      if [ -n "$_other_worktrees" ]; then
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          [ -d "$_wt" ] && echo "-p InaccessiblePaths=$_wt"
        done
        IFS="$_OLD_IFS"
      fi
    elif [ -n "$_git_common_dir" ]; then
      echo "-p ReadWritePaths=$_git_common_dir"
    fi

    # Make whitelisted directories writable
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      mkdir -p "$_p" 2>/dev/null || true
      echo "-p ReadWritePaths=$_p"
    done

    # Make sensitive directories inaccessible
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      [ -d "$_p" ] && echo "-p InaccessiblePaths=$_p"
    done
    IFS="$_OLD_IFS"
  } > "$_props"
}
