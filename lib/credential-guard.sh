#!/bin/sh
# credential isolation orchestrator
# sourced by agent-wrapper.sh
#
# pipeline: config -> credentials -> sandbox -> exec

# --- sandbox detection: early return if already sandboxed ---
if [ "${_CREDENTIAL_GUARD_SANDBOXED:-}" = "1" ]; then
  return 0 2>/dev/null || true
fi

. "$JAILRUN_LIB/config.sh"
. "$JAILRUN_LIB/credentials.sh"
. "$JAILRUN_LIB/sandbox.sh"
