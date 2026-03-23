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
    printf '-p ReadWritePaths=%s\n' "$_cwd"
    printf '-p ReadWritePaths=%s\n' "$_tmpdir"
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
    # Explicit write protection for config directory
    printf '-p ReadOnlyPaths=%s\n' "${CONFIG_DIR:-$HOME/.config/jailrun}"

    # Git worktree
    if [ -n "$_git_parent_toplevel" ]; then
      printf '-p ReadWritePaths=%s\n' "$_git_parent_toplevel"
      if [ -n "$_other_worktrees" ]; then
        _OLD_IFS="$IFS"; IFS="
"
        for _wt in $_other_worktrees; do
          [ -d "$_wt" ] && printf '-p InaccessiblePaths=%s\n' "$_wt"
        done
        IFS="$_OLD_IFS"
      fi
    elif [ -n "$_git_common_dir" ]; then
      printf '-p ReadWritePaths=%s\n' "$_git_common_dir"
    fi

    # Make whitelisted directories writable
    _OLD_IFS="$IFS"; IFS="
"
    for _p in $_SANDBOX_ALLOW_WRITE_PATHS; do
      mkdir -p "$_p" 2>/dev/null || true
      printf '-p ReadWritePaths=%s\n' "$_p"
    done

    # Make sensitive directories inaccessible
    for _p in $_SANDBOX_DENY_READ_PATHS; do
      [ -d "$_p" ] && printf '-p InaccessiblePaths=%s\n' "$_p"
    done
    IFS="$_OLD_IFS"
  } > "$_props"
}
