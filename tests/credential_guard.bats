#!/usr/bin/env bats

# Integration tests for credential-guard.sh
# Tests sandbox detection (double-sandbox prevention) and pipeline setup.

load helpers

setup() {
  setup_jailrun_env
}

@test "credential-guard skips when _CREDENTIAL_GUARD_SANDBOXED=1" {
  # When already sandboxed, sourcing credential-guard.sh should return immediately
  # without sourcing config.sh/credentials.sh/sandbox.sh
  run sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export _CREDENTIAL_GUARD_SANDBOXED=1
    . "$JAILRUN_LIB/credential-guard.sh"
    # If we reach here, the early return worked.
    # Verify that config.sh was NOT sourced by checking a variable it would set
    if [ -z "${CONFIG_DIR:-}" ]; then
      echo "SKIPPED_OK"
    else
      echo "NOT_SKIPPED"
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED_OK"* ]]
}

@test "credential-guard does not skip when _CREDENTIAL_GUARD_SANDBOXED is unset" {
  # Without the sandboxed flag, credential-guard.sh should source config.sh
  # which will try to set up config. We expect it to proceed (and likely
  # exit due to missing config, which is fine for this test).
  run sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME="claude"
    unset _CREDENTIAL_GUARD_SANDBOXED
    export XDG_CONFIG_HOME="$(mktemp -d)"
    . "$JAILRUN_LIB/credential-guard.sh" 2>&1
  '
  # config.sh will exit 1 on first run (generates config and asks to review)
  # This proves credential-guard.sh did NOT early-return
  [ "$status" -eq 1 ]
}

@test "credential-guard does not skip when _CREDENTIAL_GUARD_SANDBOXED is empty" {
  run sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME="claude"
    export _CREDENTIAL_GUARD_SANDBOXED=""
    export XDG_CONFIG_HOME="$(mktemp -d)"
    . "$JAILRUN_LIB/credential-guard.sh" 2>&1
  '
  # Should not skip — proceeds to config.sh which exits 1 on first run
  [ "$status" -eq 1 ]
}

@test "credential-guard does not skip when _CREDENTIAL_GUARD_SANDBOXED is 0" {
  run sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME="claude"
    export _CREDENTIAL_GUARD_SANDBOXED=0
    export XDG_CONFIG_HOME="$(mktemp -d)"
    . "$JAILRUN_LIB/credential-guard.sh" 2>&1
  '
  # "0" is not "1", so should not skip
  [ "$status" -eq 1 ]
}
