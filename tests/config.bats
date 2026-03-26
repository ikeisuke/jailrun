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

@test "config.sh generates TOML config on first run" {
  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
  '
  # exits 1 and creates config
  [ "$status" -eq 1 ]
  [ -f "$TEST_CONFIG_DIR/jailrun/config.toml" ]
  grep -q "allowed_aws_profiles" "$TEST_CONFIG_DIR/jailrun/config.toml"
  grep -q "gh_token_name" "$TEST_CONFIG_DIR/jailrun/config.toml"
}

@test "config.sh loads existing TOML config" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
allowed_aws_profiles = ["testprofile"]
default_aws_profile = "testprofile"
gh_token_name = "test"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
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

@test "config.sh auto-migrates legacy shell config to TOML" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config" <<'EOF'
ALLOWED_AWS_PROFILES="migrated"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
  '
  [ "$status" -eq 0 ]
  [ -f "$TEST_CONFIG_DIR/jailrun/config.toml" ]
  [[ "$output" == *"profiles=migrated"* ]]
}

@test "config.sh GH_TOKEN_NAME env override takes precedence" {
  mkdir -p "$TEST_CONFIG_DIR/jailrun"
  cat > "$TEST_CONFIG_DIR/jailrun/config.toml" <<'EOF'
[global]
gh_token_name = "from-config"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
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
  cat > "$TEST_CONFIG_DIR/security-wrapper/config" <<'EOF'
ALLOWED_AWS_PROFILES="migrated"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
EOF

  run sh -c '
    export XDG_CONFIG_HOME="'"$TEST_CONFIG_DIR"'"
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    . "'"$JAILRUN_LIB"'/config.sh"
    echo "profiles=$ALLOWED_AWS_PROFILES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"profiles=migrated"* ]]
}
