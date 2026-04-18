#!/bin/sh
# Linux systemd-run sandbox backend
# Sourced by sandbox-linux.sh
#
# Requires: $_tmpdir, $_WRAPPER_NAME, $_SANDBOX_DENY_READ_PATHS,
#           $_SANDBOX_ALLOW_WRITE_PATHS, $_git_parent_toplevel,
#           $_git_common_dir, $_other_worktrees
# Provides: _setup_sandbox(), _build_sandbox_exec()

_setup_sandbox() {
  local _cwd="$PWD"
  _detect_git_worktree

  # Try AppArmor for filesystem control
  _APPARMOR_PROFILE_LOADED=""
  if [ "${_APPARMOR_AVAILABLE:-}" = "1" ]; then
    _build_apparmor_profile
    _load_apparmor_profile || true
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
    # When proxy is enabled, restrict to localhost only (proxy handles filtering)
    if [ "${PROXY_ENABLED:-false}" = "true" ] || [ "${PROXY_ENABLED:-0}" = "1" ]; then
      echo '-p IPAddressDeny=any'
      echo '-p IPAddressAllow=127.0.0.0/8'
      echo '-p IPAddressAllow=::1/128'
    fi
    # Filesystem
    if [ -z "${_APPARMOR_PROFILE_LOADED:-}" ]; then
      echo '-p ProtectSystem=strict'
      echo '-p ProtectHome=read-only'
      echo "-p ReadWritePaths=$_cwd"
      echo "-p ReadWritePaths=$_tmpdir"
    fi
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
    # Detect socket type for _DBUS_NEEDS_ENV_CLEAR (used by env-spec)
    _dbus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    _dbus_sock=""
    case "$_dbus_addr" in
      *path=/*)
        # Extract path= value from anywhere in the address string
        _dbus_tail="${_dbus_addr#*path=}"
        _dbus_sock="${_dbus_tail%%,*}"
        _dbus_sock="${_dbus_sock%%;*}" ;;
    esac
    if [ -z "$_dbus_sock" ] || [ ! -S "$_dbus_sock" ]; then
      # Abstract sockets or unresolvable: clear the address as fallback
      _DBUS_NEEDS_ENV_CLEAR=1
    fi
    if [ -z "${_APPARMOR_PROFILE_LOADED:-}" ]; then
      # Block via InaccessiblePaths (systemd filesystem control mode)
      _xdg_runtime="${XDG_RUNTIME_DIR:-}"
      if [ -n "$_xdg_runtime" ] && [ -S "$_xdg_runtime/bus" ]; then
        echo "-p InaccessiblePaths=$_xdg_runtime/bus"
      fi
      if [ -n "$_dbus_sock" ] && [ -S "$_dbus_sock" ]; then
        echo "-p InaccessiblePaths=$_dbus_sock"
      fi
    fi

    if [ -z "${_APPARMOR_PROFILE_LOADED:-}" ]; then
      # --- systemd filesystem control (fallback when AppArmor unavailable) ---

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
        [ -d "$_p" ] || continue
        echo "-p ReadWritePaths=$_p"
      done

      # Lockfile directories: proper-lockfile creates <dir>.lock next to target.
      # Only add ReadWritePaths if the directory already exists. Do NOT pre-create
      # with mkdir — proper-lockfile uses mkdir to acquire locks, so a pre-created
      # directory would appear as a permanently held lock. See #23.
      for _p in $_SANDBOX_ALLOW_WRITE_LOCK_PATHS; do
        [ -d "$_p" ] || continue
        echo "-p ReadWritePaths=$_p"
      done

      # NOTE: _SANDBOX_ALLOW_WRITE_FILES and _SANDBOX_ALLOW_WRITE_REGEXES are
      # not consumed in systemd-only mode. systemd does not support regex-based
      # or single-file granularity permissions. Target files (e.g. ~/.claude.json,
      # ~/.claude.json.tmp.*) are covered only if $_cwd includes $HOME.

      # Make sensitive paths inaccessible (directories and files).
      # NOTE: InaccessiblePaths requires the path to exist; non-existent paths
      # are skipped. Paths created after sandbox startup are NOT protected.
      for _p in $_SANDBOX_DENY_READ_PATHS; do
        [ -e "$_p" ] && echo "-p InaccessiblePaths=$_p"
      done

      # NOTE: _SANDBOX_DENY_READ_REGEXES is not consumed in systemd-only mode.
      # Filename-based deny (sandbox_deny_read_names) requires AppArmor.

      IFS="$_OLD_IFS"
    else
      # --- AppArmor handles all filesystem control ---
      echo "-p AppArmorProfile=$_apparmor_profile_name"
    fi
  } > "$_props"
}

# Generate systemd EnvironmentFile from env-spec
_build_systemd_envfile() {
  local _envfile="$_tmpdir/env-systemd"
  while IFS= read -r _line; do
    case "$_line" in
      SET\ *) printf '%s\n' "${_line#SET }" ;;
    esac
  done < "$_tmpdir/env-spec" > "$_envfile"
}

# Write sandbox exec command to stdout (appended to exec.sh)
_build_sandbox_exec() {
  _build_systemd_envfile
  # --pty allocates a new PTY, so set OSC title from inside the PTY
  printf 'exec systemd-run \\\n'
  printf '  --user --pty --wait --collect --same-dir \\\n'
  printf '  -p "EnvironmentFile=%s/env-systemd" \\\n' "$_tmpdir"
  while IFS= read -r _line; do
    case "$_line" in
      -p\ *) printf '  -p "%s" \\\n' "${_line#-p }" ;;
      *)     printf '  %s \\\n' "$_line" ;;
    esac
  done < "$_tmpdir/systemd-props"
  echo '  -- sh -c '\''printf "\\033]0;jailrun %s\\007" "${1##*/}"; exec "$@"'\'' _ "$@"'
}
