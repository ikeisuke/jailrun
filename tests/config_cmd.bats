#!/usr/bin/env bats

load helpers

setup() {
  setup_jailrun_env
  TEST_CONFIG_DIR=$(mktemp -d)
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  export CONFIG_DIR="$TEST_CONFIG_DIR/jailrun"
  CONFIG_FILE="$CONFIG_DIR/config.toml"
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

_create_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'EOF'
[global]
gh_token_name = "classic"
allowed_aws_profiles = ["default"]
default_aws_profile = "default"
sandbox_extra_deny_read = []
sandbox_extra_allow_write = []
sandbox_extra_allow_write_files = []
sandbox_passthrough_env = []
EOF
}

# --- show ---

@test "config show displays all known variables" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" show
  [ "$status" -eq 0 ]
  [[ "$output" == *'allowed_aws_profiles'* ]]
  [[ "$output" == *'default_aws_profile'* ]]
  [[ "$output" == *'gh_token_name'* ]]
  [[ "$output" == *'sandbox_extra_deny_read'* ]]
  [[ "$output" == *'sandbox_passthrough_env'* ]]
}

@test "config show fails without config file" {
  run "$JAILRUN_LIB/config-cmd.sh" show
  [ "$status" -eq 1 ]
  [[ "$output" == *"no config file"* ]]
}

# --- set ---

@test "config set updates existing key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set default_aws_profile staging
  [ "$status" -eq 0 ]
  grep -q 'default_aws_profile = "staging"' "$CONFIG_FILE"
}

@test "config set rejects unknown key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set unknown_key value
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown key"* ]]
}

@test "config set --append adds value to list" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append allowed_aws_profiles staging
  [ "$status" -eq 0 ]
  grep -q '"staging"' "$CONFIG_FILE"
}

@test "config set --append avoids duplicates" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append allowed_aws_profiles default
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in"* ]]
}

@test "config set --remove removes value from list" {
  _create_config
  "$JAILRUN_LIB/config-cmd.sh" set allowed_aws_profiles "dev staging prod"
  run "$JAILRUN_LIB/config-cmd.sh" set --remove allowed_aws_profiles staging
  [ "$status" -eq 0 ]
  # staging should be gone
  ! grep -q '"staging"' "$CONFIG_FILE"
}

@test "config set --append rejects non-list key" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" set --append default_aws_profile extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"only supported for list-type"* ]]
}

@test "config set appends key if not in file" {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'EOF'
[global]
default_aws_profile = "default"
EOF
  run "$JAILRUN_LIB/config-cmd.sh" set gh_token_name fine-grained
  [ "$status" -eq 0 ]
  grep -q 'gh_token_name' "$CONFIG_FILE"
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
  [[ "$output" == *"/jailrun/config.toml" ]]
}

# --- init ---

@test "config init creates default config" {
  run "$JAILRUN_LIB/config-cmd.sh" init
  [ "$status" -eq 0 ]
  [ -f "$CONFIG_FILE" ]
  grep -q "allowed_aws_profiles" "$CONFIG_FILE"
  grep -q "gh_token_name" "$CONFIG_FILE"
}

@test "config init refuses if config exists" {
  _create_config
  run "$JAILRUN_LIB/config-cmd.sh" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "config init --force overwrites existing config" {
  _create_config
  echo 'custom = "yes"' >> "$CONFIG_FILE"
  run "$JAILRUN_LIB/config-cmd.sh" init --force
  [ "$status" -eq 0 ]
  ! grep -q "custom" "$CONFIG_FILE"
  grep -q "allowed_aws_profiles" "$CONFIG_FILE"
}

# --- migrate ---

@test "config migrate converts shell config to TOML" {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/config" <<'EOF'
ALLOWED_AWS_PROFILES="default staging"
DEFAULT_AWS_PROFILE="default"
GH_TOKEN_NAME="classic"
SANDBOX_PASSTHROUGH_ENV="ANTHROPIC_API_KEY"
EOF
  run "$JAILRUN_LIB/config-cmd.sh" migrate
  [ "$status" -eq 0 ]
  [ -f "$CONFIG_FILE" ]
  grep -q '\[global\]' "$CONFIG_FILE"
  grep -q '"staging"' "$CONFIG_FILE"
  grep -q '"ANTHROPIC_API_KEY"' "$CONFIG_FILE"
}

# --- help ---

@test "config --help exits 0" {
  run "$JAILRUN_LIB/config-cmd.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"load"* ]]
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
  [[ "$output" == *"load"* ]]
}
