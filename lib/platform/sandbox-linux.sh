#!/bin/sh
# Linux sandbox backend dispatcher
# Sourced by sandbox.sh
#
# Selects the best available backend: systemd-run > none
# Each backend provides: _setup_sandbox(), _build_sandbox_exec()

. "$JAILRUN_LIB/platform/git-worktree.sh"

if command -v systemd-run >/dev/null 2>&1; then
  . "$JAILRUN_LIB/platform/sandbox-linux-systemd.sh"
else
  echo "[$_WRAPPER_NAME] ERROR: systemd-run not found. Cannot launch without sandbox." >&2
  exit 1
fi

# No-op deny log hooks (Linux does not support Seatbelt deny logging)
_start_deny_log() { :; }
_stop_deny_log() { :; }
