#!/usr/bin/env bats

# Tests for lib/platform/sandbox-linux-systemd.sh
# Verifies property file generation without requiring actual systemd-run.

load helpers

setup() {
  setup_jailrun_env
  _tmpdir=$(mktemp -d)
  export _tmpdir

  # Stub _detect_git_worktree (not testing git integration here)
  _detect_git_worktree() { :; }
  export -f _detect_git_worktree 2>/dev/null || true

  # Default empty values for optional variables
  _git_parent_toplevel=""
  _git_common_dir=""
  _other_worktrees=""
  _SANDBOX_ALLOW_WRITE_PATHS=""
  _SANDBOX_DENY_READ_PATHS=""
  _WRAPPER_NAME="claude"
}

teardown() {
  rm -rf "$_tmpdir"
}

# Helper: source the script and run _setup_sandbox, then cat the props file.
# _is_wsl2 is overridden via $_IS_WSL2_OVERRIDE (default: native / return 1) so
# tests are deterministic regardless of the host running the suite (macOS dev,
# Linux CI, WSL2 dev). Issue #90 / Unit 001.
run_setup_sandbox() {
  local _wsl_override="${_IS_WSL2_OVERRIDE:-return 1}"
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    _git_parent_toplevel="'"${_git_parent_toplevel:-}"'"
    _git_common_dir="'"${_git_common_dir:-}"'"
    _other_worktrees="'"${_other_worktrees:-}"'"
    _SANDBOX_ALLOW_WRITE_PATHS="'"${_SANDBOX_ALLOW_WRITE_PATHS:-}"'"
    _SANDBOX_DENY_READ_PATHS="'"${_SANDBOX_DENY_READ_PATHS:-}"'"
    _NETNS="'"${_NETNS:-}"'"
    JAILRUN_NETNS_HOST_IP="'"${JAILRUN_NETNS_HOST_IP:-10.200.0.1}"'"
    _WRAPPER_NAME="claude"
    export PROXY_ENABLED="'"${PROXY_ENABLED:-false}"'"
    _detect_git_worktree() { :; }
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _is_wsl2() { '"$_wsl_override"'; }
    _setup_sandbox
    cat "$_tmpdir/systemd-props"
  '
}

run_build_sandbox_exec() {
  local _mode="${1:-user}"
  run sh -c '
    _tmpdir="'"$_tmpdir"'"
    printf "%s\n" "SET PATH=/usr/bin" > "$_tmpdir/env-spec"
    printf "%s\n" "-p NetworkNamespacePath=/run/netns/agentns" > "$_tmpdir/systemd-props"
    _SYSTEMD_RUN_MODE="'"$_mode"'"
    _SYSTEMD_RUN_USER="jailrun-user"
    _SYSTEMD_RUN_GROUP="jailrun-group"
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    _build_sandbox_exec
  '
}

# --- Basic property generation ---

@test "generates NoNewPrivileges property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"NoNewPrivileges=yes"* ]]
}

@test "generates CapabilityBoundingSet empty" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"CapabilityBoundingSet="* ]]
}

@test "generates RestrictSUIDSGID property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"RestrictSUIDSGID=yes"* ]]
}

@test "generates LockPersonality property" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"LockPersonality=yes"* ]]
}

@test "generates ProtectSystem=strict" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectSystem=strict"* ]]
}

@test "generates ProtectHome=read-only" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectHome=read-only"* ]]
}

@test "generates SystemCallFilter" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"SystemCallFilter=@system-service"* ]]
  [[ "$output" == *"SystemCallFilter=~@privileged @debug"* ]]
}

@test "generates device restrictions" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"PrivateDevices=yes"* ]]
}

@test "generates kernel protection properties" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ProtectProc=invisible"* ]]
  [[ "$output" == *"ProtectClock=yes"* ]]
  [[ "$output" == *"ProtectHostname=yes"* ]]
  [[ "$output" == *"ProtectKernelLogs=yes"* ]]
  [[ "$output" == *"ProtectKernelModules=yes"* ]]
  [[ "$output" == *"ProtectKernelTunables=yes"* ]]
}

# --- PROXY_ENABLED ---

@test "PROXY_ENABLED=true adds IP address restrictions" {
  PROXY_ENABLED=true
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"IPAddressDeny=any"* ]]
  [[ "$output" == *"IPAddressAllow=127.0.0.0/8"* ]]
  [[ "$output" == *"IPAddressAllow=::1/128"* ]]
  [[ "$output" != *"IPAddressAllow=10.200.0.1/32"* ]]
}

@test "PROXY_ENABLED=true with netns allows host-side proxy IP" {
  PROXY_ENABLED=true
  _NETNS=agentns
  JAILRUN_NETNS_HOST_IP=10.200.0.1
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"IPAddressDeny=any"* ]]
  [[ "$output" == *"IPAddressAllow=10.200.0.1/32"* ]]
}

@test "PROXY_ENABLED=1 adds IP address restrictions" {
  PROXY_ENABLED=1
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"IPAddressDeny=any"* ]]
}

@test "PROXY_ENABLED=false does not add IPAddressDeny" {
  PROXY_ENABLED=false
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"IPAddressDeny=any"* ]]
}

@test "PROXY_ENABLED unset does not add IPAddressDeny" {
  unset PROXY_ENABLED
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"IPAddressDeny=any"* ]]
}

# --- Custom paths ---

@test "SANDBOX_ALLOW_WRITE_PATHS adds ReadWritePaths" {
  _write_dir=$(mktemp -d)
  _SANDBOX_ALLOW_WRITE_PATHS="$_write_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_write_dir"* ]]
  rm -rf "$_write_dir"
}

@test "SANDBOX_DENY_READ_PATHS adds InaccessiblePaths for directories" {
  _deny_dir=$(mktemp -d)
  _SANDBOX_DENY_READ_PATHS="$_deny_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"InaccessiblePaths=$_deny_dir"* ]]
  rm -rf "$_deny_dir"
}

@test "SANDBOX_DENY_READ_PATHS adds InaccessiblePaths for files" {
  _deny_file=$(mktemp)
  _SANDBOX_DENY_READ_PATHS="$_deny_file"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"InaccessiblePaths=$_deny_file"* ]]
  rm -f "$_deny_file"
}

@test "SANDBOX_DENY_READ_PATHS skips non-existent paths" {
  _SANDBOX_DENY_READ_PATHS="/nonexistent/path/for/testing"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"InaccessiblePaths=/nonexistent/path/for/testing"* ]]
}

# --- Git worktree ---

@test "git_parent_toplevel adds ReadWritePaths" {
  _wt_dir=$(mktemp -d)
  _git_parent_toplevel="$_wt_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_wt_dir"* ]]
  rm -rf "$_wt_dir"
}

@test "git_common_dir fallback adds ReadWritePaths when no parent_toplevel" {
  _common_dir=$(mktemp -d)
  _git_parent_toplevel=""
  _git_common_dir="$_common_dir"
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_common_dir"* ]]
  rm -rf "$_common_dir"
}

# --- ReadWritePaths for cwd and tmpdir ---

@test "includes ReadWritePaths for current directory" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  # PWD should appear as ReadWritePaths
  [[ "$output" == *"ReadWritePaths="* ]]
}

@test "includes ReadWritePaths for tmpdir" {
  run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"ReadWritePaths=$_tmpdir"* ]]
}

# --- WSL2 detection and PrivateDevices conditional (Issue #90 / Unit 001) ---

# _is_wsl2 contract tests: source the script and invoke _is_wsl2 with the
# `uname` shell function overridden. These exercise the real implementation
# (lowercase + microsoft|wsl2 substring match) rather than the helper override
# used by props integration tests above.
#
# Helper: run _is_wsl2 with the given uname() body and return its exit code.
run_is_wsl2() {
  local _uname_body="$1"
  run sh -c '
    . "'"$JAILRUN_LIB"'/platform/sandbox-linux-systemd.sh"
    uname() { '"$_uname_body"'; }
    _is_wsl2
  '
}

@test "_is_wsl2 detects microsoft-standard-WSL2 kernel" {
  run_is_wsl2 "printf '%s\n' '5.15.167.4-microsoft-standard-WSL2'"
  [ "$status" -eq 0 ]
}

@test "_is_wsl2 detects legacy microsoft-standard kernel" {
  run_is_wsl2 "printf '%s\n' '4.19.128-microsoft-standard'"
  [ "$status" -eq 0 ]
}

@test "_is_wsl2 rejects native Linux kernel" {
  run_is_wsl2 "printf '%s\n' '6.6.0-arch1-1'"
  [ "$status" -eq 1 ]
}

@test "_is_wsl2 returns 1 when uname output is empty" {
  run_is_wsl2 "printf ''"
  [ "$status" -eq 1 ]
}

@test "_is_wsl2 returns 1 when uname command fails" {
  run_is_wsl2 "return 1"
  [ "$status" -eq 1 ]
}

# Integration: PrivateDevices=yes conditional on _is_wsl2

@test "omits PrivateDevices=yes on WSL2" {
  _IS_WSL2_OVERRIDE="return 0" run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"PrivateDevices=yes"* ]]
}

@test "emits PrivateDevices=yes on native Linux" {
  _IS_WSL2_OVERRIDE="return 1" run_setup_sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"PrivateDevices=yes"* ]]
}

# --- systemd-run command generation ---

@test "_build_sandbox_exec uses user manager by default" {
  run_build_sandbox_exec user
  [ "$status" -eq 0 ]
  [[ "$output" == *"exec systemd-run"* ]]
  [[ "$output" == *"--user --pty --wait --collect --same-dir"* ]]
  [[ "$output" != *"sudo -n systemd-run"* ]]
}

@test "_build_sandbox_exec uses sudo systemd-run in root netns fallback mode" {
  run_build_sandbox_exec root
  [ "$status" -eq 0 ]
  [[ "$output" == *"exec sudo -n systemd-run"* ]]
  [[ "$output" == *"--pty --wait --collect --same-dir"* ]]
  [[ "$output" == *'User=jailrun-user'* ]]
  [[ "$output" == *'Group=jailrun-group'* ]]
  [[ "$output" != *"--user --pty"* ]]
}
