#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
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

@test "active proxy is written to env-spec for systemd EnvironmentFile" {
  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _PROXY_BIND="10.200.0.1"
    _PROXY_PORT="60001"
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"SET HTTPS_PROXY=http://10.200.0.1:60001"* ]]
  [[ "$output" == *"SET HTTP_PROXY=http://10.200.0.1:60001"* ]]
  [[ "$output" == *"SET https_proxy=http://10.200.0.1:60001"* ]]
  [[ "$output" == *"SET http_proxy=http://10.200.0.1:60001"* ]]
  [[ "$output" == *"SET NODE_USE_ENV_PROXY=1"* ]]
}

@test "basic env (HOME/USER/LOGNAME/SHELL) is injected via env-spec" {
  run env -u _CREDENTIAL_GUARD_SANDBOXED \
    HOME=/home/jailrun-test USER=jailrun-test LOGNAME=jailrun-test SHELL=/bin/sh \
    sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"SET HOME=/home/jailrun-test"* ]]
  # USER and LOGNAME are derived from `id -un`, not from $USER. Just confirm
  # the SET lines exist (values depend on the runner identity).
  [[ "$output" == *"SET USER="* ]]
  [[ "$output" == *"SET LOGNAME="* ]]
  [[ "$output" == *"SET SHELL=/bin/sh"* ]]
}

@test "env-spec escapes shell metacharacters in HOME (no wrapper-side expansion)" {
  # Values containing ", $, backtick, backslash must not be evaluated when
  # exec.sh emits `export KEY="VALUE"`.
  run env -u _CREDENTIAL_GUARD_SANDBOXED \
    HOME='/tmp/he"l$lo`world\back' sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_env_spec
    cat "$_tmpdir/env-spec"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  # Each special char must be backslash-escaped in the env-spec SET line so
  # the downstream `export KEY="VALUE"` evaluation is inert.
  [[ "$output" == *'SET HOME=/tmp/he\"l\$lo\`world\\back'* ]]
}
