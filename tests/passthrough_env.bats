#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<CONF
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_TOKEN_NAME="classic"
CONF
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

@test "SANDBOX_PASSTHROUGH_ENV passes set variables to env-spec" {
  run env -u _CREDENTIAL_GUARD_SANDBOXED \
    MY_VAR1=hello MY_VAR2=world sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export SANDBOX_PASSTHROUGH_ENV="MY_VAR1 MY_VAR2"
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"SET MY_VAR1=hello"* ]]
  [[ "$output" == *"SET MY_VAR2=world"* ]]
}

@test "SANDBOX_PASSTHROUGH_ENV skips unset variables" {
  run env -u _CREDENTIAL_GUARD_SANDBOXED \
    -u UNSET_VAR MY_SET_VAR=present sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export SANDBOX_PASSTHROUGH_ENV="UNSET_VAR MY_SET_VAR"
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" != *"SET UNSET_VAR="* ]]
  [[ "$output" == *"SET MY_SET_VAR=present"* ]]
}

@test "empty SANDBOX_PASSTHROUGH_ENV produces no extra entries" {
  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export SANDBOX_PASSTHROUGH_ENV=""
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  # Count SET lines - should only have the standard ones, no passthrough entries
  local set_count
  set_count=$(echo "$output" | grep -c '^SET ')
  # Standard SET entries: AWS_CONFIG_FILE, AWS_SHARED_CREDENTIALS_FILE,
  # GH_CONFIG_DIR, SSH_AUTH_SOCK, PATH, _CREDENTIAL_GUARD_SANDBOXED
  # No extra ones from passthrough
  [[ "$output" != *"SET SANDBOX_PASSTHROUGH_ENV="* ]]
}
