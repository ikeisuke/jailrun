#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

@test "config.sh generates config on first run" {
  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
  '
  # exits 1 and creates config
  [ "$status" -eq 1 ]
  [ -f "$TEST_CONFIG_DIR/jailrun/config" ]
  # config contains expected variables
  grep -q "ALLOWED_AWS_PROFILES" "$TEST_CONFIG_DIR/jailrun/config"
  grep -q "GH_KEYCHAIN_SERVICE" "$TEST_CONFIG_DIR/jailrun/config"
}

@test "config.sh loads existing config" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
ALLOWED_AWS_PROFILES="testprofile"
DEFAULT_AWS_PROFILE="testprofile"
GH_KEYCHAIN_SERVICE="github:test"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
    echo "default=$DEFAULT_AWS_PROFILE"
    echo "gh=$GH_KEYCHAIN_SERVICE"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=testprofile"* ]]
  [[ "$output" == *"default=testprofile"* ]]
  [[ "$output" == *"gh=github:test"* ]]
}

@test "config.sh has no *_BIN variables in generated config" {
  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
  ' 2>/dev/null || true

  if [ -f "$TEST_CONFIG_DIR/jailrun/config" ]; then
    run grep -c '_BIN=' "$TEST_CONFIG_DIR/jailrun/config"
    [ "$output" = "0" ]
  fi
}

@test "config.sh migrates from old security-wrapper dir" {
  mkdir -p "$TEST_CONFIG_DIR/security-wrapper"
  echo 'ALLOWED_AWS_PROFILES="migrated"' > "$TEST_CONFIG_DIR/security-wrapper/config"

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=migrated"* ]]
  [ -f "$TEST_CONFIG_DIR/jailrun/config" ]
}
