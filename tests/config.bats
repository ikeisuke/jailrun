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
  grep -q "GH_TOKEN_NAME" "$TEST_CONFIG_DIR/jailrun/config"
}

@test "config.sh loads existing config" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
ALLOWED_AWS_PROFILES="testprofile"
DEFAULT_AWS_PROFILE="testprofile"
GH_TOKEN_NAME="test"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
    echo "default=$DEFAULT_AWS_PROFILE"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=testprofile"* ]]
  [[ "$output" == *"default=testprofile"* ]]
  [[ "$output" == *"gh=test"* ]]
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

@test "config.sh migrates legacy GH_KEYCHAIN_SERVICE with github: prefix" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
GH_KEYCHAIN_SERVICE="github:fine-grained-myorg"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=fine-grained-myorg"* ]]
  [[ "$output" == *"GH_KEYCHAIN_SERVICE is deprecated"* ]]
}

@test "config.sh migrates legacy GH_KEYCHAIN_SERVICE without github: prefix" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
GH_KEYCHAIN_SERVICE="custom-token"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=custom-token"* ]]
}

@test "config.sh GH_TOKEN_NAME takes precedence over legacy GH_KEYCHAIN_SERVICE" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
GH_TOKEN_NAME="classic"
GH_KEYCHAIN_SERVICE="github:work"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=classic"* ]]
  # should NOT show deprecation warning when GH_TOKEN_NAME is explicitly set
  [[ "$output" != *"deprecated"* ]]
}

@test "config.sh GH_TOKEN_NAME with export syntax takes precedence over legacy" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
export GH_TOKEN_NAME="classic"
GH_KEYCHAIN_SERVICE="github:work"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=classic"* ]]
  [[ "$output" != *"deprecated"* ]]
}

@test "config.sh GH_TOKEN_NAME env override takes precedence" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
GH_TOKEN_NAME="from-config"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export WRAPPER_NAME=claude
    export GH_TOKEN_NAME="from-env"
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "gh=$GH_TOKEN_NAME"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh=from-env"* ]]
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
