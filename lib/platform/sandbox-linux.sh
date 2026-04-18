#!/bin/sh
# Linux sandbox backend dispatcher
# Sourced by sandbox.sh
#
# Selects the best available backend: systemd-run > none
# Each backend provides: _setup_sandbox(), _build_sandbox_exec()

. "$JAILRUN_LIB/platform/git-worktree.sh"

# Detect AppArmor availability (kernel enabled + userspace tools)
_APPARMOR_AVAILABLE=""
if [ -f /sys/module/apparmor/parameters/enabled ] && \
   [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = "Y" ] && \
   command -v apparmor_parser >/dev/null 2>&1; then
  _APPARMOR_AVAILABLE=1
  . "$JAILRUN_LIB/platform/sandbox-linux-apparmor.sh"
fi

if command -v systemd-run >/dev/null 2>&1; then
  . "$JAILRUN_LIB/platform/sandbox-linux-systemd.sh"
else
  echo "[$_WRAPPER_NAME] ERROR: systemd-run not found. Cannot launch without sandbox." >&2
  exit 1
fi

# Warn if sandbox_deny_read_names is set but AppArmor is not available
if [ "${_APPARMOR_AVAILABLE:-}" != "1" ] && [ -n "${SANDBOX_DENY_READ_NAMES:-}" ]; then
  echo "[$_WRAPPER_NAME] WARN: sandbox_deny_read_names requires AppArmor, ignoring" >&2
fi

# No-op deny log hooks (Linux does not support Seatbelt deny logging)
_start_deny_log() { :; }
_stop_deny_log() { :; }

# Cleanup hook (overridden by sandbox-linux-apparmor.sh when AppArmor is active)
if [ "${_APPARMOR_AVAILABLE:-}" != "1" ]; then
  _cleanup_sandbox() { :; }
fi
