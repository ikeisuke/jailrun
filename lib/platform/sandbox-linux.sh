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
  _setup_sandbox() {
    echo "[$_WRAPPER_NAME] WARN: no sandbox backend available (install systemd), launching without sandbox" >&2
  }
  _build_sandbox_exec() {
    printf 'exec "$@"\n'
  }
fi
