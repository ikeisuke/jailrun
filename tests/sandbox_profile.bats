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
    cat > "$XDG_CONFIG_HOME/jailrun/config" <<CONF
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_KEYCHAIN_SERVICE="github:classic"
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
  [[ "$output" == *"(deny file-write*"* ]]
  # Keychain access should be blocked
  [[ "$output" == *'(deny mach-lookup (global-name "com.apple.SecurityServer"))'* ]]
  [[ "$output" == *'(deny mach-lookup (global-name "com.apple.security.authtrampoline"))'* ]]
}

@test "exec.sh contains sandbox-exec and env unsets" {
  setup_jailrun_env

  run env -u _CREDENTIAL_GUARD_SANDBOXED sh -c '
    export JAILRUN_LIB="'"$JAILRUN_LIB"'"
    export WRAPPER_NAME=claude
    export XDG_CONFIG_HOME="'"$(mktemp -d)"'"
    mkdir -p "$XDG_CONFIG_HOME/jailrun"
    cat > "$XDG_CONFIG_HOME/jailrun/config" <<CONF
ALLOWED_AWS_PROFILES=""
DEFAULT_AWS_PROFILE=""
GH_KEYCHAIN_SERVICE="github:classic"
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
  [[ "$output" == *"-u AWS_ACCESS_KEY_ID"* ]]
  [[ "$output" == *"-u GH_TOKEN"* ]]
  [[ "$output" == *"_CREDENTIAL_GUARD_SANDBOXED=1"* ]]
  [[ "$output" == *"SSH_AUTH_SOCK="* ]]
  # DBUS_SESSION_BUS_ADDRESS unset is Linux-only (systemd-run)
  # On macOS, keychain is blocked via Seatbelt mach-lookup deny instead
}
