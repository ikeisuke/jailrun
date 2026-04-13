#!/usr/bin/env bats

load helpers

@test "sandbox-darwin.sh generates valid Seatbelt profile" {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    cat > "$XDG_CONFIG_HOME/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    cat "$_tmpdir/sandbox.sb"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"(version 1)"* ]]
  [[ "$output" == *"(allow default)"* ]]
  [[ "$output" == *"(deny file-read*"* ]]
  [[ "$output" == *".aws"* ]]
  [[ "$output" == *".ssh"* ]]
  [[ "$output" == *".gnupg"* ]]
  # Cloud service credentials
  [[ "$output" == *".config/gcloud"* ]]
  [[ "$output" == *".azure"* ]]
  [[ "$output" == *".docker"* ]]
  [[ "$output" == *".kube"* ]]
  [[ "$output" == *".terraform.d"* ]]
  [[ "$output" == *".vault-token"* ]]
  [[ "$output" == *"(deny file-write*"* ]]
  # Keychain access is intentionally allowed (apps need it for token refresh)
  [[ "$output" != *'(deny mach-lookup (global-name "com.apple.SecurityServer"))'* ]]
}

@test "seatbelt profile includes lockfile paths for auth refresh" {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    cat > "$XDG_CONFIG_HOME/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    cat "$_tmpdir/sandbox.sb"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  # proper-lockfile creates <target>.lock next to target; both must be writable
  [[ "$output" == *'.claude.lock")'* ]]
  [[ "$output" == *'.claude.json.lock")'* ]]
}

@test "seatbelt profile allows writing under Library/Keychains" {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    mkdir -p "$HOME/Library/Keychains"
    cat > "$XDG_CONFIG_HOME/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    grep -n "Library/Keychains" "$_tmpdir/sandbox.sb"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *'subpath "'$HOME'/Library/Keychains"'* ]]
}

@test "seatbelt profile includes temp config regex for atomic writes" {
  setup_jailrun_env
  export _CREDENTIAL_GUARD_SANDBOXED=""

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    cat > "$XDG_CONFIG_HOME/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    grep -n "claude\\\\.json\\\\.tmp" "$_tmpdir/sandbox.sb"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *'.claude\.json\.tmp'* ]]
}

@test "exec.sh contains sandbox-exec and env setup" {
  setup_jailrun_env

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    cat > "$XDG_CONFIG_HOME/jailrun/config.toml" <<CONF
[global]
allowed_aws_profiles = []
default_aws_profile = ""
gh_token_name = "classic"
CONF
    . "$JAILRUN_LIB/config.sh"
    . "$JAILRUN_LIB/credentials.sh"
    . "$JAILRUN_LIB/sandbox.sh"
    _setup_sandbox
    _build_exec_script
    cat "$_tmpdir/exec.sh"
  ' 2>/dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox-exec"* ]]
  # env vars are set via unset/export (not env -u/-E) to hide secrets from ps
  [[ "$output" == *"unset AWS_ACCESS_KEY_ID"* ]]
  [[ "$output" == *"unset GH_TOKEN"* ]]
  [[ "$output" == *'export _CREDENTIAL_GUARD_SANDBOXED="1"'* ]]
  [[ "$output" == *'export SSH_AUTH_SOCK=""'* ]]
}
