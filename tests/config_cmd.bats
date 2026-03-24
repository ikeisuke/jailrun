#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  export CONFIG_DIR="$TEST_CONFIG_DIR/jailrun"
  export CONFIG_FILE="$CONFIG_DIR/config"
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

_create_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'EOF'
ALLOWED_AWS_PROFILES="default"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
SANDBOX_EXTRA_DENY_READ=""
SANDBOX_EXTRA_ALLOW_WRITE=""
SANDBOX_EXTRA_ALLOW_WRITE_FILES=""
SANDBOX_PASSTHROUGH_ENV=""
EOF
}

# --- show ---

@test "config show displays all known variables" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" show
  [ "$status" -eq 0 ]
  [[ "$output" == *'ALLOWED_AWS_PROFILES="default"'* ]]
  [[ "$output" == *'DEFAULT_AWS_PROFILE="default"'* ]]
  [[ "$output" == *'GH_TOKEN_NAME="classic"'* ]]
  [[ "$output" == *'SANDBOX_EXTRA_DENY_READ=""'* ]]
  [[ "$output" == *'SANDBOX_PASSTHROUGH_ENV=""'* ]]
}

@test "config show fails without config file" {
  run "$JAILRUN_LIB/config-cmd.sh" show
  [ "$status" -eq 1 ]
  [[ "$output" == *"no config file"* ]]
}

# --- set ---

@test "config set updates existing key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set DEFAULT_AWS_PROFILE staging
  [ "$status" -eq 0 ]
  grep -q 'DEFAULT_AWS_PROFILE="staging"' "$CONFIG_FILE"
}

@test "config set rejects unknown key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set UNKNOWN_KEY value
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key"* ]]
}

@test "config set --append adds value to list" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append ALLOWED_AWS_PROFILES staging
  [ "$status" -eq 0 ]
  grep -q 'ALLOWED_AWS_PROFILES="default staging"' "$CONFIG_FILE"
}

@test "config set --append avoids duplicates" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append ALLOWED_AWS_PROFILES default
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in"* ]]
  # value unchanged
  grep -q 'ALLOWED_AWS_PROFILES="default"' "$CONFIG_FILE"
}

@test "config set --remove removes value from list" {
  _create_config
  "$JAILRUN_LIB/config-cmd.sh" set ALLOWED_AWS_PROFILES "dev staging prod"
  run "$JAILRUN_LIB/config-cmd.sh" set --remove ALLOWED_AWS_PROFILES staging
  [ "$status" -eq 0 ]
  grep -q 'ALLOWED_AWS_PROFILES="dev prod"' "$CONFIG_FILE"
}

@test "config set --append rejects non-list key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append DEFAULT_AWS_PROFILE extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"only supported for list-type"* ]]
}

@test "config set warns on shell-unsafe characters" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set GH_TOKEN_NAME 'test;rm'
  [ "$status" -eq 0 ]
  [[ "$output" == *"shell-unsafe"* ]]
}

@test "config set appends key if not in file" {
  mkdir -p "$CONFIG_DIR"
  echo 'DEFAULT_AWS_PROFILE="default"' > "$CONFIG_FILE"
  run "$JAILRUN_LIB/config-cmd.sh" set GH_TOKEN_NAME fine-grained
  [ "$status" -eq 0 ]
  grep -q 'GH_TOKEN_NAME="fine-grained"' "$CONFIG_FILE"
}

# --- edit ---

@test "config edit fails without config file" {
  run "$JAILRUN_LIB/config-cmd.sh" edit
  [ "$status" -eq 1 ]
  [[ "$output" == *"no config file"* ]]
}

# --- path ---

@test "config path prints config file path" {
  run "$JAILRUN_LIB/config-cmd.sh" path
  [ "$status" -eq 0 ]
  [[ "$output" == *"/jailrun/config" ]]
}

# --- init ---

@test "config init creates default config" {
  run "$JAILRUN_LIB/config-cmd.sh" init
  [ "$status" -eq 0 ]
  [ -f "$CONFIG_FILE" ]
  grep -q "ALLOWED_AWS_PROFILES" "$CONFIG_FILE"
  grep -q "GH_TOKEN_NAME" "$CONFIG_FILE"
}

@test "config init refuses if config exists" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "config init --force overwrites existing config" {
  _create_config
  echo 'CUSTOM="yes"' >> "$CONFIG_FILE"
  run "$JAILRUN_LIB/config-cmd.sh" init --force
  [ "$status" -eq 0 ]
  # custom line should be gone
  ! grep -q "CUSTOM" "$CONFIG_FILE"
  grep -q "ALLOWED_AWS_PROFILES" "$CONFIG_FILE"
}

# --- help ---

@test "config --help exits 0" {
  run "$JAILRUN_LIB/config-cmd.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "config with unknown subcommand exits 1" {
  run "$JAILRUN_LIB/config-cmd.sh" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

# --- integration with jailrun dispatch ---

@test "jailrun config --help exits 0" {
  run "$JAILRUN_DIR/jailrun" config --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
